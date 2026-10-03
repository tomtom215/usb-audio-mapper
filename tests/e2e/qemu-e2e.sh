#!/usr/bin/env bash
# End-to-end harness: boots a throwaway QEMU guest with real kernel USB audio
# (qemu-xhci + emulated usb-audio devices -> snd-usb-audio) and a real
# systemd-udevd, then runs a guest scenario script against the mapper.
#
# Usage: tests/e2e/qemu-e2e.sh MAPPER_SCRIPT SCENARIO_SCRIPT [EXTRA_QEMU_ARGS...]
# Environment: E2E_KERNEL_ROOT, E2E_KERNEL_VERSION, E2E_TIMEOUT (seconds),
# E2E_PRELOAD_RULES, E2E_UDEV_ROOT, E2E_MODULES, E2E_COLDPLUG (1 = load drivers
# before udevd starts, as at boot).
#
# The guest's console output is printed to stdout. Scenario scripts report
# results as lines "E2E-RESULT: <name> PASS|FAIL <detail>" and the harness exits
# non-zero if any FAIL line (or no RESULT line at all) is seen.
#
# Host requirements: qemu-system-x86_64, a kernel image + modules for it,
# bash/coreutils/grep/sed, udevadm (systemd >= 245), kmod, lsusb, cpio.
# Override the kernel with E2E_KERNEL_VERSION (default: newest in /lib/modules).
# No KVM is required (TCG is used when /dev/kvm is absent).

set -euo pipefail

die() {
    printf 'qemu-e2e: %s\n' "$*" >&2
    exit 2
}

