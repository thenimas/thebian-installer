# thebian-installer
Automatic setup script for my personal debian config.

This script is intended to be run from a live environment. I recommend the Debian Live Standard ISO.
https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/

## Features
- Automated installation with encryption support
- i3 Window Manager preconfigured with my preferred bindings and visual configuration
- Preinstalled utilites for coding, file syncing and snapshotting.
- Support for up-to-date applications via Flatpak.

## Minimum Requirements
- 64-bit Intel or AMD CPU
- 2GB of available RAM
- 8GB of disk space 
  - >32GB recommended for standard use
- UEFI/GPT Booting
  - Secure Boot is not required but it is recommended, and should work without any modification.
- Valid internet connection (for the installation)

## Usage
The script simply can be downloaded and run as root.
```
wget https://github.com/thenimas/thebian-installer/raw/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

You will be given three options for the installation:
```
1. Install Debian to disk formatted with LUKS encryption (recommended)
2. Install Debian without encryption
3. Manual install to /target (advanced)
```
Encryption is recommended for security, but you have the option to just have a normal BTRFS filesystem for instances where this is not needed (i.e virtual machines.)

Manually installing to /target is primarily for when a specific partitioning setup is needed (RAID, dual booting, etc). The partition needs to be mounted at /target and with a valid partition at /target/boot/efi. Note that you must configure fstab manually.

The installation takes about 15-30 minutes on a good internet connection.
