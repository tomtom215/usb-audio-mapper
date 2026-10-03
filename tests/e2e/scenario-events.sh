#!/bin/bash
# Guest scenario: mappings must survive everything that happens to a running
# system after setup. Three identical devices on 1-1, 1-2 and 1-3.1 (hub 1-3).
#   - udevd restart, full system-wide "udevadm trigger" (change and add)
#   - re-enumeration in reverse order, so card numbers change
#   - rapid unplug/replug flapping without waiting for udev
#   - replugging the hub (the device behind it re-enumerates)
#   - all of the above while one card is open and playing audio
# shellcheck disable=SC2016  # check() eval()s its single-quoted condition
M=/opt/usb-audio-mapper.sh
declare -A WANT=(["1-1"]=mic-left ["1-2"]=mic-right ["1-3.1"]=mic-hub)

result() { echo "E2E-RESULT: $1 $2 ${3:-}"; }
check() { if eval "$2"; then result "$1" PASS "$3"; else result "$1" FAIL "$3"; fi; }
card_of() {
    local c
    for c in /sys/bus/usb/devices/"$1":1.0/sound/card*; do
        [[ -e "$c" ]] && basename "$c"
        return
    done
}
id_of() { cat "/sys/bus/usb/devices/$1:1.0/sound/$(card_of "$1")/id" 2>/dev/null; }
deauth() { echo 0 >"/sys/bus/usb/devices/$1/authorized"; }
auth() { echo 1 >"/sys/bus/usb/devices/$1/authorized"; }
check_all() { # phase
    local port want card link
    for port in 1-1 1-2 1-3.1; do
        want=${WANT[$port]}
        card=$(card_of "$port")
        link=$(readlink -f "/dev/sound/by-id/$want" 2>/dev/null)
        check "$1:id[$port]" '[[ "$(id_of "$port")" == "$want" ]]' "got=$(id_of "$port") ($card)"
        check "$1:link[$port]" '[[ "$link" == "/dev/snd/controlC${card#card}" ]]' "${link:-missing}"
    done
}
cards_by_port() {
    local p
    for p in 1-1 1-2 1-3.1; do printf '%s=%s ' "$p" "$(card_of "$p")"; done
}

echo "E2E-INFO: udev=$(udevadm --version) kernel=$(uname -r)"
for port in 1-1 1-2 1-3.1; do
    bash "$M" -n -v 46f4 -p 0002 -u "$port" -f "${WANT[$port]}" </dev/null >/dev/null 2>&1
done
check_all mapped
log0=$(wc -l </run/udevd.log)

# Keep mic-left busy for the rest of the scenario (QEMU usb-audio is playback).
aplay -q -D hw:CARD=mic-left -f S16_LE -r 48000 -c 2 -d 600 /dev/zero 2>/tmp/aplay.err &
player=$!
sleep 1
check busy:player-started 'kill -0 $player' "pid=$player"

# 1. udevd restart (daemon restart, as on a package upgrade).
pkill -x systemd-udevd
for _ in $(seq 1 50); do
    pgrep -x systemd-udevd >/dev/null || break
    sleep 0.1
done
/usr/lib/systemd/systemd-udevd >>/run/udevd.log 2>&1 &
for _ in $(seq 1 100); do
    [ -S /run/udev/control ] && break
    sleep 0.1
done
udevadm settle
check_all after-udevd-restart

# 2. Full system-wide triggers.
udevadm trigger --action=change
udevadm settle --timeout=60
check_all after-trigger-change-all
udevadm trigger --action=add
udevadm settle --timeout=60
check_all after-trigger-add-all

# 3. Re-enumerate the two idle devices in reverse order so card numbers move.
#    (mic-left stays plugged: it is busy.)
before=$(cards_by_port)
deauth 1-3.1
deauth 1-2
udevadm settle
auth 1-2
udevadm settle
auth 1-3.1
udevadm settle
after=$(cards_by_port)
echo "E2E-INFO: cards before [$before] after [$after]"
check_all after-reverse-reenumeration

# 4. Unplug both idle devices, then plug them in the opposite order so the
#    free card numbers are handed out differently.
deauth 1-2
deauth 1-3.1
udevadm settle
auth 1-3.1
udevadm settle
auth 1-2
udevadm settle
echo "E2E-INFO: cards now [$(cards_by_port)]"
check_all after-swapped-plug-order

# 5. Flapping: ten fast unplug/replug cycles without waiting for udev.
for _ in $(seq 1 10); do
    deauth 1-2
    auth 1-2
done
udevadm settle --timeout=60
sleep 1
udevadm settle
check_all after-flapping

# 6. Hub replug: the device behind it disappears and re-enumerates.
deauth 1-3
udevadm settle
check hub:child-gone '[[ -z "$(card_of 1-3.1)" ]]'
auth 1-3
udevadm settle --timeout=60
sleep 1
udevadm settle
check_all after-hub-replug

# The busy card kept playing through all of it.
check busy:player-survived 'kill -0 $player' "$(head -n1 /tmp/aplay.err 2>/dev/null)"
kill "$player" 2>/dev/null
wait "$player" 2>/dev/null

# Only expected udevd chatter: nothing about our rules or card ids.
tail -n +"$((log0 + 1))" /run/udevd.log | grep -E '99-usb-soundcards|ATTR[{]id[}]|/id' >/tmp/ourlog
grc=$?
cat /tmp/ourlog
check udevd-no-errors '[[ $grc -eq 1 ]]' "grep rc=$grc"
