# USB Audio Mapper — technical documentation

How the mapper names USB sound cards, why each part of the generated rule is
there, and how the behavior was verified. For everyday use see
[README.md](README.md).

Each statement below is marked with how it is known:

- **[kernel]** / **[systemd]** — read in the cited source file.
- **[e2e]** — observed in `tests/e2e/` (real Linux kernel and real
  systemd-udevd in QEMU with emulated USB audio devices).
- **[unit]** — covered by `tests/usb-audio-mapper.bats`.

## 1. The names involved

**ALSA card id.** Every sound card has an id string, shown in brackets in
`/proc/asound/cards` and readable at `/sys/class/sound/cardN/id`. Programs can
open a card by id (`hw:CARD=mic-left`) instead of by number, which is what
makes a name stable. The id is writable through sysfs, and that is what the
`ATTR{id}="..."` rule action does.

Kernel limits on the id **[kernel]** (`sound/core/init.c`, `id_store`;
`sound/core/info.c`, `snd_info_check_reserved_words`; `include/sound/core.h`):

- `card->id` is `char[16]`. A write longer than 15 characters is cut to 15
  characters and still reports success. **[e2e]** writing `abcdefghijklmnopq`
  left the id `abcdefghijklmno`.
- Allowed characters are letters, digits, `_` and `-`.
- The write fails with `EEXIST` if any card already has that id, *including the
  card being written* (the uniqueness check is called with no card to skip), if
  the id starts with `card`, or if it is one of `version meminfo memdebug detect
  devices oss cards timers synth pcm seq`. **[e2e]** `card-test` and `pcm` were
  refused with "File exists".

The mapper's name rule (lowercase letter first, `[a-z0-9-]`, at most 15
characters, no `card` prefix, no reserved word) keeps every accepted name
inside these limits. **[unit]**

**USB port.** The kernel names a USB device `<bus>-<port>`, adding
`.<port>` for each hub on the way, e.g. `1-2` or `1-3.1`; root hubs are
`usb<bus>` **[kernel]** (`drivers/usb/core/usb.c`, `usb_alloc_dev`). The sound
card hangs below the device's audio interface:

```
/sys/devices/pci0000:00/0000:00:03.0/usb1/1-3/1-3.1/1-3.1:1.0/sound/card2
                                          hub  device  interface   card
```

## 2. The generated rules

```
# usb-audio-mapper: name=NAME usb=VID:PID port=PORT path=ID_PATH desc=TEXT
SUBSYSTEM=="sound", KERNEL=="card*", ACTION=="add|change", ATTRS{idVendor}=="VID", ATTRS{idProduct}=="PID", IMPORT{builtin}="path_id", ENV{ID_PATH}=="ID_PATH", ATTR{id}!="NAME", ATTR{id}="NAME", ENV{USB_AUDIO_MAPPER}="NAME"
SUBSYSTEM=="sound", KERNEL=="controlC*", ACTION=="add|change", ATTRS{idVendor}=="VID", ATTRS{idProduct}=="PID", IMPORT{builtin}="path_id", ENV{ID_PATH}=="ID_PATH", SYMLINK+="sound/by-id/NAME", ENV{USB_AUDIO_MAPPER}="NAME"
```

The location part (`IMPORT{builtin}="path_id", ENV{ID_PATH}=="..."`) is
replaced by `KERNELS=="PORT"` when the device was not connected at mapping
time (`path=-` in the comment), and left out for `--any-port` rules.

| Part | Why |
|---|---|
| Comment line | Machine-readable record used by `--list`, `--remove` and de-duplication. It is a separate physical line: a comment and a rule on one line make the whole line a comment (the defect in v3.0.0). |
| `SUBSYSTEM=="sound"` | Only sound devices. |
| `KERNEL=="card*"` | `ATTR{id}` exists only on the card device. Without the gate the rule also ran on `controlC*`/`pcm*`, where udev logged failed writes. **[e2e]** |
| `KERNEL=="controlC*"` | The symlink needs a device node; the card device has none. Without the gate several nodes competed for the link. **[e2e]** Pointing at `controlC<N>` matches what LyreBirdAudio resolves. |
| `ACTION=="add\|change"` | Applies at plug-in and boot (`add`) and when the mapper triggers `change` to apply a new name immediately; never on `remove` (where the write fails because the card is going away). **[e2e]** |
| `ATTRS{idVendor}`, `ATTRS{idProduct}` | Only a device with this id gets the name, even if another device is plugged into that position. |
| `IMPORT{builtin}="path_id"`, `ENV{ID_PATH}` | The card's own position, independent of USB bus numbers (§2.1). The import makes it available on `add` events, before `78-sound-card.rules` would set it on `change`. |
| `KERNELS=="PORT"` (fallback) | `<bus>-<port>` name of the USB device. udev evaluates `ATTRS{}` and `KERNELS` on the same ancestor, so a rule for `1-3` does not capture a device behind a hub on `1-3`. **[e2e]** Depends on the bus number (§2.1). |
| `ATTR{id}!="NAME"` | The kernel refuses to re-assign a card its current id (`EEXIST`, see §1). **[e2e]** With the guard the rule is a no-op once the name is set, so later `change` events (udevd restarts, `udevadm trigger`) log nothing. |
| `ENV{USB_AUDIO_MAPPER}` | Marks the line as written by the mapper; also visible in `udevadm info`, and usable by your own rules (§8). |

