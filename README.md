# USB Audio Mapper

A Linux utility for creating persistent naming rules for USB audio devices, ensuring they maintain consistent names across reboots and device reconnections.

Part of the [LyreBirdAudio](https://github.com/tomtom215/LyreBirdAudio) project.

**Version**: 3.0.0

## Support the Project

If you find this tool useful, please star the [GitHub repository](https://github.com/tomtom215/LyreBirdAudio) and consider citing it in your projects:

```
USB Audio Mapper (LyreBirdAudio Project)
https://github.com/tomtom215/LyreBirdAudio
Tom F
```

If you use this in production systems, research, or interesting projects, we'd appreciate hearing about it in the GitHub discussions.

## Overview

USB audio devices in Linux are assigned card numbers (card0, card1, etc.) based on detection order. This creates problems:

- Device numbers change after reboots or when other devices are connected
- Application configurations break when card numbers change
- Multiple identical devices cannot be reliably distinguished
- Audio routing becomes unpredictable in complex setups

USB Audio Mapper solves these issues by creating udev rules that assign persistent, user-defined names to your devices. Once configured, devices maintain their names regardless of connection order.

## What's New in v3.0.0

Version 3.0.0 restores backwards compatibility with v1.0.0 while adding production-ready improvements:

**Critical Fixes**:
- USB port paths now use clean format (`3-4`) instead of suffixed format (`usb-3.4-abc12345`)
- Device detection correctly matches by busnum/devnum, preventing false matches in complex USB hubs
- Automatic rule deduplication prevents duplicate rules for the same device
- Reboot confirmation requires typing "YES" with 30-second timeout

**Code Quality**:
- Portable implementation works on minimal systems without md5sum
- New `safe_base10()` function prevents octal interpretation bugs
- Enhanced error handling with default parameters
- Centralized rule generation with `generate_udev_rules()` function
- All configuration values defined as readonly constants

**Migration from v2.0.0**: If upgrading from v2.0.0, you must remove old rules and regenerate. See Migration Guide below.

## Requirements

**Required**:
- `lsusb` (package: `usbutils`)
- `udevadm` (package: `udev` or `systemd`)
- `grep`, `sed`, `cat` (package: `coreutils`)
- Bash 4.0 or later
- Linux kernel 2.6+ with udev support
- Root privileges

**Optional**:
- `aplay` (package: `alsa-utils`) - Enhanced device information display
- `sha256sum` or `sha1sum` - Hash generation (script includes pure bash fallback)

The script checks dependencies at startup and reports missing commands.

## Installation

Download and make executable:

```bash
curl -O https://raw.githubusercontent.com/tomtom215/LyreBirdAudio/main/usb-audio-mapper.sh
chmod +x usb-audio-mapper.sh
```

Or install system-wide:

```bash
sudo curl -o /usr/local/bin/usb-audio-mapper \
  https://raw.githubusercontent.com/tomtom215/LyreBirdAudio/main/usb-audio-mapper.sh
sudo chmod +x /usr/local/bin/usb-audio-mapper
```

## Usage

### Interactive Mode

Run without arguments for guided setup:

```bash
sudo ./usb-audio-mapper.sh
```

The script will:
1. Display detected USB devices and sound cards
2. Prompt for card number to map
3. Ask for USB device confirmation
4. Request a friendly name (lowercase letters, numbers, hyphens; 1-32 characters)
5. Create udev rules with automatic deduplication
6. Offer system reboot (requires "YES" confirmation)

You can also explicitly request interactive mode:

```bash
sudo ./usb-audio-mapper.sh -i
```

### Non-Interactive Mode

For automation or scripting:

```bash
sudo ./usb-audio-mapper.sh -n -d "Device Name" -v VENDOR_ID -p PRODUCT_ID -f friendly-name
```

Required parameters:
- `-n, --non-interactive` : Non-interactive mode
- `-d, --device NAME` : Device name (used in rule comments)
- `-v, --vendor ID` : Vendor ID (4-digit hex)
- `-p, --product ID` : Product ID (4-digit hex)
- `-f, --friendly NAME` : Friendly name (used in device paths)

Optional:
- `-u, --usb-port PORT` : USB port path (required for multiple identical devices)

Example:

```bash
sudo ./usb-audio-mapper.sh -n -d "MOVO X1 MINI" -v 2e88 -p 4610 -f movo-mic
```

Find vendor and product IDs with:

```bash
lsusb | grep -i audio
# Output: Bus 001 Device 003: ID 2e88:4610 USB Audio Device
#         Vendor: 2e88 ^^^^ ^^^^ Product: 4610
```

### Testing Port Detection

Test if your system supports USB port detection:

```bash
sudo ./usb-audio-mapper.sh -t
```

Output shows how many devices can be mapped to physical ports. Port detection is only required for multiple identical devices.

### Debug Mode

Enable detailed output for troubleshooting:

```bash
sudo ./usb-audio-mapper.sh -D
```

Or combine with debug environment variable:

```bash
sudo DEBUG=true ./usb-audio-mapper.sh -t
```

### Viewing Help

View all available options and usage information:

```bash
sudo ./usb-audio-mapper.sh -h
```

Or without sudo to see the help text:

```bash
./usb-audio-mapper.sh --help
```

### Command Reference

Complete list of all available flags and options:

| Flag | Long Form | Required | Description | Example Value |
|------|-----------|----------|-------------|---------------|
| `-i` | `--interactive` | No | Interactive mode (default) | N/A |
| `-n` | `--non-interactive` | For automation | Non-interactive mode | N/A |
| `-d` | `--device` | Yes (non-interactive) | Device name for comments | "MOVO X1 MINI" |
| `-v` | `--vendor` | Yes (non-interactive) | 4-digit hex vendor ID | `2e88` |
| `-p` | `--product` | Yes (non-interactive) | 4-digit hex product ID | `4610` |
| `-u` | `--usb-port` | No | USB port path | `3-4` or `usb-3.4` |
| `-f` | `--friendly` | Yes (non-interactive) | Friendly name (lowercase, hyphens) | `movo-mic` |
| `-t` | `--test` | No | Test USB port detection | N/A |
| `-D` | `--debug` | No | Enable debug output | N/A |
| `-h` | `--help` | No | Show help message | N/A |

## Validation

After running the script and rebooting, verify the configuration:

**Check sound card assignment**:
```bash
cat /proc/asound/cards
```

Your device should show the friendly name instead of the generic name.

**Verify udev rules**:
```bash
sudo cat /etc/udev/rules.d/99-usb-soundcards.rules
```

Expected format for v3.0.0:
```
# USB Sound Card: USB Audio Device
SUBSYSTEM=="sound", ATTRS{idVendor}=="2e88", ATTRS{idProduct}=="4610", ATTR{id}="movo-mic", SYMLINK+="sound/by-id/movo-mic"
```

If port detection succeeded, additional rules will be present with `KERNELS=="3-4"` or `ENV{ID_PATH}` matching.

**Important**: v3.0.0 uses clean port paths (e.g., `3-4`). If you see paths with random characters (e.g., `usb-3.4-abc12345`), you still have v2.0.0 rules.

**Check symlink**:
```bash
ls -la /dev/sound/by-id/
```

Should show a symlink with your friendly name pointing to the actual device.

**Test device access**:
```bash
arecord -D plughw:movo-mic -d 3 test.wav
```

## Troubleshooting

### Device Not Being Renamed

**Diagnosis**:
1. Verify rules exist: `sudo cat /etc/udev/rules.d/99-usb-soundcards.rules`
2. Check vendor/product IDs match: `lsusb | grep -i audio`
3. Reload rules: `sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=sound`
4. Reboot system

**Common causes**:
- Old v2.0.0 rules present (check for suffixed port paths, remove entire file if found)
- Vendor/product IDs don't match device
- Rules file has incorrect permissions (should be 644, owned by root)

### Multiple Identical Devices Not Distinguished

You must use port-specific mapping:

1. Connect devices one at a time and note their ports from `cat /proc/asound/cards`
2. Map each to its specific port:

```bash
sudo ./usb-audio-mapper.sh -n -d "Mic Left" -v 2e88 -p 4610 -u "3" -f mic-left
sudo ./usb-audio-mapper.sh -n -d "Mic Right" -v 2e88 -p 4610 -u "4" -f mic-right
```

3. Keep devices in the same USB ports after configuration

### Port Detection Fails

Run diagnostic test:
```bash
sudo DEBUG=true ./usb-audio-mapper.sh -t
```

If port detection completely fails, the script will still work using vendor/product ID matching only. You won't be able to distinguish between multiple identical devices.

### Script Issues

**Missing dependencies**:
```bash
# Debian/Ubuntu
sudo apt-get install usbutils udev coreutils alsa-utils

# RHEL/Fedora/CentOS
sudo yum install usbutils systemd coreutils alsa-utils

# Arch Linux
sudo pacman -S usbutils systemd coreutils alsa-utils
```

**Check bash version** (must be 4.0+):
```bash
bash --version
```

## Migration from v2.0.0

Version 2.0.0 used an incompatible port path format. To upgrade:

```bash
# Remove old rules
sudo rm /etc/udev/rules.d/99-usb-soundcards.rules

# Regenerate with v3.0.0
sudo ./usb-audio-mapper.sh

# Reboot
sudo reboot
```

After rebooting, verify new rules use clean port paths without serial suffixes.

## Use Cases

**Professional Audio**:
- Live streaming with consistent microphone/mixer identification
- Recording studios requiring deterministic device routing
- Podcast production with guest microphones
- Broadcast automation systems requiring reliable audio paths

**Multi-Device Recording**:
- Stereo capture systems using two microphones as a stereo pair
- Video production with multiple cameras each having USB audio

**Embedded Systems**:
- Raspberry Pi audio projects (voice assistants, monitoring systems)
- Kiosks and digital signage requiring audio after unattended reboots
- Industrial audio applications and IoT sensors
- Automotive infotainment systems

**Education and Research**:
- Computer labs requiring consistent audio across workstations
- Audio engineering curriculum with standardized equipment
- Research laboratories with acoustic measurement equipment
- Language labs with multiple student workstations

**Home Use**:
- Home recording studios
- Gaming and communication setups (Discord, streaming)
- Home theater PCs with multiple audio zones
- Amateur radio digital mode interfaces

## How It Works

### udev Rules System

Linux uses udev to manage device nodes dynamically. When a USB audio device is connected:

1. Kernel detects device and loads drivers
2. udev processes rules from `/etc/udev/rules.d/` and `/usr/lib/udev/rules.d/`
3. Matching rules apply device configuration
4. ALSA registers the sound card

Without persistence rules, ALSA assigns card numbers based on detection order, which varies between boots.

### Rule Types

The script creates up to three rules per device:

**1. Basic Vendor/Product Rule** (always created):
```
SUBSYSTEM=="sound", ATTRS{idVendor}=="2e88", ATTRS{idProduct}=="4610", ATTR{id}="movo-mic", SYMLINK+="sound/by-id/movo-mic"
```
Matches any device with these IDs. Cannot distinguish multiple identical devices.

**2. USB Port Rule** (if port detected):
```
SUBSYSTEM=="sound", KERNELS=="3-4", ATTRS{idVendor}=="2e88", ATTRS{idProduct}=="4610", ATTR{id}="movo-mic", SYMLINK+="sound/by-id/movo-mic"
```
Matches device on specific physical port. Can distinguish identical devices on different ports.

**3. Platform Path Rule** (if platform path detected):
```
SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-xhci-hcd.0-usb-0:1.4:1.0", ATTRS{idVendor}=="2e88", ATTRS{idProduct}=="4610", ATTR{id}="movo-mic", SYMLINK+="sound/by-id/movo-mic"
```
Most specific matching using complete platform path. Works reliably with complex USB topologies.

### Rule Actions

When a rule matches:
- `ATTR{id}="friendly-name"` sets the ALSA card ID (appears in `/proc/asound/cards`)
- `SYMLINK+="sound/by-id/friendly-name"` creates persistent symlink in `/dev/sound/by-id/`

### v3.0.0 vs v2.0.0 Rule Differences

**v2.0.0** (incompatible):
```
KERNELS=="usb-3.4-a8f3b2c1"  # Serial suffix breaks v1.0.0 compatibility
```

**v3.0.0** (fixed):
```
KERNELS=="3-4"  # Clean path, v1.0.0 compatible
```

The v3.0.0 approach maintains compatibility, works reliably across distributions, and prevents false matches.

## Uninstallation

Remove all rules:

```bash
sudo rm /etc/udev/rules.d/99-usb-soundcards.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=sound
sudo reboot
```

To remove rules for a specific device only, edit the file and delete the relevant lines, then reload udev.

## Advanced Usage

### Batch Configuration

Create a script to configure multiple devices:

```bash
#!/bin/bash
DEVICES=(
  "MOVO X1 MINI|2e88|4610|3|movo-left"
  "MOVO X1 MINI|2e88|4610|4|movo-right"
  "Blue Yeti|b58e|9e84||blue-yeti"
)

for device in "${DEVICES[@]}"; do
  IFS='|' read -r name vendor product port friendly <<< "$device"
  
  if [ -n "$port" ]; then
    sudo ./usb-audio-mapper.sh -n -d "$name" -v "$vendor" -p "$product" -u "$port" -f "$friendly"
  else
    sudo ./usb-audio-mapper.sh -n -d "$name" -v "$vendor" -p "$product" -f "$friendly"
  fi
done
```

### Custom Rule Modification

Generate initial rules with the script, then edit `/etc/udev/rules.d/99-usb-soundcards.rules` to add custom attributes:

```
SUBSYSTEM=="sound", ATTRS{idVendor}=="2e88", ATTRS{idProduct}=="4610", ATTR{id}="my-device", SYMLINK+="sound/by-id/my-device", GROUP="audio", MODE="0660"
```

Reload rules after editing:
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=sound
```

## Changelog

### Version 3.0.0 (October 2025)

**Breaking Changes**:
- Complete refactor from LyreBirdAudio project codebase
- USB port path format changed from suffixed to clean format
- Requires removal of old rules file when upgrading from v2.0.0

**Critical Fixes**:
- USB port detection now correctly identifies devices by busnum/devnum matching
- Port paths use clean format (e.g., `3-4`) for v1.0.0 compatibility
- Automatic rule deduplication prevents duplicate rules
- Reboot requires typing "YES" instead of single keypress

**New Features**:
- `safe_base10()` prevents octal interpretation bugs
- `get_portable_hash()` with multiple fallbacks (no md5sum dependency)
- `generate_udev_rules()` centralizes rule generation
- Readonly constants for all configuration values
- Expanded signal handling (EXIT INT TERM HUP QUIT)

**Code Quality**:
- Consistent use of printf instead of echo for POSIX compliance
- Enhanced error handling with default parameters
- Advanced terminal color detection with graceful degradation
- Reduced from 1,431 to 1,175 lines while adding functionality

**Compatibility**:
- v3.0.0 works with v1.0.0 rules (v2.0.0 did not)
- v3.0.0 works with v2.0.0 rules after regeneration
- v3.0.0 works with v3.0.0 rules

### Version 2.0 (2025) - Deprecated

Added error checking, atomic operations, and dependency validation. Broke v1.0.0 compatibility with suffixed port paths. Users should upgrade to v3.0.0.

### Version 1.0 (2025)

Initial release with core functionality, multi-method detection, and interactive/non-interactive modes.

## License

USB Audio Mapper is licensed under the Apache License 2.0.

Copyright 2025 Tom F and LyreBirdAudio Contributors

## Contributing

Contributions are welcome. Please ensure changes:

- Maintain backwards compatibility with v1.0.0 rules
- Include error handling and validation
- Pass shellcheck validation
- Are tested on multiple distributions (Ubuntu, Debian, Fedora, Arch)
- Include documentation updates

**Submission process**:
1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Ensure shellcheck passes
5. Submit pull request with detailed description

## Support

**Issues**: https://github.com/tomtom215/LyreBirdAudio/issues

When reporting issues, include:
- Linux distribution and version
- Kernel version (`uname -r`)
- Output of `lsusb` and `cat /proc/asound/cards`
- Script output with debug enabled (`-D`)
- Contents of `/etc/udev/rules.d/99-usb-soundcards.rules`

## FAQ

**Q: Do I need to run this every time I plug in my device?**  
A: No. Rules persist and apply automatically.

**Q: Will this break my existing audio setup?**  
A: No. It only affects devices you explicitly configure.

**Q: What if two devices have the same vendor and product ID?**  
A: Use port-specific mapping with the `-u` flag.

**Q: Can I edit the generated rules manually?**  
A: Yes. Edit `/etc/udev/rules.d/99-usb-soundcards.rules` and reload with `udevadm`.

**Q: Why does the script create multiple rules per device?**  
A: For reliability. Basic matching, port-specific, and platform-specific rules provide fallback options.

**Q: What happens if I move my device to a different USB port?**  
A: With port-specific rules, the name follows the port. Without port-specific rules, the name follows the device.

**Q: Does this work in a virtual machine?**  
A: Yes, but USB port detection may be less reliable. Basic vendor/product matching always works.

**Q: I'm upgrading from v2.0.0 - do I have to?**  
A: Yes. v2.0.0 has compatibility issues and bugs. Remove old rules and regenerate with v3.0.0.

---

**Project**: [LyreBirdAudio](https://github.com/tomtom215/LyreBirdAudio)  
**Version**: 3.0.0  
**License**: Apache 2.0
