# RaspiBlitz rpi-image-gen Integration

This directory contains configuration files for building RaspiBlitz images using the [rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen) framework.

## Overview

The rpi-image-gen integration allows for fully automated, reproducible builds of RaspiBlitz images without requiring physical hardware or manual SD card operations.

## Files

- **raspiblitz-base.yaml** - Base layer configuration with system packages
- **raspiblitz-provision.yaml** - Provision layer that runs build_sdcard.sh in image build mode
- **raspiblitz.ini** - Main build configuration file
- **README.md** - This file

## Quick Start

### Prerequisites

1. Install rpi-image-gen on a Debian/Ubuntu build host:
   ```bash
   sudo apt-get update
   sudo apt-get install -y git python3 python3-pip qemu-user-static
   git clone https://github.com/raspberrypi/rpi-image-gen.git
   cd rpi-image-gen
   sudo pip3 install -r requirements.txt
   ```

2. Ensure you have adequate disk space (at least 20GB free)

### Building an Image

1. Navigate to this directory:
   ```bash
   cd build/rpi-image-gen
   ```

2. Build with default settings (lean image, dev branch):
   ```bash
   rpi-image-gen build raspiblitz.ini
   ```

3. Build with custom parameters:
   ```bash
   # Fatpack image from specific branch
   FATPACK=true BRANCH=v1.12 rpi-image-gen build raspiblitz.ini
   
   # Custom GitHub user and branch
   GITHUB_USER=myuser BRANCH=mybranch rpi-image-gen build raspiblitz.ini
   
   # Different display class
   DISPLAY=lcd rpi-image-gen build raspiblitz.ini
   ```

### Build Variables

You can customize the build by setting environment variables:

- `GITHUB_USER` - GitHub user/org to fetch RaspiBlitz from (default: raspiblitz)
- `BRANCH` - Git branch or tag to build (default: dev)
- `FATPACK` - Install all optional dependencies (default: false)
- `DISPLAY` - Display class: lcd, hdmi, or headless (default: headless)
- `WIFI_REGION` - WiFi country code or 'off' (default: off)
- `VERSION` - Version string for output filename (default: dev)

### Output

After a successful build, you'll find:

- **raspiblitz-{VERSION}.img.gz** - Compressed image file ready to flash
- **raspiblitz-{VERSION}.img.sha256** - Checksum file
- **raspiblitz-{VERSION}-sbom.json** - Software Bill of Materials (if enabled)
- **build.log** - Detailed build log

### Flashing the Image

Use [Balena Etcher](https://www.balena.io/etcher/) or `dd`:

```bash
# Uncompress
gunzip raspiblitz-dev.img.gz

# Flash to SD card (replace /dev/sdX with your SD card device)
sudo dd if=raspiblitz-dev.img of=/dev/sdX bs=4M status=progress
sync
```

## How It Works

1. **Base Layer** (`raspiblitz-base.yaml`):
   - Installs system packages
   - Creates admin user
   - Configures locale and timezone

2. **Provision Layer** (`raspiblitz-provision.yaml`):
   - Downloads `build_sdcard.sh` from GitHub
   - Runs it with `--image-build` flag
   - This skips all hardware-dependent operations
   - Installs RaspiBlitz components and configurations

3. **First Boot**:
   - The RaspiBlitz bootstrap service runs on first boot
   - It performs hardware-specific initialization
   - Enables systemd services that were skipped during image build

## Differences from Manual SD Card Build

### Skipped During Image Build

The following operations are skipped when `--image-build` is used:

- Hardware device operations (tune2fs, watchdog)
- Network interface configuration (nmcli, ifconfig)
- systemctl enable/disable commands
- raspi-config runtime operations
- Service restarts

### Deferred to First Boot

These operations are performed by the bootstrap service on first boot:

- Hardware detection and configuration
- Network setup
- Service enablement
- Display configuration
- Storage initialization

## Troubleshooting

### Build fails with "out of space"

Increase the image size in `raspiblitz.ini`:
```ini
size = 32G  # or larger
```

### Build fails during package installation

Check `build.log` for apt errors. You may need to update the package list in `raspiblitz-base.yaml`.

### Image boots but services don't start

Check that the bootstrap service is present and executable:
```bash
ls -la /home/admin/_bootstrap.sh
systemctl status bootstrap
```

## CI/CD Integration

See the [GitHub Actions workflow example](../../.github/workflows/rpi-image-gen-build.yml) for automated builds in CI.

## More Information

- [RaspiBlitz Documentation](../../README.md)
- [rpi-image-gen Documentation](https://github.com/raspberrypi/rpi-imager-gen)
- [Automated Image Build Guide](../../docs/development/automatic-image-build.md)
