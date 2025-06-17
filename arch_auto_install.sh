#!/bin/bash
# uncomment to view debugging information 
set -xeuo pipefail

# check if we're root
if [[ "$UID" -ne 0 ]]; then
    echo "This script needs to be run as root!" >&2
    exit 3
fi

# config options
TARGET="/dev/nvme0n1"
LOCALE="en_US.UTF-8"
KEYMAP="us"
TIMEZONE="Europe/Amsterdam"
HOSTNAME="arch"
USERNAME="rroethof"

# SHA512 hash of password. To generate, run 'mkpasswd -m sha-512' (install `whois` package), don't forget to prefix any $ symbols with \
# the entry below is the hash of 'password'
USER_PASSWORD="\$6\$/VBa6GuBiFiBmi6Q\$yNALrCViVtDDNjyGBsDG7IbnNR0Y/Tda5Uz8ToyxXXpw86XuCVAlhXlIvzy1M8O.DWFB6TRCia0hMuAJiXOZy/"
ROOT_MNT="/mnt"

# to fully automate the setup, change BAD_IDEA=no to yes, and enter a cleartext password for the disk encryption 
BAD_IDEA="no"
CRYPT_PASSWORD="changeme"

# packages to pacstrap
PACSTRAP_PACKAGES=(
        amd-ucode
        base
        base-devel
        btrfs-progs
        cryptsetup
        dosfstools
        efibootmgr
        grub
        grub-btrfs
        linux
        linux-firmware
        networkmanager
        sbctl
        sudo
        util-linux
)
PACMAN_PACKAGES=(
        alacritty
        alsa-utils
        amdgpu_top
        asciiquarium
        bash-completion
        bash-language-server
        bat
        bluez
        bluez-utils
        bluez-deprecated-tools
        pavucontrol
        btop
        cmatrix
        dive
        debugedit
        fakeroot
        fastfetch
        firewalld
        fzf
        git
        github-cli
        git-filter-repo
        jq
        kdeconnect
        keyd
        man-db
        man-pages
        mtools
        neovim
        noto-fonts-emoji
        openssh
        pavucontrol
        plocate
        pipewire
        pipewire-jack
        pipewire-pulse
        python-cookiecutter
        speedtest-cli
        starship
        stow
        tldr
        translate-shell
        tree
        ttf-jetbrains-mono-nerd
        ttf-firacode-nerd
        yq
        zsh
        )    
### Desktop packages #####
HYPRLAND_PACKAGES=(
        hyprpolkitagent
        kwalletmanager
        kwallet-pam
        waybar
)

GUI_PACKAGES=("${HYPRLAND_PACKAGES[@]}" # Assigning Hyprland packages
        sddm
        nm-connection-editor
        )

# set locale, timezone, NTP
loadkeys "${KEYMAP}"
timedatectl set-timezone "${TIMEZONE}"
timedatectl set-ntp true

echo "Creating partitions..."
sgdisk -Z "${TARGET}"
# https://wiki.archlinux.org/title/GPT_fdisk#Partition_type
# ef00: EFI System
# 8309: Linux LUKS
sgdisk \
    -n1:0:+1G -t1:ef00 -c1:EFI \
    -N2       -t2:8309 -c2:linux \
    "${TARGET}"
sleep 2
echo
# reload partition table
partprobe -s "${TARGET}"
sleep 2
echo

echo "Encrypting root partition..."
# if BAD_IDEA=yes, then pipe cryptpass and carry on, if not, prompt for it
if [[ "${BAD_IDEA}" == "yes" ]]; then
    echo -n "${CRYPT_PASSWORD}" | cryptsetup luksFormat --type luks2 "/dev/disk/by-partlabel/linux" -
    echo -n "${CRYPT_PASSWORD}" | cryptsetup luksOpen "/dev/disk/by-partlabel/linux" root -
else
    cryptsetup luksFormat --type luks2 "/dev/disk/by-partlabel/linux"
    cryptsetup luksOpen "/dev/disk/by-partlabel/linux" root
fi
echo

echo "Making File Systems..."
# create file systems
mkfs.vfat -F32 -n EFI "/dev/disk/by-partlabel/EFI"
mkfs.btrfs -f -L linux /dev/mapper/root
# mount the root, and create + mount the EFI directory
echo "Mounting File Systems..."
mount "/dev/mapper/root" "${ROOT_MNT}"
mkdir "${ROOT_MNT}/efi" -p
mount -t vfat "/dev/disk/by-partlabel/EFI" "${ROOT_MNT}/efi"
echo
echo "Create BTRFS subvolumes..."
cd "${ROOT_MNT}"
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create --parents @var/cache
btrfs subvolume create --parents @var/lib/libvirt/images
btrfs subvolume create --parents @var/log
btrfs subvolume create --parents @var/log/audit
btrfs subvolume create --parents @var/spool
btrfs subvolume create --parents @var/tmp
cd -
echo

