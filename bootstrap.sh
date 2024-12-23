#!/bin/bash -x

export CHROOT_DIR=/mnt
export INSTALL_DEV=/dev/vda # this drive will be wiped!
export UKI_IMG=/root/uki.bmp
export SBCTL=/usr/local/sbin/sbctl
export SIGNPKG=/root/ks-systemd-boot-signer_1.0_all.deb
export TMPLUKSPASS; read TMPLUKSPASS <<< $(head -c 32 /dev/urandom | base64)

apt update
apt -y install parted dosfstools arch-install-scripts mmdebstrap efibootmgr cryptsetup
wipefs -a "$INSTALL_DEV"*
parted "$INSTALL_DEV" mklabel gpt mkpart e fat32 4MiB 1020MiB mkpart r 1020MiB 3068MiB set 1 esp on
udevadm settle
mkfs.fat -F 32 -n e /dev/disk/by-partlabel/e
<<< "$TMPLUKSPASS" tr -d \\n | cryptsetup -d - luksFormat /dev/disk/by-partlabel/r
<<< "$TMPLUKSPASS" tr -d \\n | cryptsetup -d - luksOpen   /dev/disk/by-partlabel/r r
mkfs.ext4 -L r $([ -b /dev/mapper/r ] && echo /dev/mapper/r || echo /dev/disk/by-partlabel/r)
mount LABEL=r "$CHROOT_DIR"
mmdebstrap --aptopt='Acquire::http { Proxy "http://10.10.10.1:3142"; }' --skip=cleanup/apt,cleanup/reproducible bookworm "$CHROOT_DIR"
mount -m LABEL=e "$CHROOT_DIR"/efi
cp "$UKI_IMG" "$CHROOT_DIR$UKI_IMG"
cp "$SBCTL" "$CHROOT_DIR$SBCTL"

# Create package to auto-sign systemd-boot
##apt -y install ruby-rubygems; gem install fpm
##trigf=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
##bashScript () { printf %s\\n '#!/bin/bash' 'trigf='"'$trigf'" "$@"; }
##fpm -n ks-systemd-boot-signer -s empty -t deb --deb-interest "$trigf" -p "$SIGNPKG" \
##  --after-install <(bashScript '[ "$1" = "configure" ] || [ "$1" = "triggered" ] && rm -f "$trigf".signed && [ -f "$trigf" ] && '"'$SBCTL'"' sign -o "$trigf"{.signed,} || true') \
##  --after-remove  <(bashScript 'rm -f "$trigf".signed')
##mv "$SIGNPKG" "$CHROOT_DIR$SIGNPKG"

arch-chroot "$CHROOT_DIR" bash -x << 'CEOF'
mv /etc/apt/apt.conf.d/99mmdebstrap /etc/apt/apt.conf.d/proxy
export DEBIAN_FRONTEND=noninteractive
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/default_environment_locale select en_US.UTF-8'
LANG=C.UTF-8 debconf-set-selections <<< 'locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8'
LANG=C.UTF-8 apt -y install locales

sed -i -re '/#force_color_prompt=yes/s/^#//' /etc/skel/.bashrc
echo -e 'alias lh=\x27ls -lhA\x27' >> /etc/skel/.bashrc
cp /etc/skel/.bashrc /root/

