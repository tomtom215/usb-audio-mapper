#!/usr/bin/env bash
# Run the full end-to-end suite (each step boots a fresh QEMU guest):
#   1. operator workflow on three identical devices (2 root ports + hub)
#   2. events: udevd restart, system-wide triggers, re-enumeration with card
#      numbers changing, flapping, hub replug, a busy device
#   3. reboots with the rules from step 1: coldplug (drivers before udevd, as
#      at boot), coldplug with the first device absent (card numbers shift),
#      and hotplug order
#   4. USB bus renumbering: map on two controllers, reboot with the controller
#      drivers loaded in the opposite order (needs ohci-pci as a module)
# Usage: tests/e2e/run.sh [MAPPER_SCRIPT]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mapper=${1:-$here/../../usb-audio-mapper.sh}
# shellcheck disable=SC2054  # commas are QEMU -device property syntax
devices=(
    -device usb-audio,audiodev=snd0,bus=xhci.0,port=1
    -device usb-audio,audiodev=snd0,bus=xhci.0,port=2
    -device usb-hub,bus=xhci.0,port=3
    -device usb-audio,audiodev=snd0,bus=xhci.0,port=3.1
)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
rc=0

run_step() { # label log scenario [qemu args...]   (env passed through)
    local label=$1 log=$out/$2 scenario=$3
    shift 3
    echo "== $label"
    if ! "$here/qemu-e2e.sh" "$mapper" "$here/$scenario" "$@" >"$log" 2>&1; then
        rc=1
        echo "   FAILED; guest log follows" >&2
        tr -d '\r' <"$log" | sed -n '/E2E-BOOTED/,/E2E-DONE/p' >&2
    fi
    tr -d '\r' <"$log" | grep -E 'E2E-(RESULT|INFO)' || true
}
rules_from() { tr -d '\r' <"$out/$1" | sed -n '/^E2E-RULES-BEGIN$/,/^E2E-RULES-END$/p' | sed '1d;$d'; }

run_step "operator workflow" ops.log scenario-identical-devices.sh "${devices[@]}"
rules_from ops.log >"$out/rules"
[[ -s "$out/rules" ]] || {
    echo "no rules captured from the operator workflow" >&2
    exit 1
}

run_step "events on a running system" events.log scenario-events.sh "${devices[@]}"

E2E_PRELOAD_RULES="$out/rules" E2E_COLDPLUG=1 \
    run_step "reboot (coldplug)" boot1.log scenario-boot.sh "${devices[@]}"
E2E_PRELOAD_RULES="$out/rules" E2E_COLDPLUG=1 \
    run_step "reboot (coldplug, first device absent)" boot2.log scenario-boot.sh "${devices[@]:2}"
E2E_PRELOAD_RULES="$out/rules" E2E_COLDPLUG=0 \
    run_step "reboot (drivers after udevd)" boot3.log scenario-boot.sh "${devices[@]}"

# shellcheck disable=SC2054
bus_devices=(
    -device pci-ohci,id=ohci
    -device usb-audio,audiodev=snd0,bus=xhci.0,port=1
    -device usb-audio,audiodev=snd0,bus=ohci.0,port=1
)
kver_root=${E2E_KERNEL_ROOT:+-d $E2E_KERNEL_ROOT}
kver=${E2E_KERNEL_VERSION:-$(find "${E2E_KERNEL_ROOT:-}/lib/modules" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -n1)}
# shellcheck disable=SC2086  # kver_root is "-d DIR" or empty
if modprobe $kver_root -S "$kver" --show-depends ohci-pci 2>/dev/null | grep -q '^insmod'; then
    E2E_COLDPLUG=1 E2E_MODULES="xhci-pci ohci-pci snd-usb-audio" \
        run_step "bus renumbering: map (xHCI driver first)" bus1.log scenario-bus-map.sh "${bus_devices[@]}"
    rules_from bus1.log >"$out/bus-rules"
    E2E_PRELOAD_RULES="$out/bus-rules" E2E_COLDPLUG=1 E2E_MODULES="ohci-pci xhci-pci snd-usb-audio" \
        run_step "bus renumbering: reboot (OHCI driver first)" bus2.log scenario-bus-check.sh "${bus_devices[@]}"
else
    echo "== bus renumbering: SKIPPED (ohci-pci is built into kernel $kver; use E2E_KERNEL_ROOT from fetch-deps.sh)"
fi
exit "$rc"
