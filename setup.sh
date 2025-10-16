#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root!"
   exit 1
fi

echo "Verifying required packages..."
apt install --no-install-recommends fdisk rsync btrfs-progs tar wget lshw smartmontools cryptsetup -yy >> /dev/null

echo " "

echo "Welcome to the Thebian installer!"
echo "Please select an installation option:"
echo " "

echo "1. Install Debian to disk formatted with LUKS encryption (recommended)"
echo "2. Install Debian without encryption"
echo "3. Manual install to /target (advanced)"

echo " "

INSTALL_TYPE="0"

CRYPT_NAME=""

until [ "$INSTALL_TYPE" -ge 1 ] && [ "$INSTALL_TYPE" -le 3 ]; do
    read -p "(1,2,3): " INSTALL_TYPE
done

echo " "

read -p "Enter new username: " USER_NAME
echo " "

read -p "Enter new name for your PC (hostname): " HOST_NAME
echo " "

willWriteRandom="N"

if [ "$INSTALL_TYPE" == 1 ]; then
    echo "IMPORTANT WARNING:"
    echo " "
    echo "After the partitioning is complete, you will be prompted to set up an encryption password. If you lose this password, there is 100% NO way to recover it and you will lose access to all of your data."
    echo " "
    confirm=" "
    read -p "Type YES in all capital letters to continue: " confirm
    if [ ! $confirm = "YES" ]; then
        echo "Aborting."
        exit 0
    fi
    echo " "
fi 

if [ "$INSTALL_TYPE" == 3 ]; then
    if ! cat /proc/mounts | grep -q "/target " ; then
        echo "ERROR: /target not mounted!"
        exit 1
    fi
    if ! cat /proc/mounts | grep -q "/target/boot/efi " ; then
        echo "ERROR: /target/boot/efi not mounted!"
        exit 1
    fi
else
    availableDisks="$(lsblk -d | grep disk | cut -d' ' -f1)"

    echo "Disks available to install to:"
    lsblk -d | grep disk | awk '{print $1" "$4}'

    echo " "

    installDisk="x"

    until echo "$availableDisks" | grep -q "$installDisk" && [ -b /dev/$installDisk ] ; do
        read -p "Please type a selection from this list to install to: " installDisk
        installDisk="${installDisk// /}"
    done

    echo "Selected disk /dev/${installDisk}"

    echo " "

    diskinfo="$(smartctl -a /dev/${installDisk})"

    echo "$diskinfo" | grep Model
    echo "$diskinfo" | grep Capacity
    echo "$diskinfo" | grep Rotation
    echo "$diskinfo" | grep "Version is:"
    echo "$diskinfo" | grep "Version:"
    echo "$diskinfo" | grep overall-health
    echo " "

    echo "REALLY INSTALL TO THIS DISK? THIS WILL OVERWRITE ALL DATA."
    confirm=" "
    read -p "Type YES in all capital letters to continue: " confirm
    echo " "

    if [ ! $confirm = "YES" ]; then
        echo "Aborting."
        exit 0
    fi

    if [ "$INSTALL_TYPE" == 1 ]; then
        echo "Would you like to write random data to disk? This will improve encryption strength, but may take time depending on disk speed. If you have done this step before repeating it is likely unecessary."
        echo " "
        willWriteRandom=" "
        until [ "$willWriteRandom" == "Y" ] || [ "$willWriteRandom" == "N" ]; do
            read -p "(Y,N): " willWriteRandom
        done
    fi

    IS_HDD="$(cat /sys/block/$installDisk/queue/rotational)"

    echo "Beginning installation..."

    if [ "$willWriteRandom" == "Y" ]; then
        dd if=/dev/urandom of=/dev/$installDisk bs=4M status=progress
    else
        dd if=/dev/zero of=/dev/$installDisk bs=4M count=1
    fi

    fdisk /dev/$installDisk <<EEOF
g
n


+128M
t
1
n


+1G
n



