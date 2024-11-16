#!/bin/bash -x

CHROOT_DIR=/mnt
INSTALL_DEV=/dev/vda # this drive will be wiped!
UKI_IMG=/root/uki.bmp
SBCTL=/usr/local/sbin/sbctl

apt update
apt -y install parted dosfstools arch-install-scripts systemd-container mmdebstrap efibootmgr
wipefs -a "$INSTALL_DEV"*
parted "$INSTALL_DEV" mklabel gpt mkpart e fat32 4MiB 1020MiB mkpart r 1020MiB 3068MiB set 1 esp on
udevadm settle
mkfs.fat -F 32 -n e /dev/disk/by-partlabel/e
mkfs.ext4 -L r /dev/disk/by-partlabel/r
mount LABEL=r "$CHROOT_DIR"
mmdebstrap --aptopt='Acquire::http { Proxy "http://10.10.10.1:3142"; }' --skip=cleanup/apt,cleanup/reproducible bookworm "$CHROOT_DIR"
mount -m LABEL=e "$CHROOT_DIR"/efi
cp "$UKI_IMG" "$CHROOT_DIR$UKI_IMG"
cp "$SBCTL" "$CHROOT_DIR$SBCTL"

systemd-nspawn -E UKI_IMG="$UKI_IMG" -E SBCTL="$SBCTL" -PD "$CHROOT_DIR" /bin/bash -x << 'CEOF'
mv /etc/apt/apt.conf.d/99mmdebstrap /etc/apt/apt.conf.d/proxy
export DEBIAN_FRONTEND=noninteractive
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/default_environment_locale select en_US.UTF-8'
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8'
apt -y install locales

# systemd-boot + SecureBoot
apt -y install systemd-boot
sbctl create-keys
sbctl sign /efi/EFI/systemd/systemd-bootx64.efi
sbctl sign /efi/EFI/BOOT/BOOTX64.EFI

# KS-UKI
apt -y install binutils initramfs-tools
install -d /etc/ks-uki
mv "$UKI_IMG" /etc/ks-uki/splash.bmp
cat << 'KS-UKI' > /usr/local/sbin/ks-uki
#!/bin/bash -e
cmd=$1 et=$2 un=$3
declare -A path
path[stub]=/usr/lib/systemd/boot/efi/linuxx64.efi.stub
path[osrel]=/usr/lib/os-release
path[uname]=$(mktemp); echo "$un" > "${path[uname]}"
path[cmdline]=/etc/kernel/cmdline
path[splash]=/etc/ks-uki/splash.bmp
path[initrd]=/boot/initrd.img-"$un"
path[linux]=/boot/vmlinuz-"$un"
path[efiout]=/efi/EFI/Linux/"$et"-"$un".efi
if [ "$cmd"  = rm ]; then rm -f "${path[efiout]}"; exit 0; fi
if [ "$cmd" != mk ]; then echo bad cmd $cmd >&2;   exit 1; fi
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
/usr/local/sbin/sbctl sign "${path[efiout]}"
rm -r "${path[uname]}" "/efi/$et/$un" "/efi/loader/entries/$et-$un.conf"
rmdir --ignore-fail-on-non-empty "/efi/$et"
KS-UKI
st=$(cat << 'KS-UKI'
#!/bin/bash -e
if [ -z "$1" ]; then echo missing version number >&2; exit 1; fi
/usr/local/sbin/ks-uki '%s' "$(</etc/kernel/entry-token)" "$1"
KS-UKI
)
printf "$st\n" mk | tee > /dev/null /etc/kernel/postinst.d/zzz-ks-uki /etc/initramfs/post-update.d/zzz-ks-uki
printf "$st\n" rm | tee > /dev/null /etc/kernel/postrm.d/zzz-ks-uki
chmod 755 /usr/local/sbin/ks-uki /etc/kernel/post{inst,rm}.d/zzz-ks-uki /etc/initramfs/post-update.d/zzz-ks-uki

echo do_symlinks = no > /etc/kernel-img.conf
echo root=LABEL=r console=tty0 console=ttyS0 > /etc/kernel/cmdline
apt -y install linux-image-"$(dpkg --print-architecture)"

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
sed -i -re '/\slocalhost(\s|$)/s/$/ debian/' /etc/hosts
CEOF

mount -m -B "$CHROOT_DIR"/var/lib/sbctl /var/lib/sbctl
sbctl enroll-keys -m
umount /var/lib/sbctl
genfstab -L "$CHROOT_DIR" | grep LABEL=[er] > "$CHROOT_DIR"/etc/fstab
umount -R "$CHROOT_DIR"
efibootmgr -c -d "$INSTALL_DEV" -p 1 -l '\EFI\systemd\systemd-bootx64.efi' -L 'Linux Boot Manager' # kludge because installing systemd-boot in systemd-nspawn doesn't add a boot entry
