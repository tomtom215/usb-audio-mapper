#!/bin/bash
# Guest scenario, boot 1 of 2: identical devices on two different USB host
# controllers (xHCI and OHCI). Map each by card number, naming it after its
# controller driver; the rules are carried into boot 2 (scenario-bus-check.sh),
# which loads the controller drivers in the opposite order so USB bus numbers
# swap.
name_for() { # card dir -> mic-<driver>
    local path ctrl drv
    path=$(readlink -f "$1/device")
    ctrl=$(grep -oE '0000:00:[0-9a-f]{2}\.[0-9]' <<<"$path" | tail -n1)
    drv=$(basename "$(readlink -f "/sys/bus/pci/devices/$ctrl/driver")")
    drv=${drv%%_*}
    printf 'mic-%s' "${drv%-pci}"
}
echo "E2E-INFO: udev=$(udevadm --version) kernel=$(uname -r)"
for c in /sys/class/sound/card*; do
    [[ "$(readlink -f "$c/device")" == */usb* ]] || continue
    n=${c##*card}
    name=$(name_for "$c")
    echo "E2E-INFO: card$n port=$(basename "$(dirname "$(readlink -f "$c/device")")") -> $name"
    if bash /opt/usb-audio-mapper.sh -n --card "$n" -f "$name" </dev/null >/dev/null 2>&1; then
        echo "E2E-RESULT: bus-map:$name PASS"
    else
        echo "E2E-RESULT: bus-map:$name FAIL"
    fi
done
echo "E2E-RULES-BEGIN"
cat /etc/udev/rules.d/99-usb-soundcards.rules
echo "E2E-RULES-END"
