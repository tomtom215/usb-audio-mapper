#!/bin/bash
# Guest scenario (run by qemu-e2e.sh with E2E_PRELOAD_RULES): the rules file
# exists before the devices are enumerated, as on a reboot. Checks that every
# connected, mapped device was named during enumeration, with no help from the
# mapper. Ports with nothing plugged in are reported, not failed.
declare -A WANT=(["1-1"]=mic-left ["1-2"]=mic-right ["1-3.1"]=mic-hub)
echo "E2E-INFO: udev=$(udevadm --version) kernel=$(uname -r) $(grep -o 'E2E_COLDPLUG="[01]"' /etc/e2e.conf)"
seen=0
for port in 1-1 1-2 1-3.1; do
    card=""
    for c in /sys/bus/usb/devices/"$port":1.0/sound/card*; do [[ -e "$c" ]] && card=$(basename "$c"); done
    if [[ -z "$card" ]]; then
        echo "E2E-INFO: nothing on $port"
        continue
    fi
    seen=$((seen + 1))
    id=$(cat "/sys/class/sound/$card/id")
    link=$(readlink -f "/dev/sound/by-id/${WANT[$port]}")
    [[ "$id" == "${WANT[$port]}" ]] && r=PASS || r=FAIL
    echo "E2E-RESULT: boot:id[$port] $r got=$id want=${WANT[$port]} ($card)"
    [[ "$link" == "/dev/snd/controlC${card#card}" ]] && r=PASS || r=FAIL
    echo "E2E-RESULT: boot:link[$port] $r ${WANT[$port]} -> ${link:-missing}"
done
[[ $seen -gt 0 ]] && r=PASS || r=FAIL
echo "E2E-RESULT: boot:devices-present $r count=$seen"
grep -E '99-usb-soundcards|ATTR[{]id[}]' /run/udevd.log && r=FAIL || r=PASS
echo "E2E-RESULT: boot:udevd-no-errors $r"
cat /proc/asound/cards