w
EEOF

    sleep 0.5

    EFI_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "0" '.blockdevices[0].children[$part].name')"
    BOOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "1" '.blockdevices[0].children[$part].name')"
    ROOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "2" '.blockdevices[0].children[$part].name')"

    dd if=/dev/zero of=/dev/$EFI_PART bs=4M count=1
    dd if=/dev/zero of=/dev/$BOOT_PART bs=4M count=1
    dd if=/dev/zero of=/dev/$ROOT_PART bs=4M count=1

    sleep 0.5

    mkfs.vfat -F 32 /dev/$EFI_PART
    mkfs.ext4 /dev/$BOOT_PART
    

    CRYPT_UUID=""
    ROOT_UUID=""

    if [ "$INSTALL_TYPE" == 1 ]; then
        until cryptsetup luksFormat /dev/$ROOT_PART; do
            echo "Try again"
        done
        until cryptsetup open /dev/$ROOT_PART "$ROOT_PART"_crypt; do
            echo "Try again"
        done

        CRYPT_NAME="$ROOT_PART"_crypt;
        CRYPT_UUID="$(lsblk -no UUID /dev/$ROOT_PART)"
        mkfs.btrfs /dev/mapper/"$ROOT_PART"_crypt;
        sleep 0.5
        ROOT_UUID="$(lsblk -no UUID /dev/mapper/"$ROOT_PART"_crypt)"
    else
        mkfs.btrfs /dev/$ROOT_PART
        sleep 0.5
        ROOT_UUID="$(lsblk -no UUID /dev/$ROOT_PART)"
    fi

    EFI_UUID="$(lsblk -no UUID /dev/$EFI_PART)"
    BOOT_UUID="$(lsblk -no UUID /dev/$BOOT_PART)"

    mkdir -p /target
    echo "$ROOT_UUID"
    mount /dev/disk/by-uuid/$ROOT_UUID /target

    btrfs subvol create /target/@
    btrfs subvol create /target/@home
    btrfs subvol create /target/@var-log
    umount /target

    if [ "$IS_HDD" == 0 ]; then
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async
        mkdir -p /target/home
        mkdir -p /target/var/log
        mkdir -p /target/etc
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async
        mount /dev/disk/by-uuid/$ROOT_UUID /target/var/log -o subvol=/@var-log,space_cache=v2,ssd,compress=zstd:1,discard=async

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /var/log btrfs subvol=/@var-log,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
    else
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,compress=zstd:3,autodefrag
        mkdir -p /target/home
        mkdir -p /target/var/log
        mkdir -p /target/etc
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag
        mount /dev/disk/by-uuid/$ROOT_UUID /target/var/log -o subvol=/@var-log,space_cache=v2,compress=zstd:3,autodefrag

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /var/log btrfs subvol=/@var-log,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
    fi

    echo "" >> /target/etc/fstab

    echo "tmpfs /tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab
    echo "tmpfs /var/tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab
    echo "tmpfs /var/cache tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab

    mkdir -p /target/boot
    mount /dev/disk/by-uuid/$BOOT_UUID /target/boot
    mkdir -p /target/boot/efi
    mount /dev/disk/by-uuid/$EFI_UUID /target/boot/efi

    echo "" >> /target/etc/fstab
    echo "UUID=$BOOT_UUID /boot ext4 nofail 0 2" >> /target/etc/fstab
    echo "UUID=$EFI_UUID /boot/efi vfat nofail 0 1" >> /target/etc/fstab

    if [ "$INSTALL_TYPE" == 1 ]; then
        touch /target/etc/crypttab
        crpytline="$CRYPT_NAME UUID=$CRYPT_UUID none luks"
        if [ "$IS_HDD" == 0 ]; then
            cryptline="$CRYPT_NAME UUID=$CRYPT_UUID none luks,discard" >> /target/etc/crypttab
        fi

        echo $cryptline | tr -d '\n'  >> /target/etc/crypttab
    fi

    mkdir -p /target/boot
fi

cd /target
mkdir /target/_install

# Make dummy files
mkdir -p /target/etc/apt
mkdir -p /target/etc/default
touch /target/etc/apt/sources.list
touch /target/etc/default/keyboard

# Download the latest debian system image
wget https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-nocloud-amd64-daily.raw
losetup -P /dev/loop99 debian-13-nocloud-amd64-daily.raw
sleep 1
mount /dev/loop99p1 /target/_install

