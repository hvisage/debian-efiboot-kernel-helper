#!/bin/bash
#Copyrighted BSD (Or whatever but updates and assistance to get it into Debian would be great ;)
#
# sudo -i
# rm zfs-root.sh ; wget https://apt.tros.ovh/scripts/zfs-root.sh ; chmod +x zfs-root.sh ; ./zfs-root.sh
#
# TEsted on a installation of an OVH Infra-3 2x NVMe disks
#
# Assumptions/pre-requisites before running:
# 00) UEFI boot
# 0) su/sudo'd to root
# 1) Debian 10 installled on a single disk
# 2) other disks available
# 3) *this* script as is will create a MIRROR type with a dummy
# 4) will force a reboot, pray and have the console avilable :)
# 5) once rebooted, you'll have to
# - sgdisk /dev/disk/ZFS -R /dev/disk/oldBoot
# - sgdisk -G /dev/disk/oldBoot
# - zpool replace rpool /tmp/DUMMY /dev/disk/oldBoot-part3
# - /usr/sbin/hev-efiboot-tool format /dev/disk/oldBoot-part2
# - /usr/sbin/hev-efiboot-tool init /dev/disk/oldBoot-part2
# - /usr/sbin/hev-efiboot-tool refresh

set +x
id -a
WAIT=echo

echo "Need some contrib stuff and ZFS"
echo "-------------------------------"
cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ buster main contrib non-free
deb http://deb.debian.org/debian/ buster-updates main contrib non-free
deb http://security.debian.org/debian-security buster/updates main contrib non-free
deb http://deb.debian.org/debian buster-backports main contrib non-free
EOF

apt -y update
apt -y full-upgrade
apt install --yes debootstrap gdisk dkms dpkg-dev dosfstools curl jq pciutils wget rsync linux-headers-$(uname -r)
hash

#Accept the license agreements:
echo zfs-dkms zfs-dkms/note-incompatible-licenses note  | debconf-set-selections
apt install --yes -t buster-backports --no-install-recommends zfs-dkms
apt install --yes -t buster-backports zfsutils-linux
modprobe zfs
which curl jq rsync

${WAIT} "next"

echo "Find the disk we booted from"
ROOTDISK=`lsblk --json | jq  '.blockdevices[]|select (.type == "disk" and has("children"))| select (.children[].mountpoint == "/")|.name'` ; echo $ROOTDISK
echo "Now get the rest of the disks to add to ZFS"
OTHERDISKS=`lsblk --output-all --json | jq -r '.blockdevices[]| select (.name != '$ROOTDISK')|(.model+" "+.serial) '| tr ' ' '_'` ; echo $OTHERDISKS

pushd /dev/disk/by-id
for i in $OTHERDISKS
do
	DISKNAMES=`ls nvme-$i `" "$DISKNAMES
done
echo $DISKNAMES
popd

echo "format the disk for ZFS"
DUMMYSIZE=0
for D in $DISKNAMES
do
	DISK=/dev/disk/by-id/$D
	sgdisk --zap-all $DISK
	#We might not need this:
	sgdisk -a1 -n1:24K:+1000K -t1:EF02 $DISK
	sgdisk     -n2:1M:+1024M   -t2:EF00 $DISK
	sgdisk     -n3:0:0        -t3:BF00 $DISK
	partx -s $DISK
	#udev needs to get it's stuff done, else the format doesn't
	udevadm settle
	#mkfs.vfat -F32 -n EFI ${DISK}-part2
	P3S=`lsblk -nbo SIZE ${DISK}-part3`
	#This is needed to get the size for the dummy disk
	if [ $DUMMYSIZE -lt $P3S ] ; then DUMMYSIZE=$P3S ; fi
	MEMBERS=${D}-part3" "$MEMBERS
done

#Dummy disk
truncate -s $DUMMYSIZE /tmp/DUMMY
MEMBERS=$MEMBERS" "/tmp/DUMMY
lsblk

${WAIT} "next"
TYPE=mirror

