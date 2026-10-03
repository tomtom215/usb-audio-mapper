#!/bin/bash
# Guest scenario (run by qemu-e2e.sh): three IDENTICAL usb-audio devices
# (46f4:0002) on ports 1-1, 1-2 and 1-3.1 (behind a hub on 1-3).
# Exercises the mapper exactly as an operator would, against the real kernel
# and systemd-udevd, and checks the kernel's own view afterwards.
# shellcheck disable=SC2016  # check() eval()s its single-quoted condition
M=/opt/usb-audio-mapper.sh
RULES=/etc/udev/rules.d/99-usb-soundcards.rules
declare -A WANT=(["1-1"]=mic-left ["1-2"]=mic-right ["1-3.1"]=mic-hub)

result() { echo "E2E-RESULT: $1 $2 ${3:-}"; }
echo "E2E-INFO: udev=$(udevadm --version) kernel=$(uname -r) bash=$BASH_VERSION"
check() { if eval "$2"; then result "$1" PASS "$3"; else result "$1" FAIL "$3"; fi; }
card_of() {
    local c
    for c in /sys/bus/usb/devices/"$1":1.0/sound/card*; do
        [[ -e "$c" ]] && basename "$c"
        return
    done
}
id_of() { cat "/sys/bus/usb/devices/$1:1.0/sound/$(card_of "$1")/id" 2>/dev/null; }
replug() {
    echo 0 >"/sys/bus/usb/devices/$1/authorized"
    udevadm settle
    echo 1 >"/sys/bus/usb/devices/$1/authorized"
    udevadm settle --timeout=30
}
check_all() { # phase
    local port want card link
    for port in 1-1 1-2 1-3.1; do
        want=${WANT[$port]}
        card=$(card_of "$port")
        link=$(readlink -f "/dev/sound/by-id/$want" 2>/dev/null)
        check "$1:id[$port]" '[[ "$(id_of "$port")" == "$want" ]]' "got=$(id_of "$port") want=$want"
        check "$1:symlink[$port]" '[[ "$link" == "/dev/snd/controlC${card#card}" ]]' "$want -> ${link:-missing} ($card)"
    done
}

# Legacy content that must be migrated (v3 inert line, LyreBird 1.2.1 form)
# or preserved (a foreign rule).
mkdir -p /etc/udev/rules.d
cat >"$RULES" <<'RULES'
# operator rule - keep
SUBSYSTEM=="input", ATTRS{idVendor}=="1234", MODE="0660"
# USB Sound Card: QEMU\nSUBSYSTEM=="sound", ATTRS{idVendor}=="46f4", ATTRS{idProduct}=="0002", ENV{ID_PATH}=="pci-0000:00:03.0-usb-0:1", ATTR{id}="mic-left", SYMLINK+="sound/by-id/mic-left"
# USB Sound Card: QEMU
SUBSYSTEM=="sound", ATTRS{idVendor}=="46f4", ATTRS{idProduct}=="0002", ENV{ID_PATH}=="pci-0000:00:03.0-usb-0:1", ATTR{id}="mic-right", SYMLINK+="sound/by-id/mic-right"
RULES

bash "$M" -n -v 46f4 -p 0002 -f mic-x </dev/null
rc=$?
check ambiguous-vidpid-refused '[[ $rc -eq 5 ]]' "rc=$rc"

bash "$M" -n -v 46f4 -p 0002 -u 1-1 -f mic-left </dev/null
rc=$?
check map-by-port-rc '[[ $rc -eq 0 ]]' "rc=$rc"
bash "$M" -n -v 46f4 -p 0002 -u usb-0000:00:03.0-2 -f mic-right </dev/null
rc=$?
check map-by-proc-port-rc '[[ $rc -eq 0 ]]' "rc=$rc"
bash "$M" -n --card "$(card_of 1-3.1 | tr -dc 0-9)" -f mic-hub </dev/null
rc=$?
check map-by-card-rc '[[ $rc -eq 0 ]]' "rc=$rc"

echo "--- rules file"
cat "$RULES"
echo "---"
if udevadm verify --help >/dev/null 2>&1; then
    check rules-verify 'udevadm verify --no-style "$RULES" >/dev/null 2>&1'
else
    result rules-verify SKIP "udevadm $(udevadm --version) has no verify command"
fi
check legacy-migrated '! grep -qE "ENV[{]ID_PATH[}]==\"pci-0000:00:03.0-usb-0:1\"|USB Sound Card" "$RULES"'
check foreign-rule-kept 'grep -qx "SUBSYSTEM==\"input\", ATTRS{idVendor}==\"1234\", MODE=\"0660\"" "$RULES"'

