#!/bin/bash -x -e

TARGET_REPOSITORY=@(TARGET_REPOSITORY)
ROS_REPO_FQDN=@(FQDN)
PACKAGE=@(PACKAGE)
DISTRO=@(DISTRO)
DISTRO_VER=@(DISTRO_VER)
ARCH=@(ARCH)

cd $WORKSPACE/monitored_vcs
. setup.sh

# check precondition that all dependents exist, don't check if no dependencies
@[if DEPENDENTS]
#sudo $CHECKOUT_DIR/scripts/assert_package_dependencies_present.py $rootdir $aptconffile  $PACKAGE
@[end if]

# Verify a clean workspace and output directory
rm -rf $WORKSPACE/output
rm -rf $WORKSPACE/workspace
mkdir -p $WORKSPACE/output
mkdir -p $WORKSPACE/workspace

# Check and update mock config
mount | grep -q mock_chroot_tmpfs && sudo umount mock_chroot_tmpfs || echo "mock_chroot_tmpfs is not mounted! hooray!"
MOCK_CONF_DIR=`$WORKSPACE/monitored_vcs/scripts/configure_mock heisenbug --get-default-output-dir`
$WORKSPACE/monitored_vcs/scripts/configure_mock @(DISTRO) --arch @(ARCH)
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --scrub=yum-cache
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --init
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --copyout /etc/yum.conf $WORKSPACE/workspace/

# I think this might be a mock bug...but things don't get umounted after the copyout
#sudo umount mock_chroot_tmpfs || echo "Unmount failed...this is OK"

# Pull the sourcerpm
yum --quiet clean headers packages metadata dbcache plugins expire-cache
yumdownloader --quiet --disablerepo="*" --enablerepo=building --source --config $WORKSPACE/workspace/yum.conf --destdir $WORKSPACE/workspace $PACKAGE

# extract version number from the dsc file
VERSION=`rpm --queryformat="%{VERSION}" -qp $WORKSPACE/workspace/*.src.rpm`
echo "package name ${PACKAGE} version ${VERSION}"

# Actually perform the mockbuild
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --rebuild $WORKSPACE/workspace/*.src.rpm

# Upload invalidate and add to the repo
UPLOAD_DIR=/tmp/upload/$PACKAGE/$DISTRO/$ARCH

# Remove the source RPM (that's already in the repo)
rm -f $WORKSPACE/output/*.src.rpm

ssh rosbuild@@$ROS_REPO_FQDN -- mkdir -p $UPLOAD_DIR
ssh rosbuild@@$ROS_REPO_FQDN -- rm -rf $UPLOAD_DIR/*
scp -r $WORKSPACE/output/*fc$DISTRO_VER*rpm rosbuild@@$ROS_REPO_FQDN:$UPLOAD_DIR
ssh rosbuild@@$ROS_REPO_FQDN -- PYTHONPATH=/home/rosbuild/rpmrepo_updater/src python /home/rosbuild/rpmrepo_updater/scripts/include_folder.py -f $UPLOAD_DIR --delete --invalidate -c

# check that the uploaded successfully
#sudo $CHECKOUT_DIR/scripts/assert_package_present.py $rootdir $aptconffile  $PACKAGE

# clean up work_dir to save space on the slaves
rm -rf $WORKSPACE/output
rm -rf $WORKSPACE/workspace