# systemd-boot + SecureBoot
sbctl create-keys
sbctl enroll-keys -m
cat << 'SIGNPKG' | base64 -d > "$SIGNPKG" # generated via fpm command above
ITxhcmNoPgpkZWJpYW4tYmluYXJ5LyAgMCAgICAgICAgICAgMCAgICAgMCAgICAgNjQ0ICAgICA0
ICAgICAgICAgYAoyLjAKY29udHJvbC50YXIuZ3ovIDAgICAgICAgICAgIDAgICAgIDAgICAgIDY0
NCAgICAgNjE3ICAgICAgIGAKH4sIAAAAAAAAA+2X32/TMBDH+5y/whS0vpA4vzMihkDiASSQJk3i
ZeLBSS6p1cSubAe2Mf53nLYqUzRUEErHj/tIVRr77Lv29D2fPTqbHN+SJcnmaRk/N9+DOAt9P0jS
KLPjaeCnM5JMH9ps1mvDFCHHcPUn4tGuSnTf6Ql9DAlO4/iH+Q/CeJT/LA6jGfEnjGnPf57/OKxD
P4U6S1kY+UmcsiJ7VkUh+BmcnoY1Ib1WVC+ZAlrJkq60q6+1ga5yCymNq3kjQNFyyUQDrWy85sZ5
6N+E/DweNYo3DagJC8Ah/ftpNtZ/moao/2PAhQEF2hA66LzlBd3Jmw7yplBzelfvV2ns2TGU+L+C
R9dSG9VN6eNQ/xdE4/4vixLU/1F4/IgWXNCC6aUznAT12eKXKsHCUR1xazJ/slk99zYNQYUF4i9h
q38utJnOxyH9R1Ey1r99Qf0fg9/X/6XVfjAnZ2ReSlHzplcwJx/J7S35PrPrMaEaZk5OyL01Y5i4
vDu+td3FI0vWUj3EqovStAsyLCKu3Ft/2W3z9Ovg26gesAgdxqM2a0bJdkIfh/r/KAvG+k8CPP+P
wjkrV6yBnNx/sXc+2JshlyIngec773gJQlvjXqyE/CzsrKikyomQApxXqlxyA6WxFSAnrG2d98xe
L+wHrMlzZXd9WUHBmXjhvLUHjrWAyr3gN9bady7swo2jCmrWt8Y5V1wqbq5zItfDDGudN7KD9Sba
pTHrnFK4Yt26Ba+UHRXS7RV3G/4JhPMadKn4erujkHbT/TvZWjz0H48gCIIgCIIgCIIgCIIgR+Ab
Gq717gAoAAAKZGF0YS50YXIuZ3ovICAgIDAgICAgICAgICAgIDAgICAgIDAgICAgIDY0NCAgICAg
NDAxICAgICAgIGAKH4sIAAAAAAAAA9PTZ6A5MAACc1NTMA0E6DSYbWhibmRgYGhqZmwOFDczNDBj
UDClvdMYGEqLSxKLFBToYdVgBHr6pcVFNE4DZMS/uaH5aPzTA0DivzgjsSiVZqmA5Pg3NDAwMhyN
f3oA5PhPyU+mSRogI/5NzUbLf7oA9PjPLtYtriwuSc1N0U3Kzy/RLc5Mz0ulsIIgPf5NDUfLf/oA
IuM/OSMxLz01Jz9dL72KZDtAEWxmYoIz/o0MDdHi39zEwIhBwYAG/sUAIzz+5bs5GOZLO6QzMfOe
2ch3SEHC9eHc5TsWh2YKvA1aW/hq2UvtgB/OnswqDqa11Zavp88x/bznudO9D5bHDm3e3CjENz3M
ZEey97Sme+z+x3LnGT7o8HwZGtnkt4RL8k9MpIHf+21GzyuW/KqUnDWXyz/B5x2P5sfOeA/FfIHY
+51xcYVCpt/Y5cJ+hjYOdCiMglEwCkbBKBgFo2AUjIJRMApGwSgYBaNgFIyCUTAKRsEoGAWjYBSM
glEwPAAAHsW2LwAoAAAK
SIGNPKG
apt -y install "$SIGNPKG"; rm "$SIGNPKG"
apt -y install systemd-boot

# KS-UKI
apt -y install binutils initramfs-tools
install -d /etc/ks-uki
mv "$UKI_IMG" /etc/ks-uki/splash.bmp
cat << 'KS-UKI' > /usr/local/sbin/ks-uki
#!/bin/bash -e
cmd=$1 et=$2 un=$3
efiout=/efi/EFI/Linux/"$et"-"$un".efi
if [ "$cmd"  = remove ]; then rm -f "$efiout"; exit 0; fi
if [ "$cmd" != add    ]; then echo bad cmd $cmd >&2;   exit 1; fi
/usr/local/sbin/sbctl bundle --initramfs /boot/initrd.img-"$un" --kernel-img /boot/vmlinuz-"$un" --splash-img /etc/ks-uki/splash.bmp "$efiout" &> /dev/null
/usr/local/sbin/sbctl sign "$efiout" &> /dev/null
rm -fr "/efi/$et/$un" "/efi/loader/entries/$et-$un.conf"
[ -d "/efi/$et" ] && rmdir --ignore-fail-on-non-empty "/efi/$et" || true
KS-UKI
st=$(cat << 'KS-UKI'
#!/bin/bash -e
un="%s"
if [ -z "$un" ]; then echo missing version number >&2; exit 1; fi
/usr/local/sbin/ks-uki "%s" "$(</etc/kernel/entry-token)" "$un"
KS-UKI
)
printf "$st\n" '$1' add    | tee > /dev/null /etc/kernel/postinst.d/zzz-ks-uki /etc/initramfs/post-update.d/zzz-ks-uki
printf "$st\n" '$1' remove | tee > /dev/null /etc/kernel/postrm.d/zzz-ks-uki
printf "$st\n" '$2' '$1'   | tee > /dev/null /etc/kernel/install.d/zzz-ks-uki.install # needed for systemd-boot purge then install because a systemd-boot install script looks for kernels to kernel-install add to /efi
chmod 755 /usr/local/sbin/ks-uki /etc/kernel/post{inst,rm}.d/zzz-ks-uki /etc/initramfs/post-update.d/zzz-ks-uki /etc/kernel/install.d/zzz-ks-uki.install

