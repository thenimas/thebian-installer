# thebian-installer
Automatic setup script for my personal debian config.

This script is intended to be run from a live environment. I recommend the Debian Live Standard ISO.
https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/

## Features
- (Mostly) no input required for the installation
- i3 Window Manager preconfigured with my preferred bindings and visual configuration
- Preinstalled utilites for coding, file syncing and snapshotting.
- Support for up-to-date applications via Flatpak.

## Requirements
- A 64-bit Intel or AMD CPU
- At least 2GB of available RAM
- 12GB of disk space
- UEFI Booting
- A valid internet connection (for the installation)

## Usage
The disks being installed to still need to be partitioned and formatted manually. This can be done in any reasonable configuration, as long as there is a partition for /boot/efi.

I recommend formatting the main partition with BTRFS, creating a root subvolume (`btrfs subvol create /target/@`) and remounting with the switch `-o subvol=/@`. This will ensure you can take full advantage of Timeshift for snapshotting.

If your root partition is in a LUKS encrypted volume, you will need to specify the additional package `cryptsetup-initramfs` and manually set up a crypttab.

The script will generate an fstab file for you.

1. Create a folder (if it doesn't exist) named /target/, and mount the root to it. Make sure the EFI partition is also mounted at /target/boot/efi.
2. Download the script to your live environment (`wget github.com/thenimas/thebian-installer/raw/main/setup.sh`)
3. Give it executing priveleges (`chmod +x setup.sh`) and run the script.
4. The script will prompt for a username, password and hostname. After that, the setup will run.
5. The script will prompt once the installation is complete, and the machine can then be restarted.

The installation takes about 15-30 minutes on a good internet connection.