### 2.1 Why the card's `ID_PATH`

udev's `path_id` describes where a device sits: the controller (for example
`pci-0000:00:14.0`), then `usb-0:` and the port chain, then the interface. It
deliberately drops the USB bus number **[systemd]**
(`src/udev/udev-builtin-path_id.c`, `handle_usb`: "USB host number may change
across reboots").

That matters. USB bus numbers are handed out as host-controller drivers
register, so on a machine with two controllers whose drivers load in a
different order, the numbers swap. **[e2e]** xHCI and OHCI controllers with
one identical microphone each, mapped with `KERNELS` rules, then rebooted with
the OHCI driver loaded first: the OHCI microphone received the xHCI
microphone's name, and the xHCI microphone got none. The same reboot with
`ID_PATH` rules named both correctly, in either load order, at coldplug and at
hotplug.

The value must be the sound **card's** `ID_PATH`, read with
`udevadm test-builtin path_id /sys/class/sound/cardN`. Versions up to 3.0.0
and LyreBirdAudio up to 1.2.1 used the USB device node's `ID_PATH`, which
stops at the device and lacks the interface **[e2e]**:

```
USB device /dev/bus/usb/001/002  ID_PATH=pci-0000:00:03.0-usb-0:1
sound card card0                 ID_PATH=pci-0000:00:03.0-usb-0:1:1.0
```

Those never match; in addition the old non-interactive code took the value
from the first `lsusb` line with the vendor/product id, so all identical
devices got the same rule. **[e2e]** With the old rules no card was renamed.

What `ID_PATH` does not survive: the controller itself moving (another PCIe
slot or a replaced controller changes its address). Map the devices again in
that case.

## 3. Choosing the port

| Input | Port used |
|---|---|
| `--card N` | Port of the USB device that card N belongs to (sysfs). |
| `-u PORT` | `PORT`, normalized: `1-2` as is, `usb-1-2` → `1-2`, `usb-0000:00:14.0-2` or `usb-xhci-hcd.0.auto-1.2` (from `/proc/asound/cards`; the controller is a PCI address or a platform device name) → `<bus>-2` / `<bus>-1.2` by finding the root hub on that controller. Anything else is rejected with exit 2; there is no silent fallback. |
| `-v/-p` only | The port of the single connected device with that id; exit 5 if there are several; a VID:PID-only rule (with a warning) if there are none. |
| `--any-port` | No port: VID:PID only. |

Then, if the device with that id is connected at that port, its card's
`ID_PATH` is read with `udevadm test-builtin path_id` and used in the rule; a
device with a different id on that port is never used for this. Otherwise the
rule uses `KERNELS=="PORT"` and the mapper warns that it depends on the bus
number.

Port strings are checked against `^[0-9]+-[0-9]+(\.[0-9]+)*$` and `ID_PATH`
values against `^[A-Za-z0-9][A-Za-z0-9:._+-]*$` before they reach a rule, so no
quote, newline or udev key can be injected. **[unit]**

## 4. Writing the rules file

1. Build the new block and check every line against a strict pattern
   (`assert_rules_safe`); anything unexpected aborts before writing.
2. Take an exclusive lock (`flock` on `.usb-audio-mapper.lock` next to the
   rules file) so concurrent runs cannot lose each other's changes. **[unit]**:
   8 parallel runs, 8 mappings.
3. Read the current file and drop: blocks with the same name, blocks for the
   same vendor/product at the same location (`ID_PATH`, else port; the old
   name is reported), and older-format lines
   containing `ATTR{id}="NAME"` together with a `# USB Sound Card:` comment
   directly above them. Other lines are kept. Blank-line runs are collapsed.
4. If the identical block is already present and nothing else would change,
   stop: the file is left byte-for-byte unchanged. **[unit]**, **[e2e]**
5. Write a temporary file in the same directory (name starts with `.` and lacks
   the `.rules` suffix, so udev never reads it), set mode 0644, run
   `udevadm verify` on it where the command exists (added in systemd 254), flush it to
   disk, rename it over the rules file, and flush the directory. A failure at
   any step leaves the old file untouched. **[unit]**
6. Log the change through `logger -t usb-audio-mapper` when available.

## 5. Applying and verifying

After writing, the mapper runs `udevadm control --reload-rules` and
`udevadm trigger --action=change` on the target card and its control device,
waits for `udevadm settle`, then reads the card id back from sysfs:

- id equals the name → success (exit 0), and the symlink is reported;
- another card holds the name → exit 6, naming that card; the rule stays and
  applies once the name is free;
- otherwise → exit 6 with a `udevadm test` command to investigate.

When the device is not connected, the rule is only reloaded; it applies when
the device appears. `--no-apply` skips this step entirely.

## 6. Verification performed

| Check | Scope |
|---|---|
| bats suite (56 tests) | Rule text, validation, port parsing, sysfs discovery, all CLI paths, migration, locking, atomicity, interactive mode. Runs the real script against a fake sysfs; udevadm and logger are stubbed. |
| Mutation check (`make mutation`) | 14 re-introduced defects, each of which must make the suite fail: the comment-line defect, no `!=` guard, a loose port pattern, 32-character names, `card*` names, no migration, no lock, no line assertions, unsanitized descriptions, ignored verification failures, silent port fallback, ignored ambiguity, never using `ID_PATH`, and taking `ID_PATH` from a different device on the port. |
| Portability | Unit suite under bash 4.2.53, 4.3.30, 4.4.18, 5.0, 5.1.16, 5.2.37, 5.3; bash 3.2.57 (macOS) refused with exit 4, also when sourced; non-Linux systems refused; under gawk, mawk, BWK awk and BusyBox awk; and with the whole userland replaced by BusyBox. |
| End to end: setup | QEMU guests with Linux 6.1 (Debian 12) and 6.8 (Ubuntu 24.04), real `snd-usb-audio`, real systemd-udevd 241, 245, 247, 255 and 262; three identical devices on two root ports and behind a hub. Checks: immediate rename without reboot, the symlink target, migration of older rules, preservation of unrelated rules, refusal of ambiguous ids, conflict reporting, removal, the interactive wizard, and absence of udev errors about the rules. |
| End to end: running system | Names and links unchanged after: a udevd restart; `udevadm trigger --action=change` and `--action=add` for all devices; unplug/replug in reverse order and in swapped order (card numbers observed to change); ten unplug/replug cycles without waiting for udev; unplugging the hub in front of a device. One card was playing audio throughout and kept playing. Unplug/replug is done by de-authorizing the USB device, which removes and re-creates it in the kernel. |
| End to end: reboot | Rules present before the devices appear: drivers loaded before udevd starts with udev replaying `add` events (as at boot), the same with the first device absent (the others get lower card numbers), and drivers loaded after udevd. |
| End to end: bus renumbering | Two controllers (xHCI, OHCI), one identical device on each; mapped with the xHCI driver loaded first, rebooted with OHCI first (bus numbers swap). Both names stay with their devices. Needs a kernel with modular host-controller drivers (`make e2e-matrix` uses one). |

Not covered: physical USB hardware and cable pulls, non-x86 architectures,
suspend/resume, eudev, and systemd releases older than 241.

## 7. Debugging

```bash
./usb-audio-mapper.sh --list -D
udevadm info -q property -p /class/sound/card1          # ID_* and USB_AUDIO_MAPPER
udevadm test "$(udevadm info -q path -p /class/sound/card1)" 2>&1 | grep 99-usb-soundcards
udevadm info -a -p /class/sound/card1 | grep -E 'KERNELS|idVendor|idProduct'
udevadm monitor --udev --property --subsystem-match=sound   # watch events live
```

## 8. Adding your own rules

Put your own rules in a separate file that sorts after the mapper's, for
example `/etc/udev/rules.d/99-zz-local.rules`, and match on the marker the
mapper sets:

```
SUBSYSTEM=="sound", KERNEL=="controlC*", ENV{USB_AUDIO_MAPPER}=="mic-left", GROUP="audio", MODE="0660"
```

udev reads rules files in lexical order, so the marker is already set when
this line runs. **[e2e]** with `GROUP="lyre", MODE="0640"` the control node of
`mic-left` got exactly that, and the card's other nodes kept the defaults.

Do not rely on placing such lines inside `99-usb-soundcards.rules`: the mapper
appends each new or changed block at the end of that file, so a line that
follows a block today may precede it after the next change. Lines you add to
that file are otherwise preserved.