[[ $# -ge 2 ]] || die "usage: $0 MAPPER_SCRIPT SCENARIO_SCRIPT [QEMU_ARGS...]"
mapper=$(readlink -f "$1")
scenario=$(readlink -f "$2")
shift 2
[[ -f "$mapper" ]] || die "mapper script not found: $mapper"
[[ -f "$scenario" ]] || die "scenario script not found: $scenario"

# E2E_KERNEL_ROOT: an extracted kernel package (boot/ + lib/modules/), e.g.
# from fetch-deps.sh. Default: the host's /boot and /lib/modules.
kroot=""
if [[ -n "${E2E_KERNEL_ROOT:-}" ]]; then
    kroot=$(readlink -f "$E2E_KERNEL_ROOT")
fi
kver=${E2E_KERNEL_VERSION:-$(find "$kroot/lib/modules" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -n1)}
kimg=$kroot/boot/vmlinuz-$kver
[[ -r "$kimg" ]] || die "kernel image not readable: $kimg"
for t in qemu-system-x86_64 cpio udevadm kmod lsusb depmod; do
    command -v "$t" >/dev/null 2>&1 || die "missing host tool: $t"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/qemu-e2e.XXXXXX")
trap 'rm -rf "$work"' EXIT
root=$work/root
mkdir -p "$root"/{etc/udev/rules.d,proc,sys,dev,run,tmp,root,mnt} \
    "$root"/usr/{bin,sbin,lib/udev,lib64}
# Merged-/usr layout so /lib, /bin, ... paths reported by ldd/modprobe resolve.
for d in bin sbin lib lib64; do ln -s "usr/$d" "$root/$d"; done

# Copy a binary plus its shared-library closure, preserving paths.
copy_bin() {
    local src lib
    src=$(command -v "$1") || die "missing guest tool: $1"
    src=$(readlink -f "$src")
    install -D -m 0755 "$src" "$root/usr/bin/$1"
    while read -r lib; do
        [[ -n "$lib" && -e "$lib" ]] || continue
        [[ -e "$root$lib" ]] || install -D -m 0755 "$(readlink -f "$lib")" "$root$lib"
    done < <(ldd "$src" 2>/dev/null | grep -oE '/[^ ]+' || true)
}

# GNU userland so the mapper runs against the same tools it meets in the field.
for b in bash grep sed tr cut head tail mktemp dirname basename chmod mv cp cat \
    rm mkdir ls readlink sleep xargs sha256sum stat sync env wc sort uniq \
    mount umount seq udevadm kmod lsusb tput id find diff cmp tee date timeout \
    awk flock logger ln uname pkill pgrep sleep ps; do
    copy_bin "$b"
done
command -v aplay >/dev/null 2>&1 && copy_bin aplay
ln -s bash "$root/usr/bin/sh"
for b in modprobe insmod depmod lsmod; do ln -s /usr/bin/kmod "$root/usr/sbin/$b"; done

# E2E_UDEV_ROOT: an extracted udev/systemd package tree (e.g. Debian 11's
# systemd 247) whose udevadm and stock rules replace the host's, to test
# against older udev releases.
if [[ -n "${E2E_UDEV_ROOT:-}" ]]; then
    alt=$(readlink -f "$E2E_UDEV_ROOT")
    alt_bin=$(find "$alt/bin" "$alt/usr/bin" -maxdepth 1 -name udevadm -type f 2>/dev/null | head -n1 || true)
    [[ -n "$alt_bin" ]] || die "no udevadm under $alt"
    alt_lib=$(find "$alt" -name 'libsystemd-shared-*.so' -type f | head -n1 || true)
    alt_rules=$(find "$alt/lib/udev/rules.d" "$alt/usr/lib/udev/rules.d" -maxdepth 0 -type d 2>/dev/null | head -n1 || true)
    install -D -m 0755 "$alt_bin" "$root/usr/bin/udevadm"
    # systemd < 247 ships systemd-udevd as a separate binary, not a symlink.
    alt_udevd=$(find "$alt/lib/systemd" "$alt/usr/lib/systemd" -maxdepth 1 -name systemd-udevd -type f 2>/dev/null | head -n1 || true)
    if [[ -n "$alt_udevd" ]]; then
        udevd_override=$alt_udevd
    fi
    if [[ -n "$alt_lib" ]]; then
        # Same path relative to the package root (matches the binary's RUNPATH).
        rel=${alt_lib#"$alt"}
        rel=/usr${rel#/usr}
        install -D -m 0644 "$alt_lib" "$root$rel"
    fi
    while read -r lib; do
        [[ -n "$lib" && -e "$lib" && ! -e "$root$lib" ]] && install -D -m 0755 "$(readlink -f "$lib")" "$root$lib"
    done < <(LD_LIBRARY_PATH="$(dirname "${alt_lib:-/nonexistent}")" ldd "$alt_bin" | grep -oE '/[^ ]+' | grep -v "^$alt" || true)
    [[ -n "$alt_rules" ]] || die "no udev rules.d under $alt"
    cp -a "$alt_rules" "$root/usr/lib/udev/"
else
    cp -a /usr/lib/udev/rules.d "$root/usr/lib/udev/"
fi
for f in /usr/lib/udev/hwdb.bin /etc/udev/hwdb.bin; do
    [[ -f "$f" ]] && install -D -m 0644 "$f" "$root$f"
done
for d in /usr/share/terminfo /usr/lib/terminfo /usr/share/alsa; do
    if [[ -d "$d" ]]; then
        mkdir -p "$root$(dirname "$d")"
        cp -a "$d" "$root$(dirname "$d")/"
    fi
done
for f in /usr/share/misc/usb.ids /var/lib/usbutils/usb.ids; do
    [[ -f "$f" ]] && install -D -m 0644 "$(readlink -f "$f")" "$root$f"
done
printf 'root:x:0:0:root:/root:/bin/bash\n' >"$root/etc/passwd"
printf 'root:x:0:\naudio:x:29:\n' >"$root/etc/group"

# Kernel modules: xhci-pci + snd-usb-audio and their dependency closure.
moddir=/lib/modules/$kver
# E2E_MODULES: modules to load in the guest, in this order (host controller
# drivers first). Changing the order changes USB bus numbering.
modules=${E2E_MODULES:-xhci-pci snd-usb-audio}
modprobe_args=(-S "$kver")
[[ -n "$kroot" ]] && modprobe_args+=(-d "$kroot")
for m in $modules; do
    modprobe "${modprobe_args[@]}" --show-depends "$m" >/dev/null 2>&1 \
        || die "kernel $kver: cannot resolve module $m (missing modules.dep? run depmod)"
    while read -r kind path _; do
        [[ "$kind" == insmod ]] || continue
        # Builtins are listed as "builtin <name>"; only real files are copied.
        install -D -m 0644 "$path" "$root${path#"$kroot"}"
    done < <(modprobe "${modprobe_args[@]}" --show-depends "$m" 2>/dev/null || true)
done
cp "$kroot$moddir"/modules.{order,builtin,builtin.modinfo} "$root$moddir/" 2>/dev/null || true
depmod -b "$root" "$kver"

mkdir -p "$root/usr/lib/systemd"
if [[ -n "${udevd_override:-}" ]]; then
    install -D -m 0755 "$udevd_override" "$root/usr/lib/systemd/systemd-udevd"
else
    ln -s /usr/bin/udevadm "$root/usr/lib/systemd/systemd-udevd"
fi

printf 'E2E_MODULES="%s"\nE2E_COLDPLUG="%s"\n' "$modules" "${E2E_COLDPLUG:-0}" >"$root/etc/e2e.conf"
install -D -m 0755 "$mapper" "$root/opt/usb-audio-mapper.sh"
install -D -m 0755 "$scenario" "$root/opt/scenario.sh"
# E2E_PRELOAD_RULES: a rules file present before udevd starts, i.e. the state
# of a machine that boots with an existing mapping.
if [[ -n "${E2E_PRELOAD_RULES:-}" ]]; then
    install -D -m 0644 "$E2E_PRELOAD_RULES" "$root/etc/udev/rules.d/99-usb-soundcards.rules"
fi

cat >"$root/init" <<'INIT'
#!/bin/bash
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /tmp
mkdir -p /run/udev
. /etc/e2e.conf
start_udevd() {
    /usr/lib/systemd/systemd-udevd >>/run/udevd.log 2>&1 &
    for _ in $(seq 1 100); do [ -S /run/udev/control ] && break; sleep 0.1; done
}
load_modules() { for m in $E2E_MODULES; do modprobe "$m"; done; }
if [ "$E2E_COLDPLUG" = 1 ]; then
    # Real-boot order: devices exist before udevd runs; udev then replays
    # "add" events for everything (systemd-udev-trigger.service).
    load_modules
    sleep 2
    start_udevd
else
    start_udevd
    load_modules
fi
udevadm trigger --action=add --type=subsystems
udevadm trigger --action=add --type=devices
udevadm settle --timeout=60
echo "E2E-BOOTED udev=$(udevadm --version)"
bash /opt/scenario.sh 2>&1
echo "E2E-DONE"
echo o >/proc/sysrq-trigger 2>/dev/null
sync
exec /usr/bin/bash -c 'echo 1 > /proc/sys/kernel/sysrq; echo o > /proc/sysrq-trigger; sleep 5'
INIT
chmod 0755 "$root/init"

(cd "$root" && find . -print0 | cpio --null -o -H newc --quiet) | gzip -1 >"$work/initrd.gz"

accel=tcg
[[ -w /dev/kvm ]] && accel=kvm

log=$work/console.log
timeout "${E2E_TIMEOUT:-600}" qemu-system-x86_64 \
    -machine q35,accel=$accel -m 1024 -smp 2 -nographic -no-reboot \
    -kernel "$kimg" -initrd "$work/initrd.gz" \
    -append "console=ttyS0 rdinit=/init panic=-1 loglevel=3 sysrq_always_enabled=1" \
    -audiodev none,id=snd0 \
    -device qemu-xhci,id=xhci \
    "$@" </dev/null | tee "$log" | tr -d '\r' || true

grep -q 'E2E-RESULT:' "$log" || {
    echo "qemu-e2e: no results produced" >&2
    exit 1
}
if grep -q 'E2E-RESULT: .* FAIL' "$log"; then exit 1; fi
exit 0
