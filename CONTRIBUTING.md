# Contributing to USB Audio Mapper

Thank you for helping. This project is licensed under the Apache License 2.0;
by contributing you agree your contribution is licensed the same way. Please be
respectful and constructive.

## Reporting bugs

Open an issue at https://github.com/tomtom215/usb-audio-mapper/issues with:

- what you ran and what you expected;
- the output of `./usb-audio-mapper.sh --list -D` and of the failing command;
- `cat /proc/asound/cards`, `cat /etc/udev/rules.d/99-usb-soundcards.rules`;
- `udevadm --version`, `bash --version | head -n1`, `uname -r`, distribution.

Device compatibility reports (worked / did not work, with the same details and
the device's make and model) are very welcome, especially from physical
hardware and ARM boards, which CI cannot cover.

## Development setup

Develop and test on Linux (a VM or container is fine). The test helpers use
GNU coreutils and bash ≥ 4.2; on macOS the system bash 3.2 and BSD tools will
not run the suite, and the script itself only runs on Linux. You need bash,
bats, shellcheck and shfmt. For the end-to-end tests also qemu-system-x86,
cpio, kmod, usbutils, alsa-utils and a udev install on the host.

```bash
# Debian/Ubuntu
sudo apt-get install bats shellcheck shfmt
sudo apt-get install qemu-system-x86 cpio kmod usbutils alsa-utils   # for make e2e
```

| Command | What it does | Root? |
|---|---|---|
| `make check` | lint (bash -n, shellcheck, shfmt) + bats suite | no |
| `make fmt` | format with shfmt (`-i 4 -bn -ci`) | no |
| `make test AWK=mawk` | bats suite with a specific awk | no |
| `make test-awk` | bats suite under gawk, mawk, BWK awk, BusyBox awk | no |
| `make bash-matrix` | bats suite under bash 4.2 … 5.3, plus a check that bash 3.2 (macOS) is refused cleanly; all built from pinned tarballs | no |
| `make mutation` | re-introduces known defects; each must fail the suite | no |
| `make e2e` | QEMU with the host kernel and udev | only to read `/boot/vmlinuz-*` where it is root-only (e.g. Ubuntu) |
| `make e2e-matrix` | QEMU with a pinned Debian kernel and udev 241/247/262 + host, including the USB bus-renumbering reboot | no |

The bats suite runs the real script against a fake sysfs tree
(`tests/test_helper.bash`) with stub `udevadm` and `logger` on `PATH`
(`tests/helpers/bin/`), so it never touches your system. The end-to-end suite
(`tests/e2e/`) boots a throwaway VM; see the header of `tests/e2e/qemu-e2e.sh`.

## Rules for changes

- **Behavior changes need a test that fails without them.** Run the suite on
  the unfixed code first and see it fail.
- **Anything that changes the generated rules needs `make e2e`.** Text that
  looks right can still be ignored or misread by udev; only the kernel and
  udevd can confirm a rule works.
- Keep `make check` clean: shellcheck at its default severity, shfmt with
  `-i 4 -bn -ci`. Re-run the tests after `make fmt` — shfmt rewrites
  unquoted associative-array keys such as `[1-1]` as arithmetic, so quote them.
- In bats tests, end negated assertions with `|| false`
  (`! grep -q x file || false`): bash does not fail on a negated command in the
  middle of a test. Call script functions through `fn` (a child shell), never
  by sourcing the script into the test shell, which would switch off bats'
  error handling.
- No process substitution (`<(...)`) in the script: it needs `/dev/fd`, which
  minimal systems lack. A test enforces this.
- Bash 4.0 compatibility: guard expansions of possibly empty arrays
  (`${arr[@]+"${arr[@]}"}`) and check `make bash-matrix` for anything
  version-sensitive.
- Update README.md, DOCUMENTATION.md and CHANGELOG.md in the same change.

## Commit messages

Imperative mood, first line at most 72 characters ("Fix port parsing for
hub ports"), body explaining why. Reference issues where relevant.

## Pull requests

CI (`.github/workflows/ci.yml`) runs lint, the bats suite under four awks,
the bash version matrix, the mutation check and the end-to-end matrix. All
must pass. When you fix a defect, consider adding it to `tests/mutation.sh`.
