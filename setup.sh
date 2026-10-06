#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root!"
   exit 1
fi

## STAGE 1

echo "Verifying required packages..."
apt update
apt install fdisk bc rsync btrfs-progs tar wget lshw smartmontools cryptsetup debootstrap dosfstools jq playerctl -yy

clear

echo "Welcome to the Thebian installer!"
echo "Please select an installation option:"
echo " "

MODE="$1"
if [[ "$MODE" == "--iso" ]]; then
    echo "1. Install Debian to disk formatted with LUKS encryption (recommended)"
    echo "2. Install Debian without encryption"
else
    echo "1. Install Debian to disk formatted with LUKS encryption (recommended)"
    echo "2. Install Debian without encryption"
    echo "3. Manual install to /target (advanced)"
fi

echo " "

INSTALL_TYPE="0"

CRYPT_NAME=""
crypttab_entry=""

CHASSIS="$(hostnamectl chassis)"
IS_LAPTOP=0
if [[ "$CHASSIS" == "laptop" || "$CHASSIS" == "tablet" ]]; then
    IS_LAPTOP=1
fi

BOOT_TYPE="BIOS"
if [ -d /sys/firmware/efi ]; then
    BOOT_TYPE="UEFI"
fi

if [[ "$MODE" == "--iso" ]]; then
    until [ "$INSTALL_TYPE" -ge 1 ] && [ "$INSTALL_TYPE" -le 2 ]; do
        read -p "(1,2): " INSTALL_TYPE
    done
else
    until [ "$INSTALL_TYPE" -ge 1 ] && [ "$INSTALL_TYPE" -le 3 ]; do
        read -p "(1,2,3): " INSTALL_TYPE
    done
fi

clear

read -p "Enter new username: " USER_NAME

echo " "

read -p "Enter new name for your PC (hostname): " HOST_NAME

clear

encryptPass=""

if [ "$INSTALL_TYPE" == 1 ]; then
    echo "WARNING: If you lose this password, there is 100% NO way to recover it and you will lose access to all of your data."
    echo " "
    while true; do
        read -s -p "Please enter encryption passphrase: " encryptPass
        echo
        read -s -p "Confirm passphrase: " encryptPass2
        echo
        [ "$encryptPass" = "$encryptPass2" ] && break
        echo "Passphrases do not match"
    done
    echo " "
fi 

DESKTOP_TYPE="-1"
until [ "$DESKTOP_TYPE" -ge 1 ] && [ "$DESKTOP_TYPE" -le 7 ]; do
    DESKTOP_TYPE="-1"
    clear
    echo "Select desktop type:"
    echo " "

    echo "1. Headless (no desktop)"
    echo "2. i3"
    echo "3. KDE Plasma"
    echo "4. Cinnamon"
    echo "5. GNOME"
    echo "6. MATE"
    echo "7. LXQT"

    echo " "
    read -p "(1-7): " DESKTOP_TYPE
done

if [ "$INSTALL_TYPE" == 3 ]; then
    if ! cat /proc/mounts | grep -q "/target " ; then
        echo "ERROR: /target not mounted!"
        exit 1
    fi
else
    availableDisks="$(lsblk -d | grep disk | cut -d' ' -f1)"

    confirm=" "
    installDisk="x"
    
    until [ "$confirm" == "YES" ]; do
        clear

        echo "Disks available to install to:"
        lsblk -d | grep disk | awk '{print $1" "$4}'

        echo " "

        installDisk="x"
        until echo "$availableDisks" | grep -q "$installDisk" && [ -b /dev/$installDisk ] ; do
            read -p "Please type a selection from this list to install to: " installDisk
            installDisk="${installDisk// /}"
        done

        clear

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
        
        read -p "Type YES in all capital letters to continue: " confirm
        echo " "
    done

    # if [ "$INSTALL_TYPE" == 1 ]; then
    #     echo "Would you like to write random data to disk? This will improve encryption strength, but may take time depending on disk speed. If you have done this step before repeating it is likely unecessary."
    #     echo " "
    #     willWriteRandom=" "
    #     until [ "$willWriteRandom" == "Y" ] || [ "$willWriteRandom" == "N" ]; do
    #         read -p "(Y,N): " willWriteRandom
    #     done
    # fi

    IS_HDD="$(cat /sys/block/$installDisk/queue/rotational)"

    echo "Beginning installation..."

    dd if=/dev/zero of=/dev/$installDisk bs=4M count=1

    EFI_PART=""
    BOOT_PART=""
    ROOT_PART=""

    if [ "$BOOT_TYPE" == "UEFI" ]; then

        fdisk /dev/$installDisk <<EEOF
