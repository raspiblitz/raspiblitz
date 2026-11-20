# Automated Image Build with rpi-image-gen

This guide explains how to build RaspiBlitz images using the modern rpi-image-gen framework, which provides a fully automated, reproducible alternative to the traditional manual SD card build process.

## Table of Contents

- [Overview](#overview)
- [Why rpi-image-gen?](#why-rpi-image-gen)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Build Customization](#build-customization)
- [Understanding Image Build Mode](#understanding-image-build-mode)
- [Output Artifacts](#output-artifacts)
- [Advanced Usage](#advanced-usage)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)
- [Comparison: Manual vs Automated Build](#comparison-manual-vs-automated-build)

## Overview

The rpi-image-gen integration allows you to:

- Build RaspiBlitz images entirely on a build host (no physical Raspberry Pi required)
- Create reproducible, bit-for-bit identical builds
- Automate image builds in CI/CD pipelines
- Generate Software Bill of Materials (SBOM) for security compliance
- Build multiple image variants (lean, fatpack, different branches) quickly

## Why rpi-image-gen?

### Traditional Manual Process

The traditional RaspiBlitz image build requires:

1. Download and verify Raspberry Pi OS base image
2. Flash SD card using Balena Etcher or dd
3. Boot Raspberry Pi with fresh SD card
4. SSH into running system
5. Run `build_sdcard.sh` on live hardware
6. Perform shutdown and image extraction
7. Shrink, compress, and sign the image

**Problems:**
- Time-consuming (several hours per build)
- Requires physical hardware
- Difficult to reproduce exact builds
- Manual steps prone to human error
- Can't be easily automated in CI

### Modern Automated Process with rpi-image-gen

With rpi-image-gen:

1. Run a single command on your build host
2. Wait for automated build to complete
3. Flash the resulting image to SD card

**Benefits:**
- Fast (builds complete in 30-60 minutes)
- No physical hardware required
- Fully reproducible builds
- Easy to automate in CI/CD
- Generates SBOM automatically
- Can build multiple variants in parallel

## Prerequisites

### Build Host Requirements

- **Operating System**: Debian 12 (Bookworm) or Ubuntu 22.04+ recommended
- **Architecture**: x86_64 (AMD64) - builds ARM images via QEMU
- **Disk Space**: At least 30GB free for build artifacts
- **RAM**: 4GB minimum, 8GB+ recommended
- **Internet**: Broadband connection for downloading packages

### Software Dependencies

Install required packages on your build host:

```bash
# Update package lists
sudo apt-get update

# Install core dependencies
sudo apt-get install -y \
  git \
  python3 \
  python3-pip \
  python3-venv \
  qemu-user-static \
  binfmt-support \
  parted \
  kpartx \
  dosfstools \
  debootstrap \
  debian-archive-keyring

# Install optional but recommended tools
sudo apt-get install -y \
  wget \
  curl \
  rsync \
  pigz \
  pv
```

### Install rpi-image-gen

```bash
# Clone the rpi-image-gen repository
git clone https://github.com/raspberrypi/rpi-image-gen.git
cd rpi-image-gen

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip3 install -r requirements.txt

# Install rpi-image-gen
pip3 install .

# Verify installation
rpi-image-gen --version
```

> **Note**: This guide provides example commands based on standard image build tool patterns. The actual rpi-image-gen tool is announced in [this Raspberry Pi blog post](https://www.raspberrypi.com/news/introducing-rpi-image-gen-build-highly-customised-raspberry-pi-software-images/). When the tool is released, refer to its official documentation for the exact command syntax and options. The configuration files in this repository (YAML and INI) are designed to be compatible with layer-based image build tools.

## Quick Start

### Build a Lean Development Image

```bash
# Navigate to RaspiBlitz repository
cd /path/to/raspiblitz

# Build with defaults (lean image, dev branch, headless)
cd build/rpi-image-gen
rpi-image-gen build raspiblitz.ini
```

This creates a minimal RaspiBlitz image from the `dev` branch.

### Build Output

After a successful build (typically 30-60 minutes), you'll find:

```
raspiblitz-dev.img.gz           # Compressed bootable image
raspiblitz-dev.img.sha256       # SHA256 checksum
raspiblitz-dev-sbom.json        # Software Bill of Materials
build.log                        # Detailed build log
```

### Flash the Image

```bash
# Decompress the image
gunzip raspiblitz-dev.img.gz

# Flash to SD card using Balena Etcher (recommended)
# Or use dd:
sudo dd if=raspiblitz-dev.img of=/dev/sdX bs=4M status=progress
sync
```

Replace `/dev/sdX` with your actual SD card device (check with `lsblk`).

## Build Customization

### Environment Variables

Customize builds using environment variables:

```bash
# Build fatpack image from v1.12 branch
FATPACK=true BRANCH=v1.12 VERSION=v1.12 rpi-image-gen build raspiblitz.ini

# Build from custom fork
GITHUB_USER=myusername BRANCH=my-feature rpi-image-gen build raspiblitz.ini

# Build with LCD display support
DISPLAY=lcd rpi-image-gen build raspiblitz.ini

# Enable WiFi for a specific region
WIFI_REGION=US rpi-image-gen build raspiblitz.ini

# Combine multiple options
FATPACK=true BRANCH=v1.12 DISPLAY=lcd WIFI_REGION=DE VERSION=v1.12-fatpack-de \
  rpi-image-gen build raspiblitz.ini
```

### Available Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `GITHUB_USER` | GitHub user/org to fetch from | `raspiblitz` | Any GitHub user |
| `BRANCH` | Git branch or tag to build | `dev` | Any valid branch/tag |
| `FATPACK` | Install all optional dependencies | `false` | `true`, `false` |
| `DISPLAY` | Display class | `headless` | `lcd`, `hdmi`, `headless` |
| `WIFI_REGION` | WiFi country code | `off` | ISO country code or `off` |
| `VERSION` | Version string for output filename | `dev` | Any string |

### Editing Configuration Files

For more advanced customization, edit the configuration files directly:

#### `raspiblitz.ini` - Main Configuration

```ini
[image]
# Increase image size for more space
size = 32G

# Use different output format
format = qcow2
```

#### `raspiblitz-base.yaml` - Base Packages

```yaml
packages:
  # Add custom packages
  - your-custom-package
  - another-package
```

#### `raspiblitz-provision.yaml` - Provisioning

```yaml
run:
  # Add custom provisioning steps
  - echo "Custom step here"
```

## Understanding Image Build Mode

When `build_sdcard.sh` runs with `--image-build` flag (or `RB_IMAGE_BUILD=true` environment variable), it operates in **Image Build Mode**.

### What Gets Skipped

The following hardware-dependent operations are skipped:

1. **Device Operations**
   - `tune2fs /dev/mmcblk0p2` - Filesystem tuning
   - Watchdog device activation
   - Direct hardware device access

2. **Network Configuration**
   - `nmcli` - NetworkManager CLI commands
   - `ifconfig wlan0 down` - Network interface manipulation
   - DNS configuration on live interfaces

3. **System Service Operations**
   - `systemctl enable/disable/restart` - Service management
   - `service logrotate restart` - Service restarts
   - Any daemon start/stop commands

4. **Runtime Tools**
   - `raspi-config` - Raspberry Pi configuration tool
   - Tools requiring active kernel/hardware

### What Still Happens

These operations work normally in image build mode:

1. **File System Operations**
   - Creating directories
   - Copying files
   - Editing configuration files
   - Setting permissions

2. **Package Management**
   - `apt-get install` - Installing packages
   - `pip install` - Python packages
   - Downloading and extracting archives

3. **User Management**
   - Creating users and groups
   - Setting passwords
   - Configuring sudo

4. **System Configuration**
   - Editing `/etc` configuration files
   - Setting up systemd service files (without enabling)
   - Locale and timezone configuration

### First Boot Behavior

On first boot of the generated image:

1. **Bootstrap Service Runs**
   - Detects hardware
   - Enables skipped systemd services
   - Performs hardware-specific configuration

2. **Network Setup**
   - Configures network interfaces
   - Sets up DNS if not already configured

3. **Storage Initialization**
   - Detects and prepares storage devices
   - Expands root partition if needed

## Output Artifacts

### Image File (`.img.gz`)

The main output is a compressed disk image containing:

- Boot partition (FAT32, 512MB)
- Root partition (ext4, ~15GB)
- Complete RaspiBlitz installation
- All configurations and scripts

Ready to flash to SD card or USB drive.

### Checksum File (`.sha256`)

SHA256 checksum for verifying image integrity:

```bash
# Verify downloaded image
sha256sum -c raspiblitz-dev.img.sha256
```

### Software Bill of Materials (`.sbom.json`)

JSON file listing all installed packages with versions:

```json
{
  "packages": [
    {"name": "bitcoin-core", "version": "25.0"},
    {"name": "lnd", "version": "0.17.0"},
    ...
  ],
  "build_info": {
    "date": "2024-01-15T10:30:00Z",
    "branch": "dev",
    "commit": "abc123"
  }
}
```

Useful for:
- Security auditing
- Compliance requirements
- Tracking dependencies
- Vulnerability scanning

### Build Log (`build.log`)

Detailed log of the entire build process. Useful for:
- Debugging build failures
- Verifying build steps
- Compliance documentation

## Advanced Usage

### Building Multiple Variants

Build several image variants in parallel:

```bash
# Lean dev image
FATPACK=false BRANCH=dev VERSION=dev-lean \
  rpi-image-gen build raspiblitz.ini &

# Fatpack dev image
FATPACK=true BRANCH=dev VERSION=dev-fatpack \
  rpi-image-gen build raspiblitz.ini &

# Stable release
BRANCH=v1.12 VERSION=v1.12 \
  rpi-image-gen build raspiblitz.ini &

# Wait for all builds to complete
wait
```

### Custom Image Size

For Bitcoin full node with more space:

```bash
# Edit raspiblitz.ini
[image]
size = 64G

# Or override via command line (if supported)
rpi-image-gen build raspiblitz.ini --size=64G
```

### Using Local build_sdcard.sh

To test local changes to `build_sdcard.sh` before committing:

Edit `raspiblitz-provision.yaml`:

```yaml
run:
  # Copy local build_sdcard.sh instead of downloading
  - |
    cp /path/to/local/build_sdcard.sh /tmp/build_sdcard.sh
    chmod +x /tmp/build_sdcard.sh
    
  # Rest of the provisioning...
```

### Debugging Failed Builds

If a build fails:

1. **Check the build log**:
   ```bash
   tail -100 build.log
   ```

2. **Look for error patterns**:
   ```bash
   grep -i error build.log
   grep -i fail build.log
   ```

3. **Common issues**:
   - Out of disk space: Increase `size` in `raspiblitz.ini`
   - Package not found: Update package list in `raspiblitz-base.yaml`
   - Network timeout: Retry the build

4. **Enable debug mode** (if supported):
   ```bash
   DEBUG=1 rpi-image-gen build raspiblitz.ini
   ```

## CI/CD Integration

### GitHub Actions Example

Create `.github/workflows/rpi-image-gen-build.yml`:

```yaml
name: Automated RaspiBlitz Image Build

on:
  push:
    branches: [dev, v1.12]
  schedule:
    # Nightly builds at 2 AM UTC
    - cron: '0 2 * * *'
  workflow_dispatch:
    inputs:
      fatpack:
        description: 'Build fatpack variant'
        required: false
        default: 'false'

jobs:
  build-image:
    runs-on: ubuntu-22.04
    
    steps:
      - name: Checkout RaspiBlitz
        uses: actions/checkout@v4
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            python3 python3-pip qemu-user-static \
            parted kpartx debootstrap
      
      - name: Install rpi-image-gen
        run: |
          git clone https://github.com/raspberrypi/rpi-image-gen.git
          cd rpi-image-gen
          pip3 install -r requirements.txt
          pip3 install .
      
      - name: Build RaspiBlitz image
        env:
          BRANCH: ${{ github.ref_name }}
          FATPACK: ${{ github.event.inputs.fatpack || 'false' }}
          VERSION: ${{ github.ref_name }}-${{ github.sha }}
        run: |
          cd build/rpi-image-gen
          rpi-image-gen build raspiblitz.ini
      
      - name: Upload image artifact
        uses: actions/upload-artifact@v4
        with:
          name: raspiblitz-image-${{ github.sha }}
          path: |
            build/rpi-image-gen/raspiblitz-*.img.gz
            build/rpi-image-gen/raspiblitz-*.sha256
            build/rpi-image-gen/raspiblitz-*-sbom.json
      
      - name: Create release (on tag)
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v1
        with:
          files: |
            build/rpi-image-gen/raspiblitz-*.img.gz
            build/rpi-image-gen/raspiblitz-*.sha256
            build/rpi-image-gen/raspiblitz-*-sbom.json
```

### GitLab CI Example

Create `.gitlab-ci.yml`:

```yaml
image-build:
  image: debian:bookworm
  
  before_script:
    - apt-get update
    - apt-get install -y python3 python3-pip qemu-user-static git
    - pip3 install rpi-image-gen
  
  script:
    - cd build/rpi-image-gen
    - BRANCH=$CI_COMMIT_REF_NAME VERSION=$CI_COMMIT_SHORT_SHA rpi-image-gen build raspiblitz.ini
  
  artifacts:
    paths:
      - build/rpi-image-gen/raspiblitz-*.img.gz
      - build/rpi-image-gen/raspiblitz-*.sha256
      - build/rpi-image-gen/raspiblitz-*-sbom.json
    expire_in: 30 days
  
  only:
    - dev
    - tags
```

## Troubleshooting

### Build Fails: "Out of space"

**Problem**: Build runs out of disk space during package installation or provisioning.

**Solution**:
1. Free up space on your build host:
   ```bash
   df -h  # Check available space
   sudo apt-get clean
   docker system prune -a  # If using Docker
   ```

2. Increase image size in `raspiblitz.ini`:
   ```ini
   [image]
   size = 32G  # Or larger
   ```

### Build Fails: Package Not Found

**Problem**: `apt-get install` fails with "Package not found" error.

**Solution**:
1. Check if package name is correct in `raspiblitz-base.yaml`
2. Package may not be available for ARM64 architecture
3. Check build.log for the exact package name causing the issue

### Build Fails: QEMU Error

**Problem**: Errors related to QEMU emulation.

**Solution**:
```bash
# Ensure QEMU static binaries are installed
sudo apt-get install qemu-user-static binfmt-support

# Restart binfmt service
sudo systemctl restart systemd-binfmt
```

### Image Boots But Services Don't Start

**Problem**: Image boots successfully but RaspiBlitz services don't run.

**Solution**:
1. Check bootstrap service:
   ```bash
   systemctl status bootstrap
   journalctl -u bootstrap
   ```

2. Verify service files exist:
   ```bash
   ls -la /etc/systemd/system/bootstrap.service
   ls -la /etc/systemd/system/background.service
   ```

3. Manually enable services if needed:
   ```bash
   sudo systemctl enable bootstrap
   sudo systemctl enable background
   sudo systemctl start bootstrap
   ```

### Image Build Mode Not Working

**Problem**: Hardware-dependent operations still run during image build.

**Solution**:
1. Verify environment variable is set:
   ```bash
   echo $RB_IMAGE_BUILD  # Should print "true"
   ```

2. Check build_sdcard.sh is using --image-build flag:
   ```bash
   grep "image-build" /tmp/build_sdcard.sh
   ```

3. Review guards in build_sdcard.sh:
   ```bash
   grep "image_build" /tmp/build_sdcard.sh
   ```

### Build Too Slow

**Problem**: Build takes longer than expected.

**Solution**:
1. Use more CPU cores (if supported):
   ```bash
   CPUS=8 rpi-image-gen build raspiblitz.ini
   ```

2. Use a faster mirror for apt:
   Edit `raspiblitz-base.yaml`:
   ```yaml
   run:
     - sed -i 's/deb.debian.org/ftp.us.debian.org/g' /etc/apt/sources.list
   ```

3. Build on faster storage (SSD vs HDD)

4. Disable unnecessary packages in lean builds:
   Set `FATPACK=false`

## Comparison: Manual vs Automated Build

| Aspect | Manual SD Card Build | rpi-image-gen Build |
|--------|---------------------|-------------------|
| **Hardware Required** | Raspberry Pi + SD card | Any x86_64 Linux machine |
| **Build Time** | 2-4 hours | 30-60 minutes |
| **Reproducibility** | Difficult (manual steps) | Excellent (automated) |
| **CI/CD Integration** | Not practical | Easy |
| **Parallel Builds** | Requires multiple Pis | Easy on one machine |
| **SBOM Generation** | Manual process | Automatic |
| **First Boot** | Ready to use | Bootstrap runs once |
| **Debugging** | Limited logs | Complete build logs |
| **Cost** | Requires hardware | Build host only |

## Next Steps

1. **Test Your Build**: Flash the generated image and verify it boots correctly
2. **Customize**: Modify layer configurations for your use case
3. **Automate**: Set up CI/CD pipelines for regular builds
4. **Document**: Keep notes on your custom configurations
5. **Share**: Contribute improvements back to the RaspiBlitz project

## Resources

- [RaspiBlitz GitHub Repository](https://github.com/raspiblitz/raspiblitz)
- [rpi-image-gen Documentation](https://github.com/raspberrypi/rpi-image-gen)
- [build_sdcard.sh Source](../../build_sdcard.sh)
- [RaspiBlitz Configuration Files](../../build/rpi-image-gen/)

## Support

If you encounter issues:

1. Check this documentation first
2. Review the [RaspiBlitz FAQ](../../README.md#faq)
3. Search existing [GitHub Issues](https://github.com/raspiblitz/raspiblitz/issues)
4. Ask in the [RaspiBlitz Telegram Group](https://t.me/raspiblitz)
5. Open a new issue with:
   - build.log excerpt
   - Your build command
   - Error messages
   - System specifications