# mount /
#mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/nvme0n1p2 /mnt

# mount /efi
#mount /dev/nvme0n1p1 /mnt/efi

# start a shell into the system
#arch-chroot /mnt

#grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --bootloader-id=arch

# inspect filesystem changes
lsblk
echo
blkid
echo

# update pacman mirrors and then pacstrap base install
echo "Pacstrapping..."
reflector --country NL --age 24 --protocol https --sort rate --save "/etc/pacman.d/mirrorlist"
pacstrap -K "${ROOT_MNT}" "${PACSTRAP_PACKAGES[@]}" 
echo

# generate filesystem table
#genfstab -U -p "${ROOT_MNT}" >> /mnt/etc/fstab
cat /mnt/etc/fstab
echo

echo "Setting up environment..."
# set up locale/env: add our locale to locale.gen
sed -i -e "/^#"${LOCALE}"/s/^#//" "${ROOT_MNT}/etc/locale.gen"
# remove any existing config files that may have been pacstrapped, systemd-firstboot will then regenerate them
rm -f "${ROOT_MNT}"/etc/{machine-id,localtime,hostname,shadow,locale.conf}
systemd-firstboot \
    --root "${ROOT_MNT}" \
    --keymap="${KEYMAP}" \
    --locale="${LOCALE}" \
    --locale-messages="${LOCALE}" \
    --timezone="${TIMEZONE}" \
    --hostname="${HOSTNAME}" \
    --setup-machine-id \
    --welcome=false
arch-chroot "${ROOT_MNT}" locale-gen
echo

echo "Configuring for first boot..."
# add the local user
arch-chroot "${ROOT_MNT}" useradd -G wheel -m -p "${USER_PASSWORD}" "${USERNAME}" 
# uncomment the wheel group in the sudoers file
sed -i -e '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' "${ROOT_MNT}/etc/sudoers"
# create a basic kernel cmdline, we're using DPS so we don't need to have anything here really,
# but if the file doesn't exist, mkinitcpio will complain
echo "quiet rw" > "${ROOT_MNT}/etc/kernel/cmdline"
# change the HOOKS in mkinitcpio.conf to use systemd hooks
sed -i \
    -e 's/base udev/base systemd/g' \
    -e 's/keymap consolefont/sd-vconsole sd-encrypt/g' \
    "${ROOT_MNT}/etc/mkinitcpio.conf"
# change the preset file to generate a Unified Kernel Image instead of an initram disk + kernel
sed -i \
    -e '/^#ALL_config/s/^#//' \
    -e '/^#default_uki/s/^#//' \
    -e '/^#default_options/s/^#//' \
    -e 's/default_image=/#default_image=/g' \
    -e "s/PRESETS=('default' 'fallback')/PRESETS=('default')/g" \
    "${ROOT_MNT}/etc/mkinitcpio.d/linux.preset"
echo

# read the UKI setting and create the folder structure otherwise mkinitcpio will crash
    default_uki_line=$(grep '^default_uki=' "${ROOT_MNT}/etc/mkinitcpio.d/linux.preset")
    if [[ -n "$default_uki_line" ]]; then
        default_uki_path=$(echo "$default_uki_line" | sed -e 's/default_uki=//' -e 's/"//g')
        arch-chroot "${ROOT_MNT}" mkdir -p "$(dirname "${default_uki_path}")"
    else
        echo "WARNING: default_uki path not found in linux.preset. UKI creation might fail." >&2
        default_uki_path="" # Voorkom fouten later als de variabele niet gezet is
    fi
echo

echo "Customize pacman.conf..."
sed -i \
    -e '/#\[multilib\]/,+1s/^#//' \
    -e '/^#Color/s/^#//' \
    -e '/^#CheckSpace/s/^#//' \
    -e '/^#ParallelDownloads.*/s/^#//' \
    -e '/^ParallelDownloads.*/c\ParallelDownloads = 10' \
    -e '/^#VerbosePkgLists/s/^#//' \
    "${ROOT_MNT}/etc/pacman.conf"
echo
# initialize pacman keys and populate them with the Arch Linux keyring
echo "Adding pacman keys..."
arch-chroot "${ROOT_MNT}" pacman-key --init
echo "Populating pacman keys..."
arch-chroot "${ROOT_MNT}" pacman-key --populate archlinux

echo "Installing base packages..."
arch-chroot "${ROOT_MNT}" pacman -Sy "${PACMAN_PACKAGES[@]}" --noconfirm --quiet
echo

echo "Installing GUI..."
arch-chroot "${ROOT_MNT}" pacman -Sy "${GUI_PACKAGES[@]}" --noconfirm --quiet
echo

# enable the services we will need on start up
echo "Enabling services..."
systemctl --root "${ROOT_MNT}" enable systemd-resolved systemd-timesyncd NetworkManager sddm
# mask systemd-networkd as we will use NetworkManager instead
systemctl --root "${ROOT_MNT}" mask systemd-networkd
echo

