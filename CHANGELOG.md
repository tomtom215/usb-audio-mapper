# Changelog

## 4.0.0 — 2026-10-03

Rules written by 3.0.0 renamed no device. 4.0.0 fixes that, along with
the defects listed below, and adds the tests that would have caught them.
Re-run the mapper once per device after upgrading; old rules for the same name
are replaced automatically.

### Fixed

- **Rules were ignored by udev (critical).** The comment and the rule were
  written to one line starting with `#`, so udev treated the whole rule as a
  comment. The comment is now its own line. (Ported from LyreBirdAudio.)
- **Rules could never match (critical).** When udev knew the device's
  `ID_PATH`, the rule matched `ENV{ID_PATH}` taken from the USB device node,
  which never equals the sound card's own `ID_PATH` (the card's carries an
  interface suffix such as `:1.0`). In non-interactive mode that value also
  came from the first `lsusb` line with the vendor/product id, so all
  identical devices got the same rule and `-u` was ignored. Shown with a real
  kernel and systemd-udevd: with 3.0.0 and with LyreBirdAudio's fixed copy, no
  card was renamed. Rules now match the sound card's own `ID_PATH`, imported in
  the rule so it is available on `add` events.
- **Wrong device named after USB bus renumbering (critical).** Port rules of
  the form `KERNELS=="1-1"` contain the USB bus number, which changes between
  boots when host-controller drivers register in a different order. In a test
  with two controllers, one microphone received the other's name. `ID_PATH`
  omits the bus number; with it both devices kept their names in every load
  order. `KERNELS` is used only when the device is not connected at mapping
  time, with a warning.
- **Root code execution through the rules file (security).** A newline in the
  `-d` description, or in an `-u` port value, could add an arbitrary
  `RUN+="..."` line to a root udev rule. Descriptions are reduced to
  `[A-Za-z0-9 ._()-]`, ports must match `<bus>-<port>[.<port>...]`, and every
  generated line is checked against a strict pattern before writing.
  (Port and sanitizer fixes ported from LyreBirdAudio.)
- **Names the kernel truncates or refuses.** Names up to 32 characters were
  accepted, but ALSA ids hold 15 (longer ones are cut short). The suggested
  `card-...` prefix and words such as `pcm` are refused by the kernel. Names
  are now checked against the kernel's rules.
- **Invalid ports were silently dropped.** An unusable `-u` value fell back to
  a vendor/product rule that renames every identical device. It is now an
  error. The synthetic `bus<N>-dev<M>` port, which could never match, is no
  longer produced.
- **Non-atomic writes.** The rules file was built in `/tmp` and moved across
  filesystems, so a power cut could leave it truncated. It is now written next
  to the target, flushed, and renamed. (Ported from LyreBirdAudio.)
- **Lost updates.** Concurrent runs could overwrite each other; runs are now
  serialized with `flock`.
- **Symlink on every node.** `SYMLINK+=` matched all sound nodes of a card;
  it now targets the control device only, and `ATTR{id}` targets only the
  card device.
- **Kernel errors on re-applied rules.** The kernel rejects writing a card's
  current id again (`EEXIST`), so an unguarded rename rule fails on every
  `change` event; rules now carry an `ATTR{id}!=` guard.
- `mkdir` failures are reported (ported from LyreBirdAudio).

### Added

- `--card N`: map a connected card directly; vendor, product and port are
  read from sysfs.
- Immediate application and verification: after writing, the rule is applied
  and the kernel's card id is read back. Exit 6 reports a failure and, when
  another card holds the name, which one. No reboot is needed.
- `--list`, `--remove NAME`, `--dry-run`, `--no-apply`, `--any-port`,
  `--rules-file`, `--version`.
- `-u` accepts the form printed in `/proc/asound/cards`, for PCI controllers
  (`usb-0000:00:14.0-2`) and platform controllers whose name contains `-`
  (`usb-xhci-hcd.0.auto-1.2`, as on dwc3 ARM boards).
- Migration of rules written by 1.0.0, 2.0.0, 3.0.0 and LyreBirdAudio for the
  same name; `--list` reports any remaining older rules.
- Refusal (exit 5) when several identical devices are connected and no port
  is given.
- Documented exit codes; `NO_COLOR` support; syslog audit entries via `logger`.
- Test suite: bats tests against a fake sysfs, run under bash 4.2–5.3 and
  four awk implementations; a mutation check; QEMU end-to-end tests with real
  kernels (6.1, 6.8) and real systemd-udevd (241, 245, 247, 255, 262) covering
  setup, hot-plug and re-enumeration, udevd restarts and system-wide triggers,
  reboots (coldplug), and USB bus renumbering; CI for all of it.

### Changed

- Device information comes from sysfs; `lsusb` is no longer required.
- The interactive wizard reads the USB device from the chosen card instead of
  asking you to pick it from an `lsusb` list, retries invalid input, shows the
  rules before writing and asks for confirmation. It no longer offers to
  reboot.
- `-d` is optional (defaults to the device's manufacturer and product).
- `-t/--test` lists every USB device with its port and whether it is audio;
  it no longer needs root.
- Diagnostics go to stderr; stdout carries only rules and listings.
- The rule format (see README.md). Rules are written as one block per name.

### Removed

- The reboot prompt, rules keyed on the USB device node's `ID_PATH`, and unused code
  (`get_portable_hash`, `SCRIPT_DIR`).

## 3.0.0 — 2025-10-25

Refactor taken from LyreBirdAudio 1.2.1: clean port paths, device lookup by
bus/device number, rule de-duplication, `safe_base10()`. Its rules were
ignored by udev (see 4.0.0).

## 2.0.0 — 2025-05-23

Error checking, atomic writes, dependency checks. Port rules carried a serial
suffix and could not match.

## 1.0.0 — 2025-04-01

Initial release: interactive and non-interactive mapping.
