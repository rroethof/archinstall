#!/bin/bash
set -xeuo pipefail

# =========================================
# CONFIGURATIE
# =========================================
TARGET="/dev/nvme0n1"
LOCALE="en_US.UTF-8"
KEYMAP="us"
TIMEZONE="Europe/Amsterdam"
HOSTNAME="arch"
USERNAME="rroethof"
USER_PASSWORD="\$6\$/VBa6GuBiFiBmi6Q\$yNALrCViVtDDNjyGBsDG7IbnNR0Y/Tda5Uz8ToyxXXpw86XuCVAlhXlIvzy1M8O.DWFB6TRCia0hMuAJiXOZy/"
ROOT_MNT="/mnt"
BAD_IDEA="no"
CRYPT_PASSWORD="changeme"

PACSTRAP_PACKAGES=(amd-ucode base base-devel btrfs-progs cryptsetup dosfstools efibootmgr grub grub-btrfs linux linux-firmware networkmanager sbctl sudo util-linux)
PACMAN_PACKAGES=(alacritty alsa-utils amdgpu_top asciiquarium bash-completion bash-language-server bat bluez bluez-utils bluez-deprecated-tools pavucontrol btop cmatrix dive debugedit fakeroot fastfetch firewalld fzf git github-cli git-filter-repo jq kdeconnect keyd man-db man-pages mtools neovim noto-fonts-emoji openssh plocate pipewire pipewire-jack pipewire-pulse python-cookiecutter speedtest-cli starship stow tldr translate-shell tree ttf-jetbrains-mono-nerd ttf-firacode-nerd yq zsh zram-generator)
HYPRLAND_PACKAGES=(hyprpolkitagent kwalletmanager kwallet-pam waybar)
GUI_PACKAGES=("${HYPRLAND_PACKAGES[@]}" sddm nm-connection-editor)

# =========================================
# CHECK ROOT
# =========================================
if [[ "$UID" -ne 0 ]]; then
    echo "Dit script moet als root worden uitgevoerd!" >&2
    exit 3
fi

# =========================================
# BASIS SYSTEEM INSTELLINGEN
# =========================================
loadkeys "${KEYMAP}"
timedatectl set-timezone "${TIMEZONE}"
timedatectl set-ntp true

# =========================================
# PARTITIES EN ENCRYPTIE
# =========================================
echo "Partitioneren van $TARGET..."
sgdisk -Z "$TARGET"
sgdisk -n1:0:+1G -t1:ef00 -c1:EFI -N2 -t2:8309 -c2:linux "$TARGET"
partprobe -s "$TARGET"
sleep 2

echo "Encrypt root partition..."
if [[ "${BAD_IDEA}" == "yes" ]]; then
    echo -n "${CRYPT_PASSWORD}" | cryptsetup luksFormat --type luks2 "/dev/disk/by-partlabel/linux" -
    echo -n "${CRYPT_PASSWORD}" | cryptsetup luksOpen "/dev/disk/by-partlabel/linux" root -
else
    cryptsetup luksFormat --type luks2 "/dev/disk/by-partlabel/linux"
    cryptsetup luksOpen "/dev/disk/by-partlabel/linux" root
fi

# =========================================
# FILESYSTEMS EN BTRFS SUBVOLUMES
# =========================================
mkfs.vfat -F32 -n EFI "/dev/disk/by-partlabel/EFI"
mkfs.btrfs -f -L linux /dev/mapper/root

mount "/dev/mapper/root" "$ROOT_MNT"
cd "$ROOT_MNT"
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create --parents @var/cache
btrfs subvolume create --parents @var/lib/libvirt/images
btrfs subvolume create --parents @var/log
btrfs subvolume create --parents @var/log/audit
btrfs subvolume create --parents @var/spool
btrfs subvolume create --parents @var/tmp
cd -

umount "$ROOT_MNT"
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/root "$ROOT_MNT"
mkdir -p "$ROOT_MNT/home" "$ROOT_MNT/var" "$ROOT_MNT/efi"
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/root "$ROOT_MNT/home"
mount -t vfat "/dev/disk/by-partlabel/EFI" "$ROOT_MNT/efi"

# =========================================
# PACSTRAP
# =========================================
arch-chroot "$ROOT_MNT" reflector --country NL --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
pacstrap -K "$ROOT_MNT" "${PACSTRAP_PACKAGES[@]}"

# =========================================
# FSTAB
# =========================================
genfstab -U -p "$ROOT_MNT" >> "$ROOT_MNT/etc/fstab"

# =========================================
# LOCALE & ENVIRONMENT
# =========================================
sed -i -e "/^#${LOCALE}/s/^#//" "$ROOT_MNT/etc/locale.gen"
rm -f "$ROOT_MNT"/etc/{machine-id,localtime,hostname,shadow,locale.conf}
systemd-firstboot \
    --root "$ROOT_MNT" \
    --keymap="$KEYMAP" \
    --locale="$LOCALE" \
    --locale-messages="$LOCALE" \
    --timezone="$TIMEZONE" \
    --hostname="$HOSTNAME" \
    --setup-machine-id \
    --welcome=false