zpool create -f -o ashift=12 -O acltype=posixacl -O canmount=off -O compression=lz4 \
    -O dnodesize=auto -O normalization=formD -O relatime=on \
    -O xattr=sa -O mountpoint=/ -R /mnt \
    rpool $TYPE $MEMBERS
#offline the dummy as to prevent disk writes to it
zpool offline rpool /tmp/DUMMY
zpool status -v
${WAIT} "next"

#This creates the necessary mountpoints
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/debian10
zfs mount rpool/ROOT/debian10
zfs create                                 rpool/boot
mkdir /mnt/boot/efi
#mount ${DISK}-part2 /mnt/boot/efi
zfs create                                 rpool/home
zfs create -o mountpoint=/root             rpool/home/root
chmod 700 /mnt/root
zfs create -o canmount=off                 rpool/var
zfs create -o com.sun:auto-snapshot=false    -o mountpoint=/var/lib/docker rpool/docker
zfs create                                 rpool/var/log
zpool status -v
zfs list
${WAIT} "next"

#Install Debian in the ZFS rpool
debootstrap  --exclude=apparmor \
  --include=efivar,efibootmgr,dosfstools,gnupg2,ca-certificates,\
ca-certificates-java,ca-certificates-mono,curl,wget,gdisk,util-linux,\
jq,sudo,openssh-server,dpkg-dev,linux-headers-amd64,linux-image-amd64 \
  buster /mnt || exit 111


#fixing ZFS related stuff
mkdir -p /mnt/etc/apt/sources.list.d/
cp /etc/apt/sources.list.d/* /mnt/etc/apt/sources.list.d/
mkdir /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/

echo
echo '# Need the "Same" network'
echo
rsync -va /etc/network /mnt/etc

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
keyboard-configuration  keyboard-configuration/variant select English (US)
locales locales/default_environment_locale      select  C.UTF-8
locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8, en_ZA ISO-8859-1, en_ZA.UTF-8 UTF-8
zfs-dkms zfs-dkms/note-incompatible-licenses note
EOF
# lsblk --json -O --list |jq -r '.blockdevices[]|select (.label =="EFI")|.uuid' > /mnt/etc/kernel/efiboot-uuids
echo ""
${WAIT} "--next2---"

cat > script.sh << EOFM
#!/bin/bash
set -x
cd /root

cat /root/pubkeys/* | apt-key add -

debconf-set-selections < /root/debconf.settings
apt update
apt upgrade --yes
apt install --yes console-setup locales
update-locale LANG=en_US.UTF-8
apt install --yes zfs-initramfs
apt install --yes ovh-rtm-metrics-toolkit

echo
echo "**** done apt-gets"
echo
dpkg -i /root/debs/hev-kernel*
echo $DISKNAMES
echo
echo "%%%%%%% efi jobs"
echo
for D in $DISKNAMES
do
 /usr/sbin/hev-efiboot-tool format /dev/disk/by-id/\${D}-part2 --force
 echo "waiting for them udev..." ; sleep 2
 /usr/sbin/hev-efiboot-tool init /dev/disk/by-id/\${D}-part2
done
/usr/sbin/hev-efiboot-tool clean
/usr/sbin/hev-efiboot-tool kernel list
/usr/sbin/hev-efiboot-tool refresh
#bootctl install --path=/boot/efi

EOFM

chmod +x script.sh
popd

echo "
Add debian user
"
useradd -R /mnt -m -s /bin/bash debian
rsync -va ~debian/.ssh /mnt/home/debian
echo
echo "====extr etc stuff"
echo
rsync -va /etc/ssh /etc/sudo* /mnt/etc
rsync -va ~/.ssh /mnt/root

echo "root=ZFS=rpool/ROOT/debian10 boot=zfs" > /mnt/etc/kernel/cmdline

echo
echo "=====Mounting devices==="
echo
mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys
mount --rbind /run  /mnt/run

echo
echo "----chroot---"
echo
chroot /mnt /usr/bin/env bash /root/script.sh
echo
echo "===done chroot script.sh"
echo
umount -flvR /mnt
zpool export rpool
reboot -f