# LUKS related
debconf-set-selections <<< 'keyboard-configuration keyboard-configuration/variant select English (US)'
debconf-set-selections <<< 'console-setup console-setup/codeset47 select Guess optimal character set'
apt -y install cryptsetup-initramfs tpm2-tools xxd
echo r PARTLABEL=r none tpm2-device=auto,x-initrd.attach >> /etc/crypttab

# Turn off -x to get rid of pages of hex output
shellOpts="$-"
[[ "$shellOpts" =~ x ]] && set +x

# Calculate PCR7
switchHexEndian () { grep -o .. | tac | tr -d \\n; }
sha256UefiVariableData () {
  vn=$1 un=$2 vd=$3
  bvn=$(echo -n "$vn" | sed -re 's/(..)(..)(..)(..)-(..)(..)-(..)(..)-(....)-/\4\3\2\1\6\5\8\7\9/')
  bun=$(echo -n "$un" | iconv -t UTF-16LE | xxd -p | tr -d '[:space:]')
  bvd=$(echo -n "$vd" | tr -d '[:space:]')
  szbun=$(<<< $bun awk '{printf("%016x",length($0)/4)}' | switchHexEndian)
  szbvd=$(<<< $bvd awk '{printf("%016x",length($0)/2)}' | switchHexEndian)
  <<< $bvn$szbun$szbvd$bun$bvd xxd -r -p | sha256sum | cut -d ' ' -f 1
}
declare -A efiguid
efiguid+=( SecureBoot 8be4df61-93ca-11d2-aa0d-00e098032b8c )
efiguid+=( PK         8be4df61-93ca-11d2-aa0d-00e098032b8c )
efiguid+=( KEK        8be4df61-93ca-11d2-aa0d-00e098032b8c )
efiguid+=( db         d719b2cb-3d3a-4596-a3bc-dad00e67656f )
efiguid+=( dbx        d719b2cb-3d3a-4596-a3bc-dad00e67656f )
getEfiVar () { f=/sys/firmware/efi/efivars/"$1-${efiguid[$1]}"; test -e "$f" && cat "$f" | tail -c +$((1+4)) | xxd -p | tr -d '[:space:]'; }
sha256EfiVarWithData () { sha256UefiVariableData "${efiguid[$1]}" "$1" "$2"; }
sha256EfiVar () { sha256EfiVarWithData "$1" "$(getEfiVar "$1")"; }
pcr7=0000000000000000000000000000000000000000000000000000000000000000
extendPcr7 () { pcr7=$(echo "$pcr7$1" | xxd -r -p | sha256sum | cut -d ' ' -f 1); }
extendPcr7 "$(sha256EfiVarWithData SecureBoot 01)"
extendPcr7 "$(sha256EfiVar PK)"
extendPcr7 "$(sha256EfiVar KEK)"
extendPcr7 "$(sha256EfiVar db)"
extendPcr7 "$(sha256EfiVar dbx)"
extendPcr7 "$(echo 00000000 | xxd -r -p | sha256sum | cut -d ' ' -f 1)"
bdb=$(getEfiVar db)
szbdb0=$((0x$(echo "$bdb" | tail -c +$((1+16*2)) | head -c 8 | switchHexEndian)))
extendPcr7 "$(sha256EfiVarWithData db "$(echo "$bdb" | head -c $((szbdb0*2)) | tail -c +$((1+28*2)))")"

# Turn -x back on
[[ "$shellOpts" =~ x ]] && set -x

# Enroll TPM2 with calculated PCR7
d=$(mktemp -d)
pushd "$d" &> /dev/null
echo "$pcr7" | xxd -r -p > pcr.bin
tpm2_startauthsession -S pcr.ctx
tpm2_policypcr -S pcr.ctx -l sha256:7 -f pcr.bin -L pol.bin
tpm2_flushcontext pcr.ctx
tpm2_createprimary -C o -c prim.ctx -g sha256 -G ecc -a 'restricted|decrypt|fixedtpm|fixedparent|sensitivedataorigin|userwithauth'
read luksPass <<< $(head -c 32 /dev/urandom | base64)
<<< $luksPass base64 -d | tpm2_create -C prim.ctx -u public.obj -r private.obj -L pol.bin -i-
<<< $luksPass tr -d \\n | cryptsetup -d <(<<< $TMPLUKSPASS tr -d \\n) --new-keyfile - luksAddKey /dev/disk/by-partlabel/r
<<< $luksPass tr -d \\n | cryptsetup luksKillSlot /dev/disk/by-partlabel/r 0
unset luksPass
tpm2PolHash=$(xxd -p pol.bin | tr -d ' \n')
tpm2Blob=$(cat private.obj public.obj | base64 | tr -d ' \n')
tokenFmt='{"type":"systemd-tpm2","keyslots":["1"],"tpm2-blob":"%s","tpm2-pcrs":[7],"tpm2-pcr-bank":"sha256","tpm2-primary-alg":"ecc","tpm2-policy-hash":"%s","tpm2-pin":false}'
printf "$tokenFmt" "$tpm2Blob" "$tpm2PolHash" | cryptsetup token import --json-file - /dev/disk/by-partlabel/r
popd &> /dev/null
rm -r "$d"

