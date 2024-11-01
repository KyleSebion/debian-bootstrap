#!/bin/bash

CHROOT_DIR=/mnt
INSTALL_DEV=/dev/vda

apt update
apt -y install parted dosfstools arch-install-scripts systemd-container efibootmgr mmdebstrap
wipefs -a "$INSTALL_DEV"*
parted "$INSTALL_DEV" mklabel gpt mkpart e fat32 4MiB 1020MiB mkpart r 1021MiB 3068MiB set 1 esp on
udevadm settle
mkfs.fat -F 32 -n e /dev/disk/by-partlabel/e
mkfs.ext4 -L r /dev/disk/by-partlabel/r
mount LABEL=r "$CHROOT_DIR"
mmdebstrap --skip=cleanup/apt,cleanup/reproducible bookworm "$CHROOT_DIR"
mount -m LABEL=e "$CHROOT_DIR"/efi

systemd-nspawn -PD "$CHROOT_DIR" /bin/bash -x << 'CEOF'
export DEBIAN_FRONTEND=noninteractive
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/default_environment_locale select en_US.UTF-8'
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8'
apt -y install locales

sed -i -re '/\slocalhost(\s|$)/s/$/ debian/' /etc/hosts

echo do_symlinks = no > /etc/kernel-img.conf
apt -y install linux-image-amd64

apt -y install systemd-boot
sed -i -re '/options/s/.*/options    root=LABEL=r console=ttyS0/' /efi/loader/entries/*

echo '[Match] Name=enp1s0 [Network] Address=10.10.10.3/24 Gateway=10.10.10.1 DNS=1.1.1.1 DNS=8.8.8.8 [DHCPv4] UseDNS=false [DHCPv6] UseDNS=false' | tr ' ' \\n > /etc/systemd/network/10-enp1s0.network
systemctl enable systemd-networkd

tasksel install standard ssh-server

sed -i -re '/#force_color_prompt=yes/s/^#//' /etc/skel/.bashrc
echo -e 'alias lh=\x27ls -lhA\x27' >> /etc/skel/.bashrc
cp /etc/skel/.bashrc /root/

apt -y install sudo
adduser --disabled-password --comment '' user
adduser user sudo
echo user:live | chpasswd

apt -y install wireless-regdb
CEOF

genfstab -L "$CHROOT_DIR" | grep LABEL=[er] > "$CHROOT_DIR"/etc/fstab
umount -R "$CHROOT_DIR"
efibootmgr -c -d "$INSTALL_DEV" -p 1 -l '\EFI\systemd\systemd-bootx64.efi' -L 'Linux Boot Manager' # kludge because installing systemd-boot in systemd-nspawn doesn't add a boot entry
