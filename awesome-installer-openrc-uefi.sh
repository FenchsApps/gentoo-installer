#!/bin/bash
set -e

# ======================== User Input ========================
read -p 'Enter the disk to install Gentoo on (e.g., /dev/sda): ' DISK
read -p 'Enter hostname: ' GENTOO_HOSTNAME
read -sp 'Enter root password: ' ROOT_PASSWORD
echo
read -p 'Enter timezone (e.g., Europe/Moscow): ' TIMEZONE
read -p 'Choose kernel package ("gentoo-kernel" or "gentoo-kernel-bin"): ' KERNEL

# Determine partition prefix (NVMe/MMC disks use a "p" suffix)
if [[ "${DISK}" == *"nvme"* ]] || [[ "${DISK}" == *"mmcblk"* ]]; then
    PART="${DISK}p"
else
    PART="${DISK}"
fi

# ======================== Disk Partitioning ========================
# GPT partition layout for UEFI (per Gentoo Handbook):
#   Partition 1: EFI System Partition — 256 MiB, FAT32
#   Partition 2: Swap                 — 4 GiB
#   Partition 3: Root (/)             — remainder of disk, ext4

echo ">>> Creating GPT partition table on ${DISK}..."
wipefs -af "${DISK}"

parted -a optimal "${DISK}" --script -- mklabel gpt
parted -a optimal "${DISK}" --script -- mkpart "EFI"    fat32      1MiB    257MiB
parted -a optimal "${DISK}" --script -- set 1 esp on
parted -a optimal "${DISK}" --script -- mkpart "swap"   linux-swap 257MiB  4353MiB
parted -a optimal "${DISK}" --script -- mkpart "rootfs" ext4       4353MiB 100%

echo ">>> Partitioning complete:"
parted "${DISK}" --script print

# ======================== Formatting ========================
echo ">>> Formatting partitions..."
mkfs.vfat -F 32 "${PART}1"
mkswap "${PART}2"
swapon "${PART}2"
mkfs.ext4 -F "${PART}3"

# ======================== Mounting ========================
mkdir --parents /mnt/gentoo
mount "${PART}3" /mnt/gentoo

# ======================== Stage3 ========================
cd /mnt/gentoo
chronyd -q

echo ">>> Downloading stage3..."
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20260208T163056Z/stage3-amd64-openrc-20260208T163056Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

# ======================== Configuring make.conf (before chroot) ========================
echo 'You need to edit make.conf. See https://wiki.gentoo.org/wiki//etc/portage/make.conf for info.'
read -p 'Press Enter to edit make.conf...'
nano /mnt/gentoo/etc/portage/make.conf

# ======================== Copying DNS Configuration ========================
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# ======================== Mounting Pseudo-Filesystems ========================
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-rslave /mnt/gentoo/run

# ======================== Chroot ========================
# Write variables for use inside the chroot
cat > /mnt/gentoo/tmp/install-vars.sh <<VARS_EOF
PART="$(printf '%q' "${PART}")"
GENTOO_HOSTNAME="$(printf '%q' "${GENTOO_HOSTNAME}")"
ROOT_PASSWORD="$(printf '%q' "${ROOT_PASSWORD}")"
TIMEZONE="$(printf '%q' "${TIMEZONE}")"
KERNEL="$(printf '%q' "${KERNEL}")"
VARS_EOF

# Write the chroot installation script
cat > /mnt/gentoo/tmp/chroot-install.sh <<'CHROOT_EOF'
#!/bin/bash
set -e

source /tmp/install-vars.sh
source /etc/profile
export PS1="(chroot) ${PS1}"

# --- Mount EFI ---
mkdir -p /efi
mount "${PART}1" /efi

# --- Portage Sync ---
emerge-webrsync
mkdir -p /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
emerge --sync --quiet

# --- Profile Selection ---
echo '>>> Select a profile:'
eselect profile list
read -p 'Enter profile number: ' profile
eselect profile set ${profile}

# --- USE Flags ---
echo 'You need to set your USE flags in make.conf. See https://wiki.gentoo.org/wiki//etc/portage/make.conf for info.'
read -p 'Press Enter to edit make.conf...'
nano /etc/portage/make.conf

# --- Update @world ---
emerge --verbose --update --deep --changed-use @world
emerge --depclean

# --- Timezone ---
ln -sf ../usr/share/zoneinfo/${TIMEZONE} /etc/localtime

# --- Locales ---
echo 'You need to enable your locales in /etc/locale.gen. Press Enter to edit.'
read
nano /etc/locale.gen
locale-gen

echo '>>> Select a locale:'
eselect locale list
read -p 'Enter locale number: ' locale
eselect locale set ${locale}

env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

# --- Firmware ---
emerge sys-kernel/linux-firmware
emerge sys-firmware/sof-firmware

# --- Kernel ---
mkdir -p /etc/portage/package.use
echo 'sys-kernel/installkernel dracut' >> /etc/portage/package.use/installkernel
emerge sys-kernel/installkernel

# --- fstab ---
emerge sys-fs/genfstab
genfstab -U / >> /etc/fstab

# --- Install Kernel ---
emerge sys-kernel/${KERNEL}
emerge --depclean

# --- Hostname ---
echo "${GENTOO_HOSTNAME}" > /etc/hostname

# --- Networking ---
emerge net-misc/dhcpcd
rc-update add dhcpcd default

echo 'You should edit /etc/hosts for network information. See https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/System for details.'
read -p 'Press Enter to edit...'
nano /etc/hosts

# --- Root Password ---
echo "root:${ROOT_PASSWORD}" | chpasswd

# --- System Utilities ---
emerge app-admin/sysklogd
rc-update add sysklogd default
emerge net-misc/chrony
rc-update add chronyd default
emerge net-wireless/iw net-wireless/wpa_supplicant

# --- GRUB ---
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
emerge sys-boot/grub
emerge sys-boot/efibootmgr
grub-install --efi-directory=/efi
grub-mkconfig -o /boot/grub/grub.cfg

echo '>>> Chroot installation complete.'
CHROOT_EOF

chmod +x /mnt/gentoo/tmp/chroot-install.sh
chroot /mnt/gentoo /bin/bash /tmp/chroot-install.sh

# ======================== Cleanup and Unmount ========================
rm -f /mnt/gentoo/tmp/install-vars.sh /mnt/gentoo/tmp/chroot-install.sh

umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo

echo '>>> Gentoo has been successfully installed! Press Enter to reboot.'
read
reboot