# LUKS TPM kludge (for tpm2-device=auto in crypttab)
# Thanks to: https://github.com/wmcelderry/systemd_with_tpm2 and https://github.com/BoskyWSMFN/systemd_with_tpm2
apt -y install libtss2-dev
patch=(-e 's/([^\n]*\n)([^\n]*)# unlock via keyfile([^\n]*\n){3}/        if ! ([ -z "${CRYPTTAB_OPTION_keyscript+x}" ] \&\& '\
'([ -n "${CRYPTTAB_OPTION_tpm2_device}" ] || [ "$CRYPTTAB_KEY" != "none" ]) \&\& unlock_mapping "$CRYPTTAB_KEY"); then\n/')
sed -i -zr "${patch[@]}" /usr/share/initramfs-tools/scripts/local-top/cryptroot
patch=()
patch+=(-e 's/(CRYPTTAB_OPTION_no_write_workqueue)/\1 \\\n             CRYPTTAB_OPTION_tpm2_device/')
patch+=(-e 's/(no-write-workqueue\) OPTION="no_write_workqueue";;)/\1\n        tpm2-device) OPTION="tpm2_device";;/')
patch+=(-e 's/(        # and now the flags)/        tpm2-device) ;;\n\1/')
patch+=(-e 's@(fi\n\n)(    /sbin/cryptsetup -T1 \\)@\1    if [[ -z "${CRYPTTAB_OPTION_tpm2_device}" ]] || [ "$keyfile" = "-" ]; then\n\n\2@')
patch+=(-e 's@(open -- "\$CRYPTTAB_SOURCE" "\$CRYPTTAB_NAME")@\1\n    else\n        /lib/systemd/systemd-cryptsetup attach '\
'"${CRYPTTAB_NAME}" "${CRYPTTAB_SOURCE}" "${keyfile}" "tpm2-device=${CRYPTTAB_OPTION_tpm2_device},headless"\n    fi\n@')
sed -i -zr "${patch[@]}" /usr/lib/cryptsetup/functions
cat << 'HOOK' > /etc/initramfs-tools/hooks/systemd_cryptsetup_hook
#!/bin/sh
case "$1" in prereqs) exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
copy_exec /lib/systemd/systemd-cryptsetup /lib/systemd
for i in /lib/x86_64-linux-gnu/libtss2*; do copy_exec ${i} /lib/x86_64-linux-gnu; done
for i in /lib/x86_64-linux-gnu/cryptsetup/*; do copy_file ${i} ${i}; done
HOOK
chmod +x /etc/initramfs-tools/hooks/systemd_cryptsetup_hook

# Kernel
echo do_symlinks = no > /etc/kernel-img.conf
echo root=LABEL=r console=tty0 console=ttyS0 > /etc/kernel/cmdline
apt -y install linux-image-"$(dpkg --print-architecture)"

echo '[Match] Name=enp1s0 [Network] Address=10.10.10.3/24 Gateway=10.10.10.1 DNS=1.1.1.1 DNS=8.8.8.8 [DHCPv4] UseDNS=false [DHCPv6] UseDNS=false' | tr ' ' \\n > /etc/systemd/network/10-enp1s0.network
systemctl enable systemd-networkd

tasksel install standard ssh-server

apt -y install sudo
adduser --disabled-password --comment '' user
adduser user sudo
echo user:live | chpasswd
echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/010_user-nopasswd

apt -y install wireless-regdb # to get rid of: failed to load regulatory.db
sed -i -re '/\slocalhost(\s|$)/s/$/ debian/' /etc/hosts
CEOF

genfstab -L "$CHROOT_DIR" | grep LABEL=[er] > "$CHROOT_DIR"/etc/fstab
umount -R "$CHROOT_DIR"
[ -b /dev/mapper/r ] && cryptsetup luksClose r