g
n


+128M
t
1
n


+1G
t
2
142
n



t
3
23
w
EEOF

        sleep 0.5

        EFI_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "0" '.blockdevices[0].children[$part].name')"
        BOOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "1" '.blockdevices[0].children[$part].name')"
        ROOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "2" '.blockdevices[0].children[$part].name')"

        dd if=/dev/zero of=/dev/$EFI_PART bs=4M count=1

        sleep 0.5
        mkfs.vfat -F 32 /dev/$EFI_PART
    else

        fdisk /dev/$installDisk <<EEOF
o
n
p


+1G
n
p



w
EEOF

    BOOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "0" '.blockdevices[0].children[$part].name')"
    ROOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "1" '.blockdevices[0].children[$part].name')"

    fi

    dd if=/dev/zero of=/dev/$BOOT_PART bs=4M count=1
    dd if=/dev/zero of=/dev/$ROOT_PART bs=4M count=1

    sleep 0.5

    mkfs.ext4 /dev/$BOOT_PART
    

    CRYPT_UUID=""
    ROOT_UUID=""

    if [ "$INSTALL_TYPE" == 1 ]; then
        cryptsetup luksFormat -q --verify-passphrase --type luks2 /dev/$ROOT_PART <<EEOF
$encryptPass
$encryptPass
EEOF

        echo $encryptPass | cryptsetup open /dev/$ROOT_PART "$ROOT_PART"_crypt

        CRYPT_NAME="$ROOT_PART"_crypt;
        CRYPT_UUID="$(lsblk -no UUID /dev/$ROOT_PART)"

        dd if=/dev/zero of=/dev/mapper/"$ROOT_PART"_crypt bs=4M status=progress

        mkfs.btrfs /dev/mapper/"$ROOT_PART"_crypt;
        sleep 0.5
        ROOT_UUID="$(lsblk -no UUID /dev/mapper/"$ROOT_PART"_crypt)"
    else
        mkfs.btrfs /dev/$ROOT_PART
        sleep 0.5
        ROOT_UUID="$(lsblk -no UUID /dev/$ROOT_PART)"
    fi

    sleep 0.5

    EFI_UUID="$(lsblk -no UUID /dev/$EFI_PART)"
    BOOT_UUID="$(lsblk -no UUID /dev/$BOOT_PART)"

    mkdir -p /target
    echo "$ROOT_UUID"
    mount /dev/disk/by-uuid/$ROOT_UUID /target

    btrfs subvol create /target/@
    btrfs subvol create /target/@home
    btrfs subvol create /target/@swap
    umount /target

    if [ "$IS_HDD" == 0 ]; then
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async
        mkdir -p /target/home
        mkdir -p /target/etc
        mkdir -p /target/swap
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async
        mount /dev/disk/by-uuid/$ROOT_UUID /target/swap -o subvol=/@swap,space_cache=v2,ssd,compress=zstd:1,discard=async

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /swap btrfs subvol=/@swap,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
    else
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,compress=zstd:3,autodefrag
        mkdir -p /target/home
        mkdir -p /target/etc
        mkdir -p /target/swap
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag
        mount /dev/disk/by-uuid/$ROOT_UUID /target/swap -o subvol=/@swap,space_cache=v2,compress=zstd:3,autodefrag

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /swap btrfs subvol=/@swap,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
    fi

    echo "" >> /target/etc/fstab

    # setting up swap
    truncate -s 0 /target/swap/swapfile
    chattr +C /target/swap/swapfile
    
    mem="$( grep MemTotal /proc/meminfo | tr -s ' ' | cut -d ' ' -f2 )"
    sw_chunk="$(echo "scale=0 ; sqrt(($mem/1000000) + 1) / 4" | bc)"
    sw_size="$(echo "scale=0 ; $sw_chunk*4 + 4" | bc)"
    sw_size="$(echo "scale=0 ; $sw_size*1024" | bc)"

    dd if=/dev/zero of=/target/swap/swapfile bs=1M count=$sw_size status=progress
    chmod 0600 /target/swap/swapfile
    btrfs balance start -v -dconvert=single /target/swap 
    mkswap /target/swap/swapfile
    swapon /target/swap/swapfile

    echo "tmpfs /tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab
    echo "tmpfs /var/tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab

    echo "" >> /target/etc/fstab

    echo "/swap/swapfile none swap nofail,pri=0 0 0" >> /target/etc/fstab

    mkdir -p /target/boot

    sleep 0.5

    mount /dev/disk/by-uuid/$BOOT_UUID /target/boot
    if [ "$BOOT_TYPE" == "UEFI" ]; then
        mkdir -p /target/boot/efi

        sleep 0.5
        mount /dev/disk/by-uuid/$EFI_UUID /target/boot/efi
    fi

    echo "" >> /target/etc/fstab
    echo "UUID=$BOOT_UUID /boot ext4 nofail 0 2" >> /target/etc/fstab
    if [ "$BOOT_TYPE" == "UEFI" ]; then
        echo "UUID=$EFI_UUID /boot/efi vfat nofail 0 1" >> /target/etc/fstab
    fi

    if [ "$INSTALL_TYPE" == 1 ]; then
        touch /target/etc/crypttab
        crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks"
        if [ "$IS_HDD" == 0 ]; then
            crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks,discard"
        fi
    fi

    mkdir -p /target/boot
