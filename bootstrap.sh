#!/bin/bash -x

CHROOT_DIR=/mnt
INSTALL_DEV=/dev/vda # this drive will be wiped!

apt update
apt -y install parted dosfstools arch-install-scripts systemd-container mmdebstrap
wipefs -a "$INSTALL_DEV"*
parted "$INSTALL_DEV" mklabel gpt mkpart e fat32 4MiB 1020MiB mkpart r 1020MiB 3068MiB set 1 esp on
udevadm settle
mkfs.fat -F 32 -n e /dev/disk/by-partlabel/e
mkfs.ext4 -L r /dev/disk/by-partlabel/r
mount LABEL=r "$CHROOT_DIR"
mmdebstrap --aptopt='Acquire::http { Proxy "http://10.10.10.1:3142"; }' --skip=cleanup/apt,cleanup/reproducible bookworm "$CHROOT_DIR"
mount -m LABEL=e "$CHROOT_DIR"/efi

systemd-nspawn -PD "$CHROOT_DIR" /bin/bash -x << 'CEOF'
mv /etc/apt/apt.conf.d/99mmdebstrap /etc/apt/apt.conf.d/proxy
export DEBIAN_FRONTEND=noninteractive
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/default_environment_locale select en_US.UTF-8'
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8'
apt -y install locales

sed -i -re '/\slocalhost(\s|$)/s/$/ debian/' /etc/hosts

echo do_symlinks = no > /etc/kernel-img.conf
apt -y install linux-image-"$(dpkg --print-architecture)"

echo 'root=LABEL=r console=tty0 console=ttyS0' > /etc/kernel/cmdline
apt -y install systemd-boot

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
echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/010_user-nopasswd

apt -y install wireless-regdb # to get rid of: failed to load regulatory.db
CEOF

# kludge to get systemd-boot entry in efi (adds needed binds and hides that bootctl is running in a container by hiding files src/basic/virt.c detect_container looks for)
systemd-nspawn --bind "$INSTALL_DEV" --bind "$(realpath /dev/disk/by-partlabel/e)" --bind /sys/firmware/efi -PD "$CHROOT_DIR" /bin/bash -x << 'CEOF'
d="$(mktemp -d)"
b=(/run/host /proc/1 /sys/fs/cgroup)
for m in "${b[@]}"; do mount -B "$d" "$m"; done
bootctl install
for m in "${b[@]}"; do umount "$m"; done
rmdir "$d"
CEOF

# UKI
systemd-nspawn -PD "$CHROOT_DIR" /bin/bash -x << 'CEOF'
set -e
apt -y install binutils
install -d /etc/ks-uki
wget -O /etc/ks-uki/img.bmp https://people.math.sc.edu/Burkardt/data/bmp/blackbuck.bmp
cat << 'KS-UKI' > /usr/local/sbin/ks-uki
#!/bin/bash
set -e

declare -A path
path[stub]=/usr/lib/systemd/boot/efi/linuxx64.efi.stub
path[osrel]=/usr/lib/os-release
path[uname]=$(mktemp); echo "$1" > "${path[uname]}"
path[cmdline]=/etc/kernel/cmdline
path[splash]=/etc/ks-uki/img.bmp
path[initrd]=/boot/initrd.img-"$1"
path[linux]=/boot/vmlinuz-"$1"
path[efiout]=/efi/EFI/Linux/debian-"$1".efi

alignment="$(objdump -p "${path[stub]}" | mawk '$1=="SectionAlignment" { print(("0x"$2)+0) }')"
getAligned () { echo $(( $1 + $alignment - $1 % $alignment )); }

declare -A offs
getOffsetAfter () { getAligned $(( offs[$1] + $( stat -Lc%s "${path[$1]}" ) )); }
offs[osrel]=$(getAligned $(objdump -h "${path[stub]}" | mawk 'NF==7 {s=("0x"$3)+0;o=("0x"$4)+0} END {print(s+o)}'))
offs[uname]=$(getOffsetAfter osrel)
offs[cmdline]=$(getOffsetAfter uname)
offs[splash]=$(getOffsetAfter cmdline)
offs[initrd]=$(getOffsetAfter splash)
offs[linux]=$(getOffsetAfter initrd)

declare -a args
for s in "${!offs[@]}"; do args+=(--add-section ".$s=${path[$s]}" --change-section-vma ".$s=$(printf 0x%x "${offs[$s]}")"); done
objcopy "${args[@]}" "${path[stub]}" "${path[efiout]}"
rm "${path[uname]}"
KS-UKI
chmod 755 /usr/local/sbin/ks-uki

entrySrc="$(bootctl list | grep -m1 source | awk '{print($2)}')"
if [[ "$entrySrc" =~ [^-]+/([^-]+)-(.*)\.conf ]]; then
  ks-uki "${BASH_REMATCH[2]}"
  rm -rv "/efi/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" "$entrySrc"
else
  echo 'Failed to find kernel version to generate UKI from'
fi
CEOF

genfstab -L "$CHROOT_DIR" | grep LABEL=[er] > "$CHROOT_DIR"/etc/fstab
umount -R "$CHROOT_DIR"