check_all immediate # applied without replug or reboot

# A rule for the hub's port (1-3) with the microphones' id must not capture
# the microphone behind that hub (1-3.1): udev matches ATTRS{} and KERNELS on
# the same ancestor, and the hub has a different id.
bash "$M" -n -v 46f4 -p 0002 -u 1-3 -f decoy </dev/null >/dev/null 2>&1
replug 1-3.1
check hub-port-rule-not-inherited '[[ "$(id_of 1-3.1)" == mic-hub ]]' "id=$(id_of 1-3.1)"
bash "$M" --remove decoy </dev/null >/dev/null 2>&1
for p in 1-1 1-2 1-3.1; do replug "$p"; done
check_all after-replug

# Idempotence: re-running a mapping changes nothing and still verifies.
cp "$RULES" /tmp/before
bash "$M" -n -v 46f4 -p 0002 -u 1-1 -f mic-left </dev/null
rc=$?
check rerun-rc '[[ $rc -eq 0 ]]' "rc=$rc"
check rerun-same-file 'cmp -s "$RULES" /tmp/before'

# Name conflict: asking card at 1-2 to take a name another card holds fails
# loudly. udevd legitimately logs EEXIST during this step, so the log check
# below skips the lines written between these two marks.
log_mark_a=$(wc -l </run/udevd.log)
bash "$M" -n -v 46f4 -p 0002 -u 1-2 -f mic-left </dev/null
rc=$?
check conflict-detected '[[ $rc -eq 6 ]]' "rc=$rc"
bash "$M" -n -v 46f4 -p 0002 -u 1-2 -f mic-right </dev/null >/dev/null 2>&1
bash "$M" -n -v 46f4 -p 0002 -u 1-1 -f mic-left </dev/null >/dev/null 2>&1
for p in 1-1 1-2; do replug "$p"; done
log_mark_b=$(wc -l </run/udevd.log)
check_all after-conflict-repair

# Removal: the name no longer applies after reconnect.
bash "$M" --remove mic-hub </dev/null
rc=$?
check remove-rc '[[ $rc -eq 0 ]]' "rc=$rc"
replug 1-3.1
check removed-not-applied '[[ "$(id_of 1-3.1)" != "mic-hub" ]]' "id=$(id_of 1-3.1)"
# Interactive wizard on the real system: pick the hub card, name it, confirm.
# (Identical devices are connected, so the wizard must not offer "any port".)
hubcard=$(card_of 1-3.1 | tr -dc 0-9)
printf '%s\nmic-hub\ny\n' "$hubcard" | bash "$M" >/tmp/wiz.log 2>&1
rc=$?
cat /tmp/wiz.log
check wizard-rc '[[ $rc -eq 0 ]]' "rc=$rc"
check wizard-port-forced 'grep -q "identical device(s) also connected" /tmp/wiz.log'
check wizard-applied '[[ "$(id_of 1-3.1)" == mic-hub ]]' "id=$(id_of 1-3.1)"

# Documented extension point (DOCUMENTATION.md section 8): a later rules file
# keyed on the mapper's marker applies to that card's control node only.
echo "lyre:x:4242:" >>/etc/group
printf '%s\n' 'SUBSYSTEM=="sound", KERNEL=="controlC*", ENV{USB_AUDIO_MAPPER}=="mic-left", GROUP="lyre", MODE="0640"' \
    >/etc/udev/rules.d/99-zz-local.rules
udevadm control --reload
replug 1-1
c=$(card_of 1-1)
st=$(stat -c '%a %G' "/dev/snd/controlC${c#card}")
check local-rule-applies '[[ "$st" == "640 lyre" ]]' "controlC${c#card}: $st"
st2=$(stat -c '%a %G' "/dev/snd/controlC$(card_of 1-2 | tr -dc 0-9)")
check local-rule-scoped '[[ "$st2" != "640 lyre" ]]' "other card: $st2"
rm -f /etc/udev/rules.d/99-zz-local.rules

# udevd must not complain about our rules or about writing the card id.
awk -v a="$log_mark_a" -v b="$log_mark_b" 'NR <= a || NR > b' /run/udevd.log \
    | grep -E '99-usb-soundcards|ATTR[{]id[}]|/id' >/tmp/ourlog
grc=$?
echo "--- udevd log lines about the mapping (grep rc=$grc):"
cat /tmp/ourlog
check udevd-no-errors '[[ $grc -eq 1 ]]' "grep rc=$grc (1 = no matching lines)"
echo "E2E-RULES-BEGIN"
cat "$RULES"
echo "E2E-RULES-END"