fi

## STAGE 2

cd /target

# Make dummy files
mkdir -p /target/etc/apt/sources.list.d/
mkdir -p /target/etc/default
touch /target/etc/default/keyboard

debootstrap --arch=amd64 --include=locales,locales-all,util-linux-extra,linux-image-amd64,dbus,ca-certificates,locales,man-db,sudo,nano,initramfs-tools,keyboard-configuration,zstd,wget,curl,gpg trixie /target http://deb.debian.org/debian

PKGLIST="btrfs-progs gh git ufw fastfetch cryptsetup network-manager tasksel firmware-misc-nonfree accountsservice lshw firmware-linux linux-headers-amd64 apt-listchanges systemd-timesyncd fail2ban apt-listbugs rkhunter lynis avahi-utils netselect-apt"

PKGLIST_NORECS="timeshift"

if [ "$DESKTOP_TYPE" != 1 ]; then
    PKGLIST="${PKGLIST} flatpak gamemode fonts-recommended fonts-inconsolata fonts-cantarell plymouth plymouth-themes qdirstat virt-manager ttf-mscorefonts-installer vlc firefox-esr-"
    PKGLIST_NORECS="${PKGLIST_NORECS} firefox-esr-"
fi
if [ "$DESKTOP_TYPE" == 2 ]; then
    PKGLIST="${PKGLIST} bluez i3 kate pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse rxvt-unicode thunar thunar-archive-plugin gvfs-backends x11-xserver-utils xdg-desktop-portal xserver-xorg-core xclip playerctl xdotool pulseaudio-utils network-manager-gnome ibus lightdm systemsettings sox libsox-fmt-all krb5-locales xwallpaper sddm-"
    PKGLIST_NORECS="${PKGLIST_NORECS} ark gnome-software pavucontrol redshift-gtk lxappearance lxinput maim nodejs default-jdk python3 gdb bc breeze-cursor-theme geeqie libpam-winbind- lxqt-policykit ffmpegthumbnailer gvfs-fuse xsettingsd system-config-printer sddm-"
fi
if [ "$DESKTOP_TYPE" == 3 ]; then
    PKGLIST="${PKGLIST} plasma-discover-backend-flatpak lightdm gimp hunspell-en-ca hyphen-en-us kde-standard kdeaccessibility libreoffice-calc libreoffice-help-en-us libreoffice-impress libreoffice-kf6 libreoffice-plasma libreoffice-writer mythes-en-us orca print-manager"
