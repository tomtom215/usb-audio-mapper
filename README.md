# USB Audio Mapper

Give every USB microphone or sound card a permanent name on Linux, even when
you have several identical devices.

Linux numbers sound cards in the order it finds them (card 0, card 1, ...), and
that order can change at every boot. USB Audio Mapper writes udev rules so the
card plugged into a given USB port always gets the name you chose:

- the ALSA card id, as shown in `/proc/asound/cards` and usable as
  `hw:CARD=<name>` or `plughw:CARD=<name>`;
- a symlink `/dev/sound/by-id/<name>` to the card's control device.

Part of the [LyreBirdAudio](https://github.com/tomtom215/LyreBirdAudio) project.

**Version:** 4.0.0 · **License:** Apache 2.0 · [Changelog](CHANGELOG.md)

> **Upgrading from 3.0.0 or LyreBirdAudio ≤ 1.2.x?** In tests with a real
> kernel and udev, rules written by those versions renamed no device (see
> [Migration](#migration)). Re-run the mapper for each device; it replaces the
> old rules automatically.

## Quick start

```bash
curl -fsSLO https://raw.githubusercontent.com/tomtom215/usb-audio-mapper/main/usb-audio-mapper.sh
chmod +x usb-audio-mapper.sh

./usb-audio-mapper.sh --list          # see your USB sound cards and their ports
sudo ./usb-audio-mapper.sh            # guided setup
```

`--list` prints something like:

```
CARD  ID               USB-ID     PORT       MAPPED-AS        DESCRIPTION
1     Audio            2e88:4610  1-1        -                MOVO X1 MINI
2     Audio_1          2e88:4610  1-2        -                MOVO X1 MINI
```

Name both microphones without prompts:

```bash
sudo ./usb-audio-mapper.sh -n --card 1 -f mic-left
sudo ./usb-audio-mapper.sh -n --card 2 -f mic-right
```

Each run applies the name immediately and checks it took effect:

```
OK: Rules written to /etc/udev/rules.d/99-usb-soundcards.rules
OK: Verified: card 1 is now 'mic-left' (hw:CARD=mic-left).
OK: Verified: /dev/sound/by-id/mic-left -> ../../snd/controlC1
```

No reboot is needed. Record with `arecord -D plughw:CARD=mic-left -d 5 test.wav`.

## Requirements

- Linux with udev (systemd-udevd). Tested with udev 241, 245, 247, 255 and 262.
  On other systems (macOS included) the script stops with exit status 4 and a
  message saying so.
- Bash 4.0 or newer. Tested with bash 4.2, 4.3, 4.4, 5.0, 5.1, 5.2 and 5.3.
  Bash 3.2 (the version macOS ships) is refused with exit status 4.
- awk, grep, sed, sort, tr, mktemp, readlink, dirname, basename, head. GNU
  coreutils, mawk, gawk, BWK awk and BusyBox all work.
- Optional: `flock` (util-linux) serializes concurrent runs; `logger` records
  changes in the system log.
- Root, to write `/etc/udev/rules.d/`. Listing and `--dry-run` work without root.

`lsusb` is no longer required: devices are read straight from sysfs.

## Choosing a name

Names become ALSA card ids, so the kernel's limits apply. A name must:

- start with a lowercase letter and use only `a-z`, `0-9` and `-`;
- be at most **15 characters** (the kernel silently cuts longer ids short);
- not start with `card`, and not be one of `version`, `meminfo`, `memdebug`,
  `detect`, `devices`, `oss`, `cards`, `timers`, `synth`, `pcm`, `seq`
  (the kernel refuses these).

The mapper rejects names that break these rules before writing anything.

## Usage

### Interactive

```bash
sudo ./usb-audio-mapper.sh
```

The wizard lists your USB sound cards, asks which one to name, suggests a
name, shows the exact rules it will write and asks for confirmation. If
identical devices are connected it always ties the name to the port.

### Non-interactive

By ALSA card number (the simplest; vendor, product and port are read from the
card):

```bash
sudo ./usb-audio-mapper.sh -n --card 1 -f mic-left
```

By vendor and product id:

```bash
sudo ./usb-audio-mapper.sh -n -v 2e88 -p 4610 -f movo            # one such device
sudo ./usb-audio-mapper.sh -n -v 2e88 -p 4610 -u 1-2 -f movo-b   # pick the port
```

Without `-u`, the mapper looks for connected devices with that id:

| Connected devices with that id | What happens |
|---|---|
| exactly one | the name is tied to the port it is on now |
| several | refused (exit 5): choose one with `-u PORT` or `--card N` |
| none | a rule matching that id on any port is written, with a warning |

`--any-port` writes a rule that follows the device to any port. Use it only
when you have a single device with that vendor and product id: ALSA ids are
unique, so with two such devices only the first one detected gets the name.

### Finding the port

`--list` (sound cards) and `-t` (every USB device) show ports in the kernel's
form: `<bus>-<port>`, with `.<port>` added for each hub, e.g. `1-2` or
`1-3.1`. `-u` also accepts the form printed in `/proc/asound/cards`, such as
`usb-0000:00:14.0-2`, while the device is connected.

### Other commands

```bash
./usb-audio-mapper.sh --list                     # cards, ports, mappings
./usb-audio-mapper.sh -t                         # all USB devices and ports
sudo ./usb-audio-mapper.sh --remove mic-left     # delete one mapping
./usb-audio-mapper.sh -n --card 1 -f mic --dry-run   # print rules only
```

### All options

| Option | Meaning |
|---|---|
| `-i`, `--interactive` | Interactive wizard (default without options) |
| `-n`, `--non-interactive` | Map without prompts |
| `-c`, `--card N` | ALSA card number of a connected USB device |
| `-v`, `--vendor VID` | USB vendor id, 4 hex digits |
| `-p`, `--product PID` | USB product id, 4 hex digits |
| `-u`, `--usb-port PORT` | Physical port, e.g. `1-2` or `1-2.3` |
| `--any-port` | Match the device on any port |
| `-f`, `--friendly NAME` | Name to assign (see [Choosing a name](#choosing-a-name)) |
| `-d`, `--device TEXT` | Description stored in the rule comment (optional) |
| `-l`, `--list` | List USB sound cards, ports and mappings |
| `-t`, `--test` | List every USB device with its port |
| `-r`, `--remove NAME` | Remove a mapping |
| `--dry-run` | Print the rules; change nothing |
| `--no-apply` | Write rules but do not trigger udev now |
| `--rules-file PATH` | Rules file (default `/etc/udev/rules.d/99-usb-soundcards.rules`) |
| `-D`, `--debug` | Debug output |
| `-V`, `--version` | Print the version |
| `-h`, `--help` | Help |

### Exit status

| Code | Meaning |
|---|---|
| 0 | Success (and verified, when the device is connected) |
| 1 | Other error |
| 2 | Usage error: bad option, name, id or port |
| 3 | No permission to write the rules file (use sudo) |
| 4 | A required command is missing |
| 5 | Device not found, not USB, or ambiguous |
| 6 | Rules written, but the card did not take the name (the message says why) |

If exit 6 is caused by another connected card holding the name, the message
names that card. The rule is kept and applies once that card releases the name.

## What gets written

One block per mapping in `/etc/udev/rules.d/99-usb-soundcards.rules` (each
rule is a single line in the file; wrapped here):

```
# usb-audio-mapper: name=mic-left usb=2e88:4610 port=1-1 path=pci-0000:00:14.0-usb-0:1:1.0 desc=MOVO X1 MINI
SUBSYSTEM=="sound", KERNEL=="card*", ACTION=="add|change",
  ATTRS{idVendor}=="2e88", ATTRS{idProduct}=="4610",
  IMPORT{builtin}="path_id", ENV{ID_PATH}=="pci-0000:00:14.0-usb-0:1:1.0",
  ATTR{id}!="mic-left", ATTR{id}="mic-left", ENV{USB_AUDIO_MAPPER}="mic-left"
SUBSYSTEM=="sound", KERNEL=="controlC*", ACTION=="add|change",
  ATTRS{idVendor}=="2e88", ATTRS{idProduct}=="4610",
  IMPORT{builtin}="path_id", ENV{ID_PATH}=="pci-0000:00:14.0-usb-0:1:1.0",
  SYMLINK+="sound/by-id/mic-left", ENV{USB_AUDIO_MAPPER}="mic-left"
```

`ID_PATH` is udev's name for the physical position: the USB controller
(`pci-0000:00:14.0`) plus the port chain (`usb-0:1`) and interface (`:1.0`),
**without the USB bus number**. Bus numbers can change between boots on
machines with several USB controllers; in testing, a rule keyed on the bus
port (`KERNELS=="1-1"`) then gave the name to a *different* microphone. If
the device is not connected when you map it (`-u` for a future device), the
position cannot be read, and the rule falls back to `KERNELS=="<port>"` with a
warning; map it again once it is plugged in.

The file is replaced atomically (temporary file in the same directory, flushed
to disk, then renamed), checked with `udevadm verify` where available, and
written with mode 0644. Lines the mapper did not write are kept unchanged,
except that runs of blank lines are collapsed to one and older rules for the
same name are replaced (see [Migration](#migration)). [DOCUMENTATION.md](DOCUMENTATION.md) explains every part of the rule
and why it is shaped this way.

## Migration

Re-run the mapper once per device with the same name. It removes any older
rule carrying that name, including the forms written by:

- **v3.0.0 and LyreBirdAudio ≤ 1.2.1** — these wrote the comment and the rule
  on one line starting with `#`, so udev ignored the whole rule; LyreBirdAudio's
  later fix still matched on `ENV{ID_PATH}` taken from the USB device, which
  never equals the sound card's `ID_PATH`. Tested with kernel 6.8 and udev
  255, neither renamed any card.
- **v2.0.0** — up to three rules per device. The port and `ID_PATH` rules
  could not match (the port carried a serial-number suffix, and `ID_PATH` came
  from the USB device rather than the sound card); the plain vendor/product
  rule gave every identical device the same name.
- **v1.0.0** — one rule per device, optionally with `KERNELS=="<port>*"`. The
  trailing `*` also matches other ports: `1-1*` matches `1-10` and anything
  behind a hub on `1-1`.

`--list` reports any remaining older rules. To start over, delete the file and
map each device again:

```bash
sudo rm /etc/udev/rules.d/99-usb-soundcards.rules
```

## Limitations

- **The name follows the port.** Move a port-tied device to another port and
  it loses the name until you map it again.
- **The controller's position matters.** Names are tied to the USB
  controller's address (e.g. its PCI address) plus the port chain. They
  survive changes of USB bus numbers, card numbers and enumeration order, but
  if the controller itself moves (a different PCIe slot, a replaced USB card),
  map the devices again.
- **Rules written for unplugged devices** (`-u` with nothing connected) match
  the bus port instead and are exposed to bus renumbering; the mapper warns.
- **One card per name.** ALSA requires unique card ids; a second card cannot
  take a name another connected card holds.
- **udev only.** Systems using mdev or no device manager are not supported.
- **Tested on emulated hardware.** The test suite runs real Linux kernels (6.1,
  6.8) and real udev (241–262) with QEMU's emulated USB audio devices, on
  x86-64: re-plugging (one at a time, in changed order, rapidly, and behind a
  hub), udevd restarts and system-wide `udevadm trigger`, reboots with drivers
  loaded before and after udevd, card numbers changing, and USB bus numbers
  changing (see [DOCUMENTATION.md §6](DOCUMENTATION.md#6-verification-performed)).
  It has not been tested on ARM boards, with physical microphones and cable
  pulls, or across suspend/resume; reports from such setups are welcome.

## Troubleshooting

| Symptom | What to do |
|---|---|
| Exit 6, "still holds the name" | Another card has that name. Unplug it, or map it to a different name. |
| Exit 5, "N connected devices are ..." | Several identical devices: use `--card N` or `-u PORT`. |
| Exit 2, "not a USB port" | Use the port printed by `--list`, e.g. `1-2`. |
| Name lost after moving the device | Expected for port-tied names; map it again on the new port. |
| `--list` shows "Legacy (pre-v4) rules" | Re-run the mapper for those names. |

For more detail run with `-D`, and see what udev does with:

```bash
udevadm test "$(udevadm info -q path -p /class/sound/card1)" 2>&1 | grep -i usb-soundcards
```

## Development

```bash
make check        # shellcheck, shfmt, bats unit tests (no root needed)
make test-awk     # unit tests under gawk, mawk, BWK awk and BusyBox awk
make bash-matrix  # unit tests under bash 4.2 ... 5.3 (built from source)
make mutation     # re-introduce known bugs; the tests must catch each one
make e2e          # QEMU: real kernel + real udev + emulated USB audio
make e2e-matrix   # the same against udev 241, 247, 262 and the host's
```

See [CONTRIBUTING.md](CONTRIBUTING.md). CI runs all of these on every push.

## Support

Issues: https://github.com/tomtom215/usb-audio-mapper/issues

Please include `./usb-audio-mapper.sh --list`, `cat /proc/asound/cards`, the
rules file, `udevadm --version` and your distribution.

## License

Apache License 2.0. Copyright 2025 Tom F and LyreBirdAudio contributors.
