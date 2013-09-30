#!/bin/sh

#----
# bootstrap fedora19

#release=$(cat /etc/fedora-release | awk '/^Fedora/ {print $3}')
#arch=$(arch)
release=19
arch=x86_64
ROOTFS=/var/lib/libvirt/lxc/fedora$release-$arch
ROOT_PASSWORD=toor
UTSNAME=fedora19

# -- prepare rootfs directory
rm -rf $ROOTFS
mkdir -p $ROOTFS

# -- download base system
TMPROOT=/tmp
mkdir -p $TMPROOT

PKG_LIST="yum initscripts passwd rsyslog vim dhclient chkconfig rootfiles policycoreutils openssh-server net-tools nc traceroute"

BASE_URL="http://mirror.switch.ch/ftp/mirror/fedora/linux"
RELEASE_URL="$BASE_URL/releases/$release/Fedora/$arch/os/Packages/f/fedora-release-$release-1.noarch.rpm"
echo "Fetching from $RELEASE_URL"

curl -sf "$RELEASE_URL" > $TMPROOT/$(basename $RELEASE_URL)
mkdir -p $ROOTFS/var/lib/rpm
rpm --root $ROOTFS --initdb
rpm --root $ROOTFS -ivh $TMPROOT/$(basename $RELEASE_URL)
yum --noplugins --setopt=fedora.baseurl="$BASE_URL/releases/$release/Everything/$arch/os/" --setopt=fedora-updates.baseurl="$BASE_URL/updates/$release/$arch/" \
--releasever=$release --installroot $ROOTFS -y --nogpgcheck install $PKG_LIST

# continue only on success
if [ $? -gt 0 ]; then
    exit 1
fi


# -- configure fedora

# configure selinux
mkdir -p $ROOTFS/selinux
echo 0 > $ROOTFS/selinux/enforce

# configure /dev
DEV_PATH=${ROOTFS}/dev
rm -rf $DEV_PATH
mkdir -p $DEV_PATH
mknod -m 666 ${DEV_PATH}/null c 1 3
mknod -m 666 ${DEV_PATH}/zero c 1 5
mknod -m 666 ${DEV_PATH}/random c 1 8
mknod -m 666 ${DEV_PATH}/urandom c 1 9
mkdir -m 755 ${DEV_PATH}/pts
mkdir -m 1777 ${DEV_PATH}/shm
mknod -m 666 ${DEV_PATH}/tty c 5 0
mknod -m 666 ${DEV_PATH}/tty0 c 4 0
mknod -m 666 ${DEV_PATH}/tty1 c 4 1
mknod -m 666 ${DEV_PATH}/tty2 c 4 2
mknod -m 666 ${DEV_PATH}/tty3 c 4 3
mknod -m 666 ${DEV_PATH}/tty4 c 4 4
mknod -m 600 ${DEV_PATH}/console c 5 1
mknod -m 666 ${DEV_PATH}/full c 1 7
mknod -m 600 ${DEV_PATH}/initctl p
mknod -m 666 ${DEV_PATH}/ptmx c 5 2

# configure fstab
cat <<EOF > ${ROOTFS}/etc/fstab
proc            /proc         proc    nodev,noexec,nosuid 0 0
devpts          /dev/pts      devpts  defaults 0 0
sysfs           /sys          sysfs   defaults  0 0
EOF

# configure default eth interface
cat <<EOF > ${ROOTFS}/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
NM_CONTROLLED=no
TYPE=Ethernet
EOF

# configure 
cat <<EOF > ${ROOTFS}/etc/sysconfig/network
NETWORKING=yes
HOSTNAME=${UTSNAME}
EOF

# configure hostname
cat <<EOF > ${ROOTFS}/etc/hostname
${UTSNAME}
EOF

# configure host
cat <<EOF > ${ROOTFS}/etc/hosts
127.0.0.1 localhost ${UTSNAME}
EOF

# config resolv.conf
cat <<EOF > ${ROOTFS}/etc/resolv.conf
nameserver 8.8.8.8
search wyrls.net
EOF

# configure systemd
ETC=/etc/systemd/system
LIB=/lib/systemd/system
chroot ${ROOTFS} ln -sf ${LIB}/multi-user.target ${ETC}/default.target
chroot ${ROOTFS} cp ${LIB}/basic.target ${ETC}/basic.target
chroot ${ROOTFS} sed -i 's/sysinit.target/systemd-tmpfiles-setup.service/' ${ETC}/basic.target
chroot ${ROOTFS} ln -s /dev/null ${ETC}/sysinit.target
chroot ${ROOTFS} ln -s /dev/null ${ETC}/udev-settle.service
chroot ${ROOTFS} ln -s /dev/null ${ETC}/fedora-readonly.service
chroot ${ROOTFS} rm -f ${ETC}/getty.target.wants/getty\@tty{2,3,4,5,6}.service
chroot ${ROOTFS} ln -s /dev/null ${ETC}/console-shell.service
chroot ${ROOTFS} cp ${LIB}/getty\@.service ${ETC}/getty\@.service
chroot ${ROOTFS} sed -i 's/^BindTo/\#&/' ${ETC}/getty\@.service
chroot ${ROOTFS} ln -sf ${ETC}/getty\@.service ${ETC}/getty.target.wants/getty\@tty1.service
chroot ${ROOTFS} sed -i 's/^Defaults\ *requiretty/\#&/' /etc/sudoers
chroot ${ROOTFS} sed -i 's/^.*loginuid.so.*$/\#&/' /etc/pam.d/login
chroot ${ROOTFS} sed -i 's/^.*loginuid.so.*$/\#&/' /etc/pam.d/sshd
chroot ${ROOTFS} sed -i 's/^.*loginuid.so.*$/\#&/' /etc/pam.d/crond
chroot ${ROOTFS} sed -i 's/^.*loginuid.so.*$/\#&/' /etc/pam.d/remote
echo "pts/0" >> ${ROOTFS}/etc/securetty

# -- set default root password
echo "setting root passwd to '$ROOT_PASSWORD'"
echo "root:$ROOT_PASSWORD" | chroot $ROOTFS chpasswd

# -- enable sshd
chroot ${ROOTFS} systemctl enable sshd.service
chroot ${ROOTFS} chkconfig network on

# -- end
exit 0
