#!/bin/bash

# Set variables
DISK="/dev/sda"
ROOT_PART="${DISK}1"
BOOT_PART="${DISK}2"
SWAP_PART="${DISK}3"
FILESYSTEM="ext4"
STAGE3_URL="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-$(date +%Y%m%d).tar.xz"

# Partition the disk
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary 1MiB 3MiB
parted -s $DISK mkpart primary 3MiB 1GiB
parted -s $DISK mkpart primary 1GiB 100%

# Format the partitions
mkfs.vfat $BOOT_PART
mkfs.$FILESYSTEM $ROOT_PART
mkswap $SWAP_PART
swapon $SWAP_PART

# Mount the partitions
mount $ROOT_PART /mnt/gentoo
mkdir /mnt/gentoo/boot
mount $BOOT_PART /mnt/gentoo/boot

# Download and extract the stage3 tarball
cd /mnt/gentoo
wget $STAGE3_URL -O stage3-amd64.tar.xz
tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner

# Copy DNS info
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# Mount necessary filesystems
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

# Chroot into the new environment
chroot /mnt/gentoo /bin/bash << 'EOF'
source /etc/profile
export PS1="(chroot) $PS1"

# Set the timezone
echo "UTC" > /etc/timezone
emerge --config sys-libs/timezone-data

# Update the environment
env-update && source /etc/profile && export PS1="(chroot) $PS1"

# Install the base system
emerge-webrsync
emerge --sync
emerge sys-kernel/gentoo-sources
emerge sys-kernel/genkernel
genkernel all

# Configure fstab
cat << FSTAB > /etc/fstab
$ROOT_PART  /       $FILESYSTEM  defaults  0 1
$BOOT_PART  /boot   vfat         defaults  0 2
$SWAP_PART  none    swap         sw        0 0
FSTAB

# Install necessary tools
emerge sys-boot/grub
grub-install $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Set the root password
echo "root:Streamy" | chpasswd

# Exit chroot
exit
EOF

# Unmount filesystems
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -l /mnt/gentoo{/boot,/proc,/sys,}

# Reboot
echo "Installation complete! Rebooting..."
reboot