# regenerate the ramdisk, this will create our UKI
echo "Generating UKI and installing Boot Loader..."
arch-chroot "${ROOT_MNT}" mkinitcpio --preset linux
echo

echo "GRUB setup..."
#arch-chroot "${ROOT_MNT}" rm -rf /efi/EFI/Linux
# enable GRUB cryptodisk
arch-chroot "${ROOT_MNT}" sed -i \
    -e 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/g' \
    /etc/default/grub
echo "Move grub/ from /efi"
arch-chroot "${ROOT_MNT}" ls -lah /efi
# remove grub from /efi
arch-chroot "${ROOT_MNT}" rm -rf /efi/grub
# check the arch boot-loader folder is missing from /efi/EFI
arch-chroot "${ROOT_MNT}" ls -lah /efi/EFI
# create grub
arch-chroot "${ROOT_MNT}" grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --bootloader-id=arch
# check the arch boot-loader folder is now present in /efi/EFI
arch-chroot "${ROOT_MNT}" ls -lah /efi/EFI
# check the grubx64.efi boot-loader's been created
arch-chroot "${ROOT_MNT}" ls -lah /efi/EFI/arch
# check the grub/ folder is now present in /boot
arch-chroot "${ROOT_MNT}" ls -lah /boot
# check /boot/grub contains fonts/, grub.cfg, grubenv, locale/, themes/, x86_64-efi/
arch-chroot "${ROOT_MNT}" ls -lah /boot/grub
# if /boot/grub/grub.cfg is missing, create it and check again
arch-chroot "${ROOT_MNT}" grub-mkconfig --output /boot/grub/grub.cfg
arch-chroot "${ROOT_MNT}" ls -lah /boot/grub
# check the boot entry for Arch Linux has been created and its index is the first in the boot order
arch-chroot "${ROOT_MNT}" efibootmgr
echo

echo "Setting up Secure Boot..."
if [[ "$(efivar --print-decimal --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode)" -eq 1 ]]; then
    arch-chroot "${ROOT_MNT}" sbctl create-keys
    arch-chroot "${ROOT_MNT}" sbctl enroll-keys --microsoft
    arch-chroot "${ROOT_MNT}" sbctl sign --save /efi/EFI/arch/grubx64.efi
    if [[ -n "$default_uki_path" ]]; then
        arch-chroot "${ROOT_MNT}" sbctl sign --save "${default_uki_path}"
    fi
else
    echo "Not in Secure Boot setup mode. Skipping..."
fi
echo

echo "Enable services..."
arch-chroot "${ROOT_MNT}" systemctl enable bluetooth keyd
echo

echo "YAY install..."
# Run git clone and makepkg as the created user in a subshell to handle paths correctly
arch-chroot "${ROOT_MNT}" sudo -u "${USERNAME}" bash -c '
    mkdir -p "/home/'"${USERNAME}"'/build"
    git clone https://aur.archlinux.org/yay-git.git "/home/'"${USERNAME}"'/build/yay-git"
    cd "/home/'"${USERNAME}"'/build/yay-git"
    makepkg -si --noconfirm
'
# Clean up the cloned directory
arch-chroot "${ROOT_MNT}" rm -rf "/home/${USERNAME}/build/yay-git"
echo

echo "YAY update and setup packages..."
arch-chroot "${ROOT_MNT}" sudo -u "${USERNAME}" yay -Syu --noconfirm --norebuild --answerdiff=None --answeredit=None
arch-chroot "${ROOT_MNT}" sudo -u "${USERNAME}" yay -S --noconfirm --norebuild --answerdiff=None --answeredit=None oh-my-zsh-git
echo

echo "ZSH set as default..."
arch-chroot "${ROOT_MNT}" chsh --list-shells
arch-chroot "${ROOT_MNT}" chsh --shell /usr/bin/zsh "${USERNAME}"
echo

# lock the root account
arch-chroot "${ROOT_MNT}" usermod -L root
echo

# ZRAM / Swap setup
# ...

# Voeg dit toe vóór de "Install complete" boodschap in je script:
arch-chroot "${ROOT_MNT}" sudo -u "${USERNAME}" bash -c '
    sh <(curl -L https://raw.githubusercontent.com/JaKooLit/Arch-Hyprland/main/auto-install.sh)
'

# Pas je "Install complete" boodschap aan om de instructie op te nemen:
echo "--------------------------------------------------------------------------"
echo "- Install complete."
echo "- IMPORTANT: To complete the Hyprland customization by JaKooLit,"
echo "- after rebooting and logging in as '${USERNAME}', please open a terminal and run:"
echo "    sh ~/${JAKOOLIT_SCRIPT_NAME}"
echo "- Please reboot now."
echo "--------------------------------------------------------------------------"


echo "-----------------------------------"
echo "- Install complete. Please reboot -"
echo "-----------------------------------"
sleep 10
sync
echo
# reboot