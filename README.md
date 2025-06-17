# Automated Arch Linux Installation Script

This script automates the installation of Arch Linux on a target machine. It includes features like full-disk encryption with LUKS, BTRFS filesystem with subvolumes, GRUB bootloader, Secure Boot setup with `sbctl`, automatic user creation, and installation of a predefined set of packages including a desktop environment.

**Current default GUI:** XFCE (with SDDM)

## ⚠️ Important Warning ⚠️

*   **THIS SCRIPT WILL WIPE THE TARGET DISK (`/dev/sda` by default).**
*   **USE WITH EXTREME CAUTION.** There is no undo.
*   **Review and understand the entire script thoroughly before running it.** You are responsible for what it does to your system.
*   **Backup any important data from the target machine before proceeding.**
*   This script is designed primarily for **UEFI systems**.
*   The script runs with `set -x` enabled, so it will be very verbose. This is for debugging and transparency.

## Features

*   **Disk Preparation:**
    *   Wipes the target disk.
    *   Creates GPT partition table:
        *   1GB EFI System Partition (ESP).
        *   Remaining space for Linux LUKS encrypted partition.
*   **Encryption:**
    *   Encrypts the root partition using LUKS2.
    *   Option for interactive password prompt (default) or fully automated (discouraged, requires cleartext password in script).
*   **Filesystem:**
    *   VFAT (FAT32) for the EFI partition.
    *   BTRFS for the encrypted root partition.
    *   Creates BTRFS subvolumes: `@` (root), `@home`, `@opt`, `@srv`, `@var/cache`, `@var/lib/libvirt/images`, `@var/log`, `@var/spool`, `@var/tmp`.
*   **Base System Installation:**
    *   Uses `reflector` to select fast UK mirrors.
    *   Installs base system and essential packages (`base`, `linux`, `linux-firmware`, `btrfs-progs`, `cryptsetup`, `grub`, etc.) via `pacstrap`.
*   **Bootloader:**
    *   Configures `mkinitcpio` to use `systemd` hooks, `sd-vconsole`, and `sd-encrypt`.
    *   Generates a Unified Kernel Image (UKI).
    *   Installs and configures GRUB for UEFI systems with `GRUB_ENABLE_CRYPTODISK=y`.
*   **Secure Boot:**
    *   If the system is in Secure Boot "Setup Mode", it uses `sbctl` to:
        *   Create new Secure Boot keys.
        *   Enroll the keys (including Microsoft keys).
        *   Sign the GRUB EFI binary and the Unified Kernel Image.
*   **System Configuration:**
    *   Sets locale, keymap, timezone, and hostname.
    *   Creates a non-root user with a pre-hashed password and adds them to the `wheel` group for `sudo` access (NOPASSWD by default).
    *   Configures `pacman.conf` (enables Color, CheckSpace, VerbosePkgLists, ParallelDownloads, multilib repository).
*   **Package Installation:**
    *   Installs a curated list of CLI tools and utilities.
    *   Installs GUI packages (defaulting to XFCE and SDDM).
    *   Installs `yay` as an AUR helper.
    *   Installs `oh-my-zsh-git` via `yay`.
*   **Services:**
    *   Enables essential services: `systemd-resolved`, `systemd-timesyncd`, `NetworkManager`, `sddm`, `bluetooth`, `keyd`.
    *   Masks `systemd-networkd` in favor of `NetworkManager`.
*   **User Environment:**
    *   Sets Zsh as the default shell for the new user.
    *   Locks the `root` account after setup.

## Prerequisites

1.  **Arch Linux Installation Medium:** Boot your target machine using the official Arch Linux ISO.
2.  **Internet Connection:** Required for downloading packages and updating mirror lists.
3.  **Root Privileges:** The script must be run as root.
4.  **`whois` package (optional):** If you need to generate a new password hash for `USER_PASSWORD`, the `mkpasswd` utility (often in the `whois` package) is used. The script provides a default hash for "password".

## Configuration

Before running the script, you **MUST** review and customize the configuration variables at the beginning of `arch_auto_install.sh`:

*   `TARGET="/dev/nvme0n1"`: **CRITICAL!** Set this to your target disk (e.g., `/dev/nvme0n1`, `/dev/sdb`).
*   `LOCALE="en_US.UTF-8"`: System locale.
*   `KEYMAP="us"`: Default console keymap.
*   `TIMEZONE="Europe/Amsterdam"`: System timezone.
*   `HOSTNAME="arch"`: Desired hostname for the system.
*   `USERNAME="user"`: Username for the default user.
*   `USER_PASSWORD="\$6\$..."`: SHA512 hash of the password for `USERNAME`.
    *   To generate a new hash, install `whois` (which provides `mkpasswd`) on a Linux system and run: `mkpasswd -m sha-512`
    *   **Important:** If your generated hash contains `$` symbols, you **must** escape them with a backslash (`\`) in the script (e.g., `\$`).
*   `ROOT_MNT="/mnt"`: Mount point for the installation. Usually no need to change.
*   `BAD_IDEA="no"`: Set to `"yes"` to enable fully automated disk encryption using `CRYPT_PASSWORD`. **This is highly discouraged as it stores your encryption password in plaintext in the script.**
*   `CRYPT_PASSWORD="changeme"`: Plaintext disk encryption password if `BAD_IDEA="yes"`.
*   `PACSTRAP_PACKAGES=(...)`: Array of packages for the base installation.
*   `PACMAN_PACKAGES=(...)`: Array of additional packages to install via `pacman` after `pacstrap`.
*   `GUI_PACKAGES=(...)`: Array of packages for the graphical user interface. You can switch between XFCE (default) and Plasma (commented out) or add your own.

## Usage

1.  **Boot from Arch Linux ISO.**
2.  **Connect to the internet:**
    *   For Wi-Fi: `iwctl device list`, `iwctl station <device> scan`, `iwctl station <device> connect <SSID>`
    *   For Ethernet: Usually connects automatically.
3.  **Download or transfer the script:**
    ```bash
    curl -LO <URL_to_your_script_or_git_repo_raw_file_link>
    # or use scp, or mount a USB drive
    ```
4.  **Make the script executable:**
    ```bash
    chmod +x arch_auto_install.sh
    ```
5.  **Edit the script to configure variables (see Configuration section above).**
    ```bash
    nano arch_auto_install.sh
    # or vim, or other editor available on the ISO
    ```
6.  **Run the script as root:**
    ```bash
    ./arch_auto_install.sh
    ```
7.  Follow any prompts (e.g., for the LUKS encryption password if `BAD_IDEA="no"`).
8.  The script will perform the installation. Once it completes, it will display a message and wait for 10 seconds before syncing. You should then reboot.

## Post-Installation

1.  **Reboot** your system: `reboot`
2.  Remove the installation medium.
3.  Your system should boot into GRUB, then SDDM (if GUI packages were installed).
4.  Log in as the user you configured (`USERNAME`).
5.  Further customize your system (dotfiles, additional software, etc.).

## Regarding `user_configuration.json`

The `user_configuration.json` file present in the repository is an example configuration that can be generated by the official `archinstall` Python-based guided installer. While it might reflect some of the goals or choices similar to those in `arch_auto_install.sh`, this shell script **does not** use `user_configuration.json`. All configuration for `arch_auto_install.sh` is done via the variables defined at the top of the script itself.

## Troubleshooting

*   **Script fails:** Due to `set -e`, the script will exit on any error. The `set -x` output should help identify where it failed.
*   **Boot issues:** Double-check EFI settings in your BIOS/UEFI. Ensure Secure Boot is in Setup Mode or disabled if `sbctl` steps were skipped or failed.
*   **Network issues post-install:** `NetworkManager` is enabled. Use `nmcli` or `nmtui` to manage connections.

## Contributing

Feel free to fork this repository and adapt the script to your needs. If you find bugs or have improvements, pull requests are welcome (though this is primarily a personal script).
