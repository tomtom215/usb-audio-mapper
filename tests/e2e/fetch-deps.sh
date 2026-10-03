#!/usr/bin/env bash
# Download and extract the pinned guest kernel and udev builds used by the
# end-to-end suite, so CI does not depend on what the host has installed.
#
# Usage: tests/e2e/fetch-deps.sh DEST_DIR
# Produces: DEST_DIR/kernel (Debian 12 kernel 6.1, with modules)
#           DEST_DIR/udev-241 (Debian 10), udev-247 (Debian 11 / Raspberry Pi
#           OS bullseye), udev-262 (Debian unstable)
#
# Files come from snapshot.debian.org, whose /file/<sha1> URLs are permanent
# and content-addressed; each file is additionally checked against SHA-256.
set -euo pipefail

dest=${1:?usage: $0 DEST_DIR}
mkdir -p "$dest/dl"

# sha256  snapshot-sha1  filename  extract-into
pins=(
    "439422e41d2dbb840b60b81e3bf5e5955bfa56b7a8c268aec83c9ff882d421e6 deeacc5af624650aab763ec7cb65f51639704842 linux-image-6.1.0-50-amd64-unsigned_6.1.176-1_amd64.deb kernel"
    "e87407b6d02c90c69294ed0ba656c27f6147167839ccac4c3bb245b83872e40a 4a2c370544a35bdaa2b949e4e66185e79017bd8f udev_241-7~deb10u10_amd64.deb udev-241"
    "dda6dea77c18d1fb05e38544157c862331ca161e045e460eefa77353059efc18 637cfa07537c86ab8407035de8e612f2028c8fbe systemd_241-7~deb10u10_amd64.deb udev-241"
    "c7dbdf513571f76769e88db073b664f6aa5bf231797290e4b05303320c6b2882 e270b17d4e341f6fe87a7a76afbd4344285f5af1 udev_247.3-7+deb11u5_amd64.deb udev-247"
    "fc04e069a39bcdab529a75f48a6575fe7172cf02dcd5b697866312b7ba728a6c 1d0b4efb764b42d73fe02230049701c22f761aad systemd_247.3-7+deb11u5_amd64.deb udev-247"
    "0878367b18c0e77e961d632d5d1cc614058f162b2391fbe5a3b0eb33cfc96bed f7c1789b6921b0e8ae6dab51899a67ba580d4ce3 udev_262-1_amd64.deb udev-262"
    "6de3a3df3fb9d264b48c6306b55fb4d83f6114a25ad6299b3bd83e5bc28436d2 514660c298ed3869fc8df5581dbaf63aa6dcb0c2 systemd_262-1_amd64.deb udev-262"
    "66978b0102d1da834afa5ec670f8f6a1ded893be9fbe08fa2a5c95c152f90b51 b0b5770eef5ff5ef15a042e73be35a4df813055f libsystemd-shared_262-1_amd64.deb udev-262"
)

for pin in "${pins[@]}"; do
    read -r sha256 sha1 name into <<<"$pin"
    file="$dest/dl/$name"
    if [[ ! -f "$file" ]] || ! printf '%s  %s\n' "$sha256" "$file" | sha256sum -c --status; then
        curl -sSfL --retry 4 --retry-delay 2 -o "$file.part" "https://snapshot.debian.org/file/$sha1"
        mv "$file.part" "$file"
    fi
    printf '%s  %s\n' "$sha256" "$file" | sha256sum -c --quiet
    if [[ ! -e "$dest/$into/.done-$name" ]]; then
        mkdir -p "$dest/$into"
        dpkg-deb -x "$file" "$dest/$into"
        touch "$dest/$into/.done-$name"
    fi
done
# Distribution kernel packages leave modules.dep to the postinst script.
for kdir in "$dest"/kernel/lib/modules/*; do
    [[ -f "$kdir/modules.dep" ]] || depmod -b "$dest/kernel" "$(basename "$kdir")"
done
echo "E2E dependencies ready in $dest"
