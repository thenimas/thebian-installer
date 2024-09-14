# thebian-installer
Automatic setup script for my personal debian config, with i3 as the wm and all of the software I use.

This script is intended to be run from a live environment, preferably a cloud image written to a USB drive.
https://cloud.debian.org/images/cloud/

## Usage
The disks being installed to still need to be partitioned manually. This can be done in any reasonable configuration, as long as there is a partition for /boot/efi. This configuration only supports EFI booting.

The script will generate an fstab file for you if you don't make one manually.

An auto-partitioning script may be added in the future.

1. Create a folder (if it doesn't exist) named /target/, and mount the root to it. Make sure the EFI partition is also mounted at /target/boot/efi.
2. Download the script to your live environment (`wget github.com/thenimas/thebian-installer/raw/main/setup.sh`)
3. Give it executing priveleges (`chmod +x setup.sh`) and run the script.
4. The script will prompt for a username, password and hostname. After that, the setup will run without any further input needed.
5. The script will prompt once the installation is complete, and the machine can then be restarted.

The installation requires about 10GB of free space and takes about 15-30 minutes on a good internet connection.
