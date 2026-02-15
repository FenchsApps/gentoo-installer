# Awesome Installer — Gentoo Linux (OpenRC + UEFI)

A semi-automated installation script for Gentoo Linux on AMD64 systems with **OpenRC** init and **UEFI** boot.

The script follows the [Gentoo Handbook (AMD64)](https://wiki.gentoo.org/wiki/Handbook:AMD64) and automates most of the installation steps while still letting you make key decisions interactively (profile, USE flags, locales, etc.).

## Partition Layout

The script creates a **GPT** partition table with three partitions:

| # | Name   | Size              | Filesystem | Purpose              |
|---|--------|-------------------|------------|----------------------|
| 1 | EFI    | 256 MiB           | FAT32      | EFI System Partition |
| 2 | swap   | 4 GiB             | swap       | Swap                 |
| 3 | rootfs | Remainder of disk | ext4       | Root filesystem `/`  |

## What Gets Installed

- **Kernel**: `gentoo-kernel` or `gentoo-kernel-bin` (your choice)
- **Bootloader**: GRUB (EFI 64-bit)
- **Init system**: OpenRC
- **Networking**: dhcpcd, iw, wpa_supplicant
- **Firmware**: linux-firmware, sof-firmware
- **Utilities**: sysklogd, chrony

## Prerequisites

- Boot from a [Gentoo Minimal Installation CD](https://www.gentoo.org/downloads/) (or any live environment with `parted`, `wget`, and `chroot` available).
- A working internet connection.
- A UEFI-capable system.

## Usage

1. Boot into the live environment.

2. Download the script:

   ```bash
   wget https://raw.githubusercontent.com/<user>/gentoo-installer/main/awesome-installer-openrc-uefi.sh
   ```

3. Make it executable and run:

   ```bash
   chmod +x awesome-installer-openrc-uefi.sh
   bash awesome-installer-openrc-uefi.sh
   ```

4. Follow the interactive prompts:

   | Prompt           | Example              | Description                                  |
   |------------------|----------------------|----------------------------------------------|
   | Disk             | `/dev/sda`           | Target disk (**all data will be erased!**)    |
   | Hostname         | `gentoo`             | System hostname                               |
   | Root password    | _(hidden input)_     | Password for the root account                 |
   | Timezone         | `Europe/Moscow`      | See `/usr/share/zoneinfo/`                    |
   | Kernel           | `gentoo-kernel-bin`  | `gentoo-kernel` (compiled) or `gentoo-kernel-bin` (prebuilt) |

5. During installation the script will pause several times to let you edit configuration files (`make.conf`, `locale.gen`, `/etc/hosts`) and choose a Portage profile and locale via `eselect`.

6. After completion the system reboots into the new Gentoo installation.

## Disk Naming

The script automatically detects **NVMe** (`/dev/nvme0n1`) and **MMC** (`/dev/mmcblk0`) disks and uses the correct partition suffix (`p1`, `p2`, `p3`). For standard SATA/SCSI disks (`/dev/sda`) it uses `1`, `2`, `3`.

## Warnings

- **This script will wipe the entire target disk.** Double-check the disk name before proceeding.
- The stage3 tarball URL is hardcoded. If it becomes unavailable, update the URL in the script with a current one from [Gentoo Downloads](https://www.gentoo.org/downloads/).
- This script is intended for fresh installations only — do not run it on a system with existing data you want to keep.

## License

This project is licensed under the [GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE).
