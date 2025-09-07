#!/bin/bash

if [ ! -d /target/ ]; then
    echo "Directory /target/ not found. Did you partition properly?"
    echo "Setup exiting."
    exit 1
fi

read -p "Enter username: " newUser

choice="n"
additionalPackages=""

read -p "Enter hostname: " newHostname
echo ""

read -p "Add additonal packages? (y/n): " choice
if [ $choice = "y" ]; then
    read -p "Specify packages: " additonalPackages
fi

echo "Installation is starting..."
echo ""
sleep 1

echo "Checking dpeendencies..."
apt install --no-install-recommends fdisk rsync btrfs-progs neofetch tar

neofetch

echo "tmpfs /tmp tmpfs rw,nodev,nosuid,size=2G 0 0" > /target/etc/fstab
echo "tmpfs /var/tmp tmpfs rw,nodev,nosuid,size=2G 0 0" > /target/etc/fstab
echo "tmpfs /var/cache tmpfs rw,nodev,nosuid,size=2G 0 0" > /target/etc/fstab

cd /target
mkdir /target/_install

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
echo "$sourcescfg" > /target/etc/apt/sources.list

keyboardcfg = "# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
"
echo "$keyboardcfg" > /target/etc/default/keyboard

# Chroot into the new installation
for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do mount --bind $i /target$i; done
chroot /target /bin/bash << EOT
export PS1="(chroot) ${PS1}"

# Remove unneeded files
rm -r /etc/apt/sources.list.d/*

# Adding nameservers
rm /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# make user
useradd -m -s /bin/bash "$newUser"
usermod -aG sudo "$newUser"

# adding data we specified
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
echo "$newHostname" > /etc/hostname
hwclock --systohc

# adding locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen


# updating apt...
dpkg --add-architecture i386
apt update
apt upgrade -yy

apt purge "*cloud*" -yy

# installing packages
apt install ark bluez btrfs-progs gh git fonts-recommended fonts-ubuntu flatpak gamemode gnome-software ufw i3 kate kcalc neofetch nitrogen nano sudo cryptsetup pavucontrol pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse plymouth plymouth-themes qdirstat virt-manager redshift-gtk rxvt-unicode timeshift thunar thunar-archive-plugin gvfs-backends ttf-mscorefonts-installer vlc x11-xserver-utils xdg-desktop-portal xserver-xorg-core nitrogen xclip playerctl xdotool pulseaudio-utils network-manager-gnome ibus lightdm tasksel curl firmware-misc-nonfree wget task-ssh-server systemsettings systemd-zram-generator lxappearance grub-efi-amd64 initramfs-tools sox libsox-fmt-all -yy

apt install "$additionalPackages" -yy

# Downloading configs
wget https://github.com/thenimas/thebian-installer/raw/main/configs/grub -O /etc/default/grub
wget https://github.com/thenimas/thebian-installer/raw/main/configs/zram-generator.conf -O /etc/default/zram-generator.conf

wget https://raw.githubusercontent.com/thenimas/thebian-installer/main/assets/grub-full.png -O /boot/grub/grub-full.png
wget https://raw.githubusercontent.com/thenimas/thebian-installer/main/assets/grub-wide.png -O /boot/grub/grub-wide.png

systemctl daemon-reload
systemctl start /dev/zram0

wget https://github.com/thenimas/thebian-installer/raw/main/user.tar -O user.tar
tar -xf user.tar
rsync -a ./user /home/"$newUser"/
rm -r user
rm user.tar

chown "$newUser":"$newUser" /home/"$newUser" -R

# Add fstab entries
cat /proc/mounts | grep -v nosuid > /etc/fstab

# setup grub
grub-install --target=x86_64-efi --removable
update-grub2
update-initramfs -u

# disable root account
passwd -d root
passwd -l root

# expire users password (so they'll be prompted to make one on login)
passwd -d "$newUser"
passwd -e "$newUser"

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
ufw limit 22/tcp
ufw allow syncthing
ufw enable

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

EOT

echo ""
echo "Installation complete! Your system is ready to reboot."
exit 0