arch-chroot "$ROOT_MNT" locale-gen

# =========================================
# USER EN SUDO
# =========================================
arch-chroot "$ROOT_MNT" useradd -G wheel -m -p "$USER_PASSWORD" "$USERNAME"
sed -i -e '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' "$ROOT_MNT/etc/sudoers"

# =========================================
# MKINITCPIO & UKI
# =========================================
sed -i -e 's/base udev/base systemd/g' -e 's/keymap consolefont/sd-vconsole sd-encrypt/g' "$ROOT_MNT/etc/mkinitcpio.conf"
default_uki_line=$(grep '^default_uki=' "$ROOT_MNT/etc/mkinitcpio.d/linux.preset" || true)
if [[ -n "$default_uki_line" ]]; then
    default_uki_path=$(echo "$default_uki_line" | sed -e 's/default_uki=//' -e 's/"//g')
    arch-chroot "$ROOT_MNT" mkdir -p "$(dirname "$default_uki_path")"
fi
arch-chroot "$ROOT_MNT" mkinitcpio --preset linux

# =========================================
# GRUB INSTALLATIE
# =========================================
arch-chroot "$ROOT_MNT" sed -i -e 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/g' /etc/default/grub
arch-chroot "$ROOT_MNT" grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --bootloader-id=arch
arch-chroot "$ROOT_MNT" grub-mkconfig -o /boot/grub/grub.cfg

# =========================================
# SECURE BOOT + SIGNING
# =========================================
sb_setup_mode=$(arch-chroot "$ROOT_MNT" bash -c "efivar --print-decimal --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode" || echo 0)
if [[ "$sb_setup_mode" -eq 1 ]]; then
    arch-chroot "$ROOT_MNT" sbctl create-keys
    arch-chroot "$ROOT_MNT" sbctl enroll-keys --microsoft
    arch-chroot "$ROOT_MNT" sbctl sign --save /efi/EFI/arch/grubx64.efi
    if [[ -n "${default_uki_path:-}" ]]; then
        arch-chroot "$ROOT_MNT" sbctl sign --save "$default_uki_path"
    fi
fi

# =========================================
# SERVICES
# =========================================
systemctl --root "$ROOT_MNT" enable systemd-resolved systemd-timesyncd NetworkManager sddm
systemctl --root "$ROOT_MNT" mask systemd-networkd

# =========================================
# EXTRA PAKKETTEN & YAY
# =========================================
arch-chroot "$ROOT_MNT" pacman -Sy --noconfirm "${PACMAN_PACKAGES[@]}"
arch-chroot "$ROOT_MNT" pacman -Sy --noconfirm "${GUI_PACKAGES[@]}"

arch-chroot "$ROOT_MNT" sudo -u "$USERNAME" bash -c '
mkdir -p "/home/'"$USERNAME"'/build"
git clone https://aur.archlinux.org/yay-git.git "/home/'"$USERNAME"'/build/yay-git"
cd "/home/'"$USERNAME"'/build/yay-git"
makepkg -si --noconfirm
'
arch-chroot "$ROOT_MNT" rm -rf "/home/$USERNAME/build"

# =========================================
# ZRAM / Swap setup
# =========================================
echo "Configuring ZRAM swap..."
ZRAM_CONF="$ROOT_MNT/etc/systemd/zram-generator.conf"
cat <<EOF > "$ZRAM_CONF"
[zram0]
zram-size = ram/2
compression-algorithm = lz4
swap-priority = 100
EOF
arch-chroot "$ROOT_MNT" systemctl enable systemd-zram-setup@zram0.service

# =========================================
# POST-INSTALL HYPRLAND SCRIPT
# =========================================
JAKOOLIT_SCRIPT_NAME="run_jakoolit_hyprland_setup.sh"
JAKOOLIT_SCRIPT_URL="https://raw.githubusercontent.com/JaKooLit/Arch-Hyprland/main/auto-install.sh"
USER_HOME_IN_CHROOT="/home/$USERNAME"
arch-chroot "$ROOT_MNT" sudo -u "$USERNAME" curl -L "$JAKOOLIT_SCRIPT_URL" -o "$USER_HOME_IN_CHROOT/$JAKOOLIT_SCRIPT_NAME"
arch-chroot "$ROOT_MNT" sudo -u "$USERNAME" chmod +x "$USER_HOME_IN_CHROOT/$JAKOOLIT_SCRIPT_NAME"

echo "--------------------------------------------------------------------------"
echo "- Install complete."
echo "- After reboot, log in as '$USERNAME' and run:"
echo "    sh ~/$JAKOOLIT_SCRIPT_NAME"
echo "- Reboot now."
echo "--------------------------------------------------------------------------"

sync
sleep 10
