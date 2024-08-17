#!/bin/bash

# Exit on any error
set -e

# Set variables
DISK="/dev/sda"
ROOT_PART="${DISK}1"
BOOT_PART="${DISK}2"
SWAP_PART="${DISK}3"
FILESYSTEM="ext4"
STAGE3_URL="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-$(date +%Y%m%d).tar.xz"
MOUNT_DIR="/mnt/gentoo"

# Partition the disk
echo "Partitioning the disk..."
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary 1MiB 3MiB   # Boot partition
parted -s $DISK mkpart primary 3MiB 1GiB   # Root partition
parted -s $DISK mkpart primary 1GiB 100%   # Swap partition

# Format the partitions
echo "Formatting the partitions..."
mkfs.vfat $BOOT_PART
mkfs.$FILESYSTEM $ROOT_PART
mkswap $SWAP_PART
swapon $SWAP_PART

# Mount the partitions
echo "Mounting the partitions..."
mount $ROOT_PART $MOUNT_DIR
mkdir -p $MOUNT_DIR/boot
mount $BOOT_PART $MOUNT_DIR/boot

# Download and extract the stage3 tarball
echo "Downloading and extracting stage3 tarball..."
cd $MOUNT_DIR
wget $STAGE3_URL -O stage3-amd64.tar.xz
tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner

# Copy DNS info
echo "Copying DNS information..."
cp --dereference /etc/resolv.conf $MOUNT_DIR/etc/

# Mount necessary filesystems
echo "Mounting necessary filesystems..."
mount -t proc proc $MOUNT_DIR/proc
mount --rbind /sys $MOUNT_DIR/sys
mount --make-rslave $MOUNT_DIR/sys
mount --rbind /dev $MOUNT_DIR/dev
mount --make-rslave $MOUNT_DIR/dev

# Chroot into the new environment
echo "Chrooting into the new environment..."
chroot $MOUNT_DIR /bin/bash << 'EOF'
source /etc/profile
export PS1="(chroot) $PS1"

# Set the timezone
echo "UTC" > /etc/timezone
emerge --config sys-libs/timezone-data

# Update the environment
env-update && source /etc/profile

# Install the base system
emerge-webrsync
emerge --sync
emerge sys-kernel/gentoo-sources
emerge sys-kernel/genkernel
genkernel all

# Configure fstab
echo "Configuring fstab..."
cat << FSTAB > /etc/fstab
$ROOT_PART  /       $FILESYSTEM  defaults  0 1
$BOOT_PART  /boot   vfat         defaults  0 2
$SWAP_PART  none    swap         sw        0 0
FSTAB

# Install and configure GRUB
echo "Installing and configuring GRUB..."
emerge sys-boot/grub
grub-install $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Set the root password
echo "Setting the root password..."
echo "root:Streamy" | chpasswd

# Exit chroot
exit
EOF

# Unmount filesystems
echo "Unmounting filesystems..."
umount -l $MOUNT_DIR/dev{/shm,/pts}
umount -l $MOUNT_DIR{/boot,/proc,/sys}

# Reboot
echo "Installation complete! Rebooting..."
reboot