# Extract image to the new drive
rsync -auxv --ignore-existing --exclude 'lost+found' /target/_install/* /target/

# Remove temporary files
umount _install/
losetup -D /dev/loop99
rmdir _install/
rm debian-13-nocloud-amd64-daily.raw

# Adding necessary cfgs
sourcescfg="# Thebian installer sources list

deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security trixie-security main contrib non-free  non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
"
echo "$sourcescfg" >> /target/etc/apt/sources.list

rm /target/etc/resolv.conf
touch /target/etc/resolv.conf

gateway="$(ip r | awk '/^def/{print $3}')"

echo "nameserver $gateway" >> /target/etc/resolv.conf
echo "nameserver 1.1.1.1" >> /target/etc/resolv.conf
echo "nameserver 8.8.8.8" >> /target/etc/resolv.conf

resolvcfg="            nameservers:
                addresses:
                  - 1.1.1.1
                  - 8.8.8.8"

echo "$resolvcfg" >> /target/etc/netplan/90-default.yaml

keyboardcfg="# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
"
echo "$keyboardcfg" >> /target/etc/default/keyboard

# Chroot into the new installation
for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do mount --bind $i /target$i; done
chroot /target /bin/bash << EOT
export PS1="(chroot) ${PS1}"

# Remove files we're replacing later
rm -r /etc/apt/sources.list.d/*
rm -rf /etc/default/grub.d/
rm -rf /boot/grub/*

# updating apt...
dpkg --add-architecture i386
apt update
apt upgrade -yy

apt purge "*cloud*" -yy

# removing all old grub (doesnt play nice with encryption)
grubp1="$(apt-mark showmanual | grep grub)"
grubp2="$(apt-mark showauto | grep grub)"
dpkg -P --force-all $grubp1
dpkg -P --force-all $grubp2

apt install grub-efi-amd64 -yy
apt --fix-broken install -yy

apt install locales util-linux-extra -yy

apt autoremove -yy

# make user
useradd -m -s /bin/bash "$USER_NAME"
usermod -aG sudo "$USER_NAME"

# adding data we specified
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
echo "$HOST_NAME" > /etc/hostname
hwclock --systohc

# adding locale
# echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
# locale-gen

update-locale "LANG=en_US.UTF-8"
locale-gen --purge "en_US.UTF-8"
dpkg-reconfigure --frontend noninteractive locales
dpkg-reconfigure --frontend noninteractive keyboard-configuration

# installing packages
apt install ark bluez btrfs-progs gh git fonts-recommended fonts-ubuntu flatpak gamemode gnome-software ufw i3 kate kcalc fastfetch nitrogen nano sudo cryptsetup pavucontrol pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse plymouth plymouth-themes qdirstat virt-manager redshift-gtk rxvt-unicode timeshift thunar thunar-archive-plugin gvfs-backends ttf-mscorefonts-installer vlc x11-xserver-utils xdg-desktop-portal xserver-xorg-core nitrogen xclip playerctl xdotool pulseaudio-utils network-manager-gnome ibus lightdm tasksel curl firmware-misc-nonfree wget systemsettings systemd-zram-generator lxappearance initramfs-tools sox libsox-fmt-all lshw -yy

if lshw -class network | grep -q "wireless"; then
    apt install firmware-iwlwifi -yy
fi

systemctl disable NetworkManager-wait-online.service 
systemctl disable systemd-networkd-wait-online.service

if [ "$INSTALL_TYPE" != 2 ]; then
    apt install cryptsetup cryptsetup-bin cryptsetup-initramfs -yy
fi

# Downloading configs
wget https://github.com/thenimas/thebian-installer/raw/main/configs/grub -O /etc/default/grub
wget https://github.com/thenimas/thebian-installer/raw/main/configs/zram-generator.conf -O /etc/default/zram-generator.conf

wget https://raw.githubusercontent.com/thenimas/thebian-installer/main/assets/grub-full.png -O /boot/grub/grub-full.png
wget https://raw.githubusercontent.com/thenimas/thebian-installer/main/assets/grub-wide.png -O /boot/grub/grub-wide.png

systemctl daemon-reload
systemctl start /dev/zram0

wget https://github.com/thenimas/thebian-installer/raw/main/user.tar -O user.tar
tar -xf user.tar
rsync -a ./user/* /home/"$USER_NAME"/
rsync -a ./user/.* /home/"$USER_NAME"/
rm -r user
rm user.tar

chown "$USER_NAME":"$USER_NAME" /home/"$USER_NAME" -R

# setup grub

grub-install --target=x86_64-efi --removable
update-grub2
update-initramfs -u -k all

# disable root account
passwd -d root
passwd -l root

# expire users password (so they'll be prompted to make one on login)
passwd -d "$USER_NAME"
passwd -e "$USER_NAME"

# extra non-repository packages

wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor | dd of=/usr/share/keyrings/vscodium-archive-keyring.gpg
echo 'deb [ arch=amd64 signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg ] https://download.vscodium.com/debs vscodium main' | sudo tee /etc/apt/sources.list.d/vscodium.list

sudo mkdir -p /etc/apt/keyrings
curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list

apt update
apt install syncthing -yy
apt install codium -yy

# add firewall rules
ufw default deny incoming
ufw default allow outgoing
ufw allow 80
ufw allow 443
ufw allow syncthing
ufw enable

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

apt autoremove -yy

EOT

cd ~/

for i in /dev/pts /dev /proc /sys/firmware/efi/efivars /sys /run /boot/efi /boot /home /var/log / ; do 
    umount /target$i
done

if [ "$INSTALL_TYPE" == 1 ]; then
    cryptsetup close /dev/mapper/$CRYPT_NAME
fi

echo ""
echo "Installation complete! Your system is ready to reboot."
exit 0
