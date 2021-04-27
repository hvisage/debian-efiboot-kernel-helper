#!/bin/bash
#Copy righted BSD
set -x
id -a

cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ buster main contrib non-free
deb http://deb.debian.org/debian/ buster-updates main contrib non-free
deb http://security.debian.org/debian-security buster/updates main contrib non-free
deb http://deb.debian.org/debian buster-backports main contrib non-free
EOF

apt -y update
apt install --yes debootstrap gdisk dkms dpkg-dev dosfstools curl jq pciutils wget linux-headers-$(uname -r)
echo zfs-dkms zfs-dkms/note-incompatible-licenses note  | debconf-set-selections
apt install --yes -t buster-backports --no-install-recommends zfs-dkms

apt install --yes -t buster-backports zfsutils-linux
modprobe zfs
which curl
read "next"

ROOTDISK=`lsblk --json | jq '.blockdevices[]|select (.children[].mountpoint == "/")|.name'` ; echo $ROOTDISK
OTHERDISKS=`lsblk --output-all --json | jq -r '.blockdevices[]| select (.name != '$ROOTDISK')|(.model+" "+.serial) '| tr ' ' '_'` ; echo $OTHERDISKS

pushd /dev/disk/by-id
for i in $OTHERDISKS
do
	DISKNAMES=`ls nvme-$i `" "$DISKNAMES
done
echo $DISKNAMES
popd

DUMMYSIZE=0
for D in $DISKNAMES
do
	DISK=/dev/disk/by-id/$D
	sgdisk --zap-all $DISK
	sgdisk -a1 -n1:24K:+1000K -t1:EF02 $DISK
	sgdisk     -n2:1M:+1024M   -t2:EF00 $DISK
	sgdisk     -n3:0:0        -t3:BF00 $DISK
	partx -s $DISK
	udevadm settle
	mkfs.vfat -F32 -n EFI ${DISK}-part2
	P3S=`lsblk -nbo SIZE ${DISK}-part3`
	if [ $DUMMYSIZE -lt $P3S ] ; then DUMMYSIZE=$P3S ; fi

	MEMBERS=${D}-part3" "$MEMBERS

done

truncate -s $DUMMYSIZE /tmp/DUMMY
MEMBERS=$MEMBERS" "/tmp/DUMMY
lsblk

read "next"
TYPE=mirror

zpool create -f -o ashift=12 -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    rpool $TYPE $MEMBERS
zpool offline rpool /tmp/DUMMY
read "next"

zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/debian10
zfs mount rpool/ROOT/debian10

zfs create                                 rpool/boot
mkdir /mnt/boot/efi
mount ${DISK}-part2 /mnt/boot/efi

zfs create                                 rpool/home
zfs create -o mountpoint=/root             rpool/home/root
chmod 700 /mnt/root
zfs create -o canmount=off                 rpool/var
zfs create -o com.sun:auto-snapshot=false    -o mountpoint=/var/lib/docker rpool/docker
zfs create                                 rpool/var/log

zpool status -v
zfs list
read "next"


debootstrap  --include=efivar,efibootmgr,dosfstools,gnupg2,ca-certificates,ca-certificates-java,ca-certificates-mono,curl,wget buster /mnt

mkdir -p /mnt/etc/apt/sources.list.d/
cp /etc/apt/sources.list.d/* /mnt/etc/apt/sources.list.d/
mkdir /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/
apt install rsync
hash
rsync -vaP /etc/network /mnt/etc

cat > /mnt/etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ buster main contrib non-free
deb http://deb.debian.org/debian/ buster-updates main contrib non-free
deb http://security.debian.org/debian-security buster/updates main contrib non-free
deb http://deb.debian.org/debian buster-backports main contrib non-free
EOF

cat > /mnt/etc/apt/preferences.d/90_zfs << EOF
Package: libnvpair1linux libuutil1linux libzfs2linux libzfslinux-dev libzpool2linux python3-pyzfs pyzfs-doc spl spl-dkms zfs-dkms zfs-dracut zfs-initramfs zfs-test zfsutils-linux zfsutils-linux-dev zfs-zed
Pin: release n=buster-backports
Pin-Priority: 990
EOF

pushd /mnt/root

mkdir -p pubkeys debs scripts

curl  https://last-public-ovh-rtm.snap.mirrors.ovh.net/ovh_rtm.pub > pubkeys/ovh_rtm.pub
curl  http://last.public.ovh.metrics.snap.mirrors.ovh.net/pub.key > pubkeys/ovh_metrics.pub
curl https://www.postgresql.org/media/keys/ACCC4CF8.asc > pubkeys/pg.pub
wget --directory-prefix=`pwd`/debs/ https://apt.tros.ovh/debs/hev-kernel-helper_1.0.0+1_all.deb
wget --directory-prefix=`pwd`/debs/ https://apt.tros.ovh/debs/kernel-4.19_1.0.0+1_all.deb
cat > debconf.settings << EOF
tzdata  tzdata/Zones/Etc        select  UTC
console-setup   console-setup/fontface47        select  Do not change the boot/kernel font
console-setup   console-setup/charmap47 select  UTF-8
keyboard-configuration  keyboard-configuration/unsupported_config_layout        boolean true
keyboard-configuration  keyboard-configuration/layoutcode       string  us
locales locales/default_environment_locale      select  C.UTF-8
locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8, en_ZA ISO-8859-1, en_ZA.UTF-8 UTF-8
zfs-dkms zfs-dkms/note-incompatible-licenses note
EOF

read "next2"

cat > script.sh << EOFM
#!/bin/bash
set -x
cd /root
apt install --yes gnupg2 ca-certificates ca-certificates-java ca-certificates-mono curl
cat /root/pubkeys/* | apt-key add -

debconf-set-selections < /root/debconf.settings
apt update
apt upgrade --yes
apt update
apt install --yes console-setup locales
update-locale LANG=en_US.UTF-8
apt-get install --yes ovh-rtm-metrics-toolkit

apt install --yes dpkg-dev linux-headers-amd64 linux-image-amd64
apt install --yes zfs-initramfs



bootctl install --path=/boot/efi

set +x
EOFM

chmod +x script.sh
popd

mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys

chroot /mnt /usr/bin/env DISK=$DISK bash /root/script.sh