fi
if [ "$DESKTOP_TYPE" == 4 ]; then
    PKGLIST="${PKGLIST} task-cinnamon-desktop gnome-software-plugin-flatpak"
fi
if [ "$DESKTOP_TYPE" == 5 ]; then
    PKGLIST="${PKGLIST} task-gnome-desktop gnome-software-plugin-flatpak"
fi
if [ "$DESKTOP_TYPE" == 6 ]; then
    PKGLIST="${PKGLIST} task-mate-desktop"
fi
if [ "$DESKTOP_TYPE" == 7 ]; then
    PKGLIST="${PKGLIST} task-lxqt-desktop"
fi

rm /target/etc/apt/sources.list

# Adding necessary cfgs
# set main repository
if [[ "$MODE" != "--iso" ]]; then
    netselect-apt -o /target/etc/apt/sources.list
else
    sourcescfg="# Thebian installer sources list
    Types: deb deb-src
    URIs: http://deb.debian.org/debian/
    Suites: trixie
    Components: main contrib non-free-firmware
    Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

    Types: deb deb-src
    URIs: http://deb.debian.org/debian/
    Suites: trixie-updates
    Components: main contrib non-free-firmware
    Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

    Types: deb deb-src
    URIs: http://security.debian.org/debian-security/
    Suites: trixie-security
    Components: main contrib non-free-firmware
    Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
    "
    echo "$sourcescfg" > /target/etc/apt/sources.list.d/debian.sources
fi

keyboardcfg="# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
"
echo "$keyboardcfg" > /target/etc/default/keyboard

# Chroot into the new installation
for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run /etc/resolv.conf; do mount --bind $i /target$i; done
chroot /target /bin/bash << EOT
export PS1="(chroot) ${PS1}"

sleep 0.5

mount -a

wget https://github.com/thenimas/thebian-installer/raw/chooser/configs/locale.conf -O /etc/locale.conf

# adding locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_CA.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# updating apt...
dpkg --add-architecture i386
apt update
apt upgrade -yy

# apt --fix-broken install -yy

apt autoremove -yy

export LC_CTYPE=en_CA.UTF-8
export LC_ALL=en_CA.UTF-8

setupcon

# adding data we specified
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
echo "$HOST_NAME" > /etc/hostname
hwclock --systohc

# installing packages
apt install $PKGLIST -yy

apt install --no-install-suggests --no-install-recommends $PKGLIST_NORECS -yy

wget https://github.com/thenimas/thebian-installer/raw/chooser/configs/timeshift.json -O /etc/timeshift/timeshift.json
wget https://github.com/thenimas/thebian-installer/raw/chooser/configs/jail.local -O /etc/fail2ban/jail.local

sed -i 's/ROOT_UUID/'"$ROOT_UUID"'/g' /etc/timeshift/timeshift.json
sed -i 's/CRYPT_UUID/'"$CRYPT_UUID"'/g' /etc/timeshift/timeshift.json

if lshw -class network | grep -q "wireless"; then
    apt install firmware-iwlwifi -yy
fi

systemctl disable NetworkManager-wait-online.service 
systemctl disable systemd-networkd-wait-online.service
systemctl mask systemd-networkd-wait-online.service

systemctl enable fail2ban
systemctl enable avahi-daemon

chattr +C /var/lib/libvirt/images
virsh net-autostart default
usermod -aG libvirt "$USER_NAME"

if [ "$INSTALL_TYPE" != 2 ]; then
    apt install cryptsetup cryptsetup-bin cryptsetup-initramfs -yy
    echo "# <target name> <source device> <key file> <options>" > /etc/crypttab
    echo "$crypttab_entry" | tr -d '\n'  >> /etc/crypttab
    echo "" >> /etc/crypttab
fi

systemctl daemon-reload

# setup grub

if [ "$BOOT_TYPE" == "BIOS" ]; then
    apt install grub-pc -yy
    grub-install --target=i386-pc /dev/"$installDisk"
else
    apt install grub-efi-amd64 efibootmgr -yy
    grub-install --target=x86_64-efi
    grub-install --target=x86_64-efi --removable
fi

EOT

chroot /target /bin/bash << EOT
update-initramfs -u -k all

