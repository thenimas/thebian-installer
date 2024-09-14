#!/bin/bash

if [ ! -d /target/ ]; then
    echo "Directory /target/ not found. Did you partition properly?"
    echo "Setup exiting."
    exit 1
fi

read -p "Enter username: " newUser

newPassWord="__PLACEHOLDER__"
confirmPassWord=""

until [ "$newPassWord" == "$confirmPassWord" ]
do
    read -sp "Enter password: " newPassWord
    echo ""
    read -sp "Confirm password: " confirmPassWord
    echo ""
    if [ "$newPassWord" != "$confirmPassWord" ]
    then
        echo "Passwords do not match."
        echo ""
    fi
done

read -p "Enter hostname: " newHostname
echo ""

echo "Installation is starting..."
echo ""

apt install --no-install-recommends fdisk rsync btrfs-progs neofetch -y > /dev/null

neofetch

cd /target
mkdir /target/_install

# Download the latest debian system image
wget https://cloud.debian.org/images/cloud/bookworm/daily/latest/debian-12-nocloud-amd64-daily.raw
losetup -f -P debian-12-nocloud-amd64-daily.raw
sleep 1
mount /dev/loop0p1 /target/_install

# Extract image to the new drive
rsync -auxv --ignore-existing /target/_install/* /target/

# Remove temporary files
umount _install/
losetup -D
rmdir _install/
rm debian-12-nocloud-amd64-daily.raw

# Source.list setup
sourcescfg="# Thebian installer sources list

deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main contrib non-free  non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
"
echo "$sourcescfg" > /target/etc/apt/sources.list

# Chroot into the new installation
for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do mount --bind $i /target$i; done
chroot /target /bin/bash << EOT
export PS1="(chroot) ${PS1}"

# Remove unneeded files
rm -rf lost+found/
rm -r /etc/apt/sources.list.d/*

# make user
useradd -mp "$newPassword" "$newUser"
usermod -aG sudo "$newUser"

# adding data we specified
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
echo "$newHostName" > /etc/hostname
hwclock --systohc

# updating apt...
dpkg --add-architecture i386
apt update
apt upgrade -yy

# installing packages
apt install ark bluez btrfs-progs gh git fonts-recommended fonts-ubuntu flatpak gamemode gnome-software ufw i3 kate kcalc neofetch nitrogen nano cryptsetup pavucontrol pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse plymouth plymouth-themes qdirstat virt-manager redshift-gtk rxvt-unicode timeshift thunar thunar-archive-plugin gvfs-backends ttf-mscorefonts-installer vlc x11-xserver-utils xdg-desktop-portal xserver-xorg-core nitrogen xclip playerctl xdotool pulseaudio-utils network-manager-gnome ibus lightdm tasksel curl firmware-misc-nonfree wget -yy

# Downloading configs
wget https://github.com/thenimas/thebian-installer/raw/main/configs/keyboard -O /etc/default/keyboard
wget https://github.com/thenimas/thebian-installer/raw/main/configs/grub -O /etc/default/grub

mkdir -p /home/"$newUser"/.config/i3
mkdir -p /home/"$newUser"/.config/autostart
wget https://github.com/thenimas/thebian-installer/raw/main/configs/config -O /home/"$newUser"/.config/i3/config
wget https://github.com/thenimas/thebian-installer/raw/main/configs/i3status.conf -O /home/"$newUser"/.config/i3/i3status.conf
wget https://github.com/thenimas/thebian-installer/raw/main/configs/flatpak-update.desktop -O /home/"$newUser"/.config/autostart/flatpak-update.desktop
wget https://raw.githubusercontent.com/thenimas/thebian-installer/main/assets/refsheet_wallpaper.png -O /home/"$newUser"/refsheet_wallpaper.png

# extra non-repository packages

wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor | dd of=/usr/share/keyrings/vscodium-archive-keyring.gpg
echo 'deb [ signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg ] https://download.vscodium.com/debs vscodium main' | sudo tee /etc/apt/sources.list.d/vscodium.list

sudo mkdir -p /etc/apt/keyrings
curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list

apt update
apt install codium syncthing -yy

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install com.github.PintaProject.Pinta com.github.tchx84.Flatseal com.gluonhq.SceneBuilder com.obsproject.Studio com.spotify.Client dev.vencord.Vesktop org.kde.krita org.libreoffice.LibreOffice org.mozilla.Thunderbird org.mozilla.firefox

# setup grub
wget https://raw.githubusercontent.com/thenimas/thebian-installer/main/assets/desktop-grub.png -O /boot/grub/desktop-grub.png
grub-install --target=x86_64-efi --removable
update-grub2
update-initramfs -u -k all

EOT

echo ""
echo "Installation complete! Your system is ready to reboot."
exit 0
