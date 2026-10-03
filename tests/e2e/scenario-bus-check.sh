#!/bin/bash
# Guest scenario, boot 2 of 2 (see scenario-bus-map.sh): with the bus numbers
# swapped, each device must still carry the name of ITS controller.
name_for() {
    local path ctrl drv
    path=$(readlink -f "$1/device")
    ctrl=$(grep -oE '0000:00:[0-9a-f]{2}\.[0-9]' <<<"$path" | tail -n1)
    drv=$(basename "$(readlink -f "/sys/bus/pci/devices/$ctrl/driver")")
    drv=${drv%%_*}
    printf 'mic-%s' "${drv%-pci}"
}
for c in /sys/class/sound/card*; do
    [[ "$(readlink -f "$c/device")" == */usb* ]] || continue
    want=$(name_for "$c")
    got=$(cat "$c/id")
    port=$(basename "$(dirname "$(readlink -f "$c/device")")")
    link=$(readlink -f "/dev/sound/by-id/$want")
    [[ "$got" == "$want" ]] && r=PASS || r=FAIL
    echo "E2E-RESULT: bus-swap:id[$want] $r got=$got port=$port"
    [[ "$link" == "/dev/snd/controlC${c##*card}" ]] && r=PASS || r=FAIL
    echo "E2E-RESULT: bus-swap:link[$want] $r ${link:-missing}"
done