if [ "$DESKTOP_TYPE" != 1 ]; then
    plymouth-set-default-theme -R spinner
fi

mkdir /boot/grub -p

sleep 0.5

wget https://github.com/thenimas/thebian-installer/raw/chooser/configs/grub -O /etc/default/grub

wget https://raw.githubusercontent.com/thenimas/thebian-installer/chooser/assets/grub-full.png -O /boot/grub/grub-full.png
wget https://raw.githubusercontent.com/thenimas/thebian-installer/chooser/assets/grub-wide.png -O /boot/grub/grub-wide.png

EOT

sleep 0.5

chroot /target /bin/bash << EOT

update-grub2

EOT

chroot /target /bin/bash << EOT

# disable root account
passwd -d root
passwd -l root

EOT

if [ "$DESKTOP_TYPE" != 1 ]; then

    chroot /target /bin/bash << EOT

# extra non-repository packages

wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor | dd of=/usr/share/keyrings/vscodium-archive-keyring.gpg
echo "Types: deb
URIs: https://download.vscodium.com/debs/
Suites: vscodium
Components: main
Signed-By: /usr/share/keyrings/vscodium-archive-keyring.gpg
Architectures: amd64
" | tee /etc/apt/sources.list.d/vscodium.sources

mkdir -p /etc/apt/keyrings
curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "Types: deb
URIs: https://apt.syncthing.net/
Suites: syncthing
Components: stable-v2
Signed-By: /etc/apt/keyrings/syncthing-archive-keyring.gpg
" | tee /etc/apt/sources.list.d/syncthing.sources

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

apt autoremove -yy

wget https://github.com/thenimas/thebian-installer/raw/chooser/configs/timeshift-boot -O /etc/cron.d/timeshift-boot
wget https://github.com/thenimas/thebian-installer/raw/chooser/configs/timeshift-hourly -O /etc/cron.d/timeshift-hourly

EOT
fi

## STAGE 3

chroot /target /bin/bash << EOT
# make user
useradd -m -s /bin/bash "$USER_NAME"
usermod -aG sudo "$USER_NAME"

# expire users password (so they'll be prompted to make one on login)
passwd -d "$USER_NAME"
passwd -e "$USER_NAME"

if [ "$DESKTOP_TYPE" == 2 ]; then

    wget https://github.com/thenimas/thebian-installer/raw/chooser/user.tar -O user.tar
    tar -xf user.tar
    rsync -a ./user/* /home/"$USER_NAME"/
    rsync -a ./user/.* /home/"$USER_NAME"/
    rm -r user
    rm user.tar

    runuser "$USER_NAME" -c 'xdg-mime default thunar.desktop inode/directory application/x-gnome-saved-search'
fi

chown "$USER_NAME":"$USER_NAME" /home/"$USER_NAME" -R

if [ "$DESKTOP_TYPE" != 1 ]; then
    runuser "$USER_NAME" -c 'flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo'
    # runuser "$USER_NAME" -c 'flatpak install --user net.waterfox.waterfox -y'
fi
EOT

if [ "$IS_LAPTOP" == 1 ]; then
    sed -i 's/# bindsym XF86MonBrightness/bindsym XF86MonBrightness/g' /target/home/"$USER_NAME"/.config/i3/config
    sed -i 's/# order += "battery all"/order += "battery all"/g' /target/home/"$USER_NAME"/.config/i3/i3status.conf

    chroot /target /bin/bash << EOT
apt install --no-install-suggests --no-install-recommends bluez bluez-tools iw powertop wpasupplicant brightnessctl -yy

usermod -aG video "$USER_NAME"
usermod -aG input "$USER_NAME"

cd /root

EOT

fi

# STAGE 4 (cleanup)

# set main repository
chroot /target /bin/bash << EOT
netselect-apt -o /etc/apt/sources.list
rm /etc/apt/sources.list.d/debian.sources
apt modernize-sources --assume-yes
apt update
EOT

cd ~/

wget https://raw.githubusercontent.com/thenimas/thebian-installer/chooser/assets/finish.mp3
play ~/finish.mp3

echo ""
echo "Installation complete! Your system is ready to reboot."
exit 0
