#!/bin/sh
# 
# This script bootstrap Fedora.

release=19
arch=`uname -m`
ROOTFS=/var/lib/lxc/fedora$release-$arch/rootfs
ROOT_PASSWORD=toor
UTSNAME=fedora19
PKG_LIST="yum initscripts passwd rsyslog dhclient chkconfig rootfiles policycoreutils openssh-server net-tools nc traceroute"
BASE_URL="http://mirror.switch.ch/ftp/mirror/fedora/linux"
RELEASE_URL="$BASE_URL/releases/$release/Fedora/$arch/os/Packages/f/fedora-release-$release-2.noarch.rpm"

# Prepare rootfs directory
rm -rf $ROOTFS
mkdir -p $ROOTFS

# Download base system
TMPROOT=/tmp
mkdir -p $TMPROOT

echo "Fetching from $RELEASE_URL"

curl -sf "$RELEASE_URL" > $TMPROOT/$(basename $RELEASE_URL)
mkdir -p $ROOTFS/var/lib/rpm
rpm --root $ROOTFS --initdb
rpm --root $ROOTFS -ivh $TMPROOT/$(basename $RELEASE_URL)
yum -y install \
    --noplugins \
    --setopt=fedora.baseurl="$BASE_URL/releases/$release/Everything/$arch/os/" \
    --setopt=fedora-updates.baseurl="$BASE_URL/updates/$release/$arch/" \
    --releasever=$release \
    --installroot $ROOTFS \
    --nogpgcheck \
     $PKG_LIST

# Continue only on success
if [ $? -gt 0 ]; then
    exit 1
fi

# Configure selinux
mkdir -p $ROOTFS/selinux
echo 0 > $ROOTFS/selinux/enforce

# Configure /dev
DEV_PATH=$ROOTFS/dev
rm -rf $DEV_PATH
mkdir -p $DEV_PATH
mknod -m 666 $DEV_PATH/null c 1 3
mknod -m 666 $DEV_PATH/zero c 1 5
mknod -m 666 $DEV_PATH/random c 1 8
mknod -m 666 $DEV_PATH/urandom c 1 9
mkdir -m 755 $DEV_PATH/pts
mkdir -m 1777 $DEV_PATH/shm
mknod -m 666 $DEV_PATH/tty c 5 0
mknod -m 666 $DEV_PATH/tty0 c 4 0
mknod -m 666 $DEV_PATH/tty1 c 4 1
mknod -m 666 $DEV_PATH/tty2 c 4 2
mknod -m 666 $DEV_PATH/tty3 c 4 3
mknod -m 666 $DEV_PATH/tty4 c 4 4
mknod -m 600 $DEV_PATH/console c 5 1
mknod -m 666 $DEV_PATH/full c 1 7
mknod -m 600 $DEV_PATH/initctl p
mknod -m 666 $DEV_PATH/ptmx c 5 2

# Configure fstab
cat <<EOF > $ROOTFS/etc/fstab
proc            /proc         proc    nodev,noexec,nosuid 0 0
devpts          /dev/pts      devpts  defaults 0 0
sysfs           /sys          sysfs   defaults  0 0
EOF

# Configure default eth interface
cat <<EOF > $ROOTFS/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
NM_CONTROLLED=no
TYPE=Ethernet
EOF

# Configure 
cat <<EOF > $ROOTFS/etc/sysconfig/network
NETWORKING=yes
HOSTNAME=$UTSNAME
EOF

# Configure hostname
cat <<EOF > $ROOTFS/etc/hostname
$UTSNAME
EOF

# Configure host
cat <<EOF > $ROOTFS/etc/hosts
127.0.0.1 localhost $UTSNAME
EOF

# Config resolv.conf
cat <<EOF > $ROOTFS/etc/resolv.conf
nameserver 8.8.8.8
EOF

# Configure systemd
ETC=/etc/systemd/system
LIB=/lib/systemd/system
chroot $ROOTFS ln -sf $LIB/multi-user.target $ETC/default.target
chroot $ROOTFS cp $LIB/basic.target $ETC/basic.target
chroot $ROOTFS sed -i 's/sysinit.target/systemd-tmpfiles-setup.service/' $ETC/basic.target
chroot $ROOTFS ln -s /dev/null $ETC/sysinit.target
chroot $ROOTFS ln -s /dev/null $ETC/udev-settle.service
chroot $ROOTFS ln -s /dev/null $ETC/fedora-readonly.service
chroot $ROOTFS rm -f $ETC/getty.target.wants/getty\@tty{2,3,4,5,6}.service
chroot $ROOTFS ln -s /dev/null $ETC/console-shell.service
chroot $ROOTFS cp $LIB/getty\@.service $ETC/getty\@.service
chroot $ROOTFS sed -i 's/^BindTo/\#&/' $ETC/getty\@.service
chroot $ROOTFS ln -sf $ETC/getty\@.service $ETC/getty.target.wants/getty\@tty1.service
chroot $ROOTFS sed -i 's/^Defaults\ *requiretty/\#&/' /etc/sudoers
chroot $ROOTFS sed -i 's/^.*loginuid.so.*$/\#&/' /etc/pam.d/{login,sshd,crond,remote}
echo "pts/0" >> $ROOTFS/etc/securetty

# Set default root password
echo "setting root passwd to '$ROOT_PASSWORD'"
echo "root:$ROOT_PASSWORD" | chroot $ROOTFS chpasswd

# Enable sshd
chroot $ROOTFS systemctl enable sshd.service
chroot $ROOTFS chkconfig network on

# Sample lxc config
LXC_ROOT_PATH=/var/lib/lxc
LXC_NETWORK_TYPE=veth
LXC_NETWORK_LINK=virbr0

cat <<EOF >> $LXC_ROOT_PATH/$UTSNAME-$arch/config
lxc.utsname = $UTSNAME
lxc.tty = 4
lxc.pts = 1024
lxc.rootfs = $ROOTFS
lxc.mount  = $ROOTFS/etc/fstab
lxc.autodev = 1

# networking
lxc.network.type = $LXC_NETWORK_TYPE
lxc.network.flags = up
lxc.network.link = $LXC_NETWORK_LINK
lxc.network.name = eth0
lxc.network.mtu = 1500

# cgroups
lxc.cgroup.devices.deny = a

# /dev/null and zero
lxc.cgroup.devices.allow = c 1:3 rwm
lxc.cgroup.devices.allow = c 1:5 rwm

# consoles
lxc.cgroup.devices.allow = c 5:1 rwm
lxc.cgroup.devices.allow = c 5:0 rwm
lxc.cgroup.devices.allow = c 4:0 rwm
lxc.cgroup.devices.allow = c 4:1 rwm

# /dev/{,u}random
lxc.cgroup.devices.allow = c 1:9 rwm
lxc.cgroup.devices.allow = c 1:8 rwm
lxc.cgroup.devices.allow = c 136:* rwm
lxc.cgroup.devices.allow = c 5:2 rwm

# rtc
lxc.cgroup.devices.allow = c 254:0 rwm
EOF
# End sample config

# Create systemd service unit for controlling the container
cat <<EOF > /etc/systemd/system/$UTSNAME-$arch@lxc.service
[Unit]
Description=Linux Container $UTSNAME-$arch
After=network.target

[Service]
Type=simple
Restart=always
ExecStart=/usr/bin/lxc-start -n $UTSNAME-$arch
ExecReload=/usr/bin/lxc-restart -n $UTSNAME-$arch
ExecStop=/usr/bin/lxc-stop -n $UTSNAME-$arch

[Install]
WantedBy=multi-user.target
EOF

exit 0
