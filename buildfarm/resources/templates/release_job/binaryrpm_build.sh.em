#!/bin/bash -x -e

TARGET_REPOSITORY=@(TARGET_REPOSITORY)
ROS_REPO_FQDN=@(FQDN)
PACKAGE=@(PACKAGE)
DISTRO=@(DISTRO)
DISTRO_VER=@(DISTRO_VER)
ARCH=@(ARCH)
RET=0

# When mock uses tmpfs for builds, it sometimes doesn't dismount properly.
# There are other scenarios where dismounting doesn't happen, such as an
# aborted build. This will ensure that the tmpfs isn't mounted.
check_umount_mock_root ()
{
MOCK_ROOT=$(/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --print-root-path | sed 's/\/root\///')
CMOUNTS=$(mount | awk '{ print $3 }' | grep ^$MOCK_ROOT | tr "\n" " " || echo '')
if [ "$CMOUNTS" != "" ]; then
	sudo umount $CMOUNTS || echo "WARNING: umount failed"
fi
}

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
MOCK_CONF_DIR=`$WORKSPACE/monitored_vcs/scripts/configure_mock heisenbug --get-default-output-dir`
$WORKSPACE/monitored_vcs/scripts/configure_mock @(DISTRO) --arch @(ARCH) --use-ramdisk --base fedora-%\(distro\)s-%\(arch\)s-rpmfusion_nonfree-local.cfg
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --scrub=yum-cache
check_umount_mock_root
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --init || RET=$?

if [ $RET -ne 0 ]; then
  echo ""
  echo "BEGIN ROOT LOG"
  echo ""
  cat $WORKSPACE/output/root.log
  echo ""
  echo "END ROOT LOG"
  echo ""
  exit $RET
fi

/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --copyout /etc/yum.conf $WORKSPACE/workspace/

# Pull the sourcerpm
yum --quiet clean headers packages metadata dbcache plugins expire-cache
yumdownloader --quiet --disablerepo="*" --enablerepo=building --source --config $WORKSPACE/workspace/yum.conf --destdir $WORKSPACE/workspace $PACKAGE

# Extract version number from the srpm
VERSION=`rpm --queryformat="%{VERSION}-%{RELEASE}" -qp $WORKSPACE/workspace/*.src.rpm | sed 's/\.fc[0-9][0-9]*//'`
echo "package name ${PACKAGE} version ${VERSION}"

# Actually perform the mockbuild
check_umount_mock_root
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --rebuild $WORKSPACE/workspace/*.src.rpm || RET=$?

# Kill any lingering processes (important if we're in a tmpfs)
/usr/bin/mock --quiet --configdir $MOCK_CONF_DIR --root fedora-$DISTRO_VER-$ARCH-ros --resultdir $WORKSPACE/output --orphanskill

# Output the build log for stability testing
echo ""
echo "BEGIN BUILD LOG"
echo ""
cat $WORKSPACE/output/build.log
echo ""
echo "END BUILD LOG"
echo ""

if [ $RET -ne 0 ]; then
  exit $RET
else
  echo -n "Build finished: "
  date
fi

# Remove the source RPM (that's already in the repo)
rm -f $WORKSPACE/output/*.src.rpm

# Run rpmlint (for stability testing)
rpmlint $WORKSPACE/output/*.rpm 2>&1 | grep -v -e dir-or-file-in-opt -e devel-file-in-non-devel-package -e no-documentation || true

# Ensure package.xml is installed
rpm -qlp $WORKSPACE/output/*.rpm | grep -q package.xml$ || echo "WARNING: package.xml not present in RPM"

# Upload invalidate and add to the repo
UPLOAD_DIR=/mnt/storage/upload_temp/$PACKAGE/$DISTRO_VER/$ARCH

ssh rosbuild@@$ROS_REPO_FQDN -- mkdir -p $UPLOAD_DIR
ssh rosbuild@@$ROS_REPO_FQDN -- rm -rf $UPLOAD_DIR/*
scp -r $WORKSPACE/output/*fc$DISTRO_VER*rpm rosbuild@@$ROS_REPO_FQDN:$UPLOAD_DIR
ssh rosbuild@@$ROS_REPO_FQDN -- PYTHONPATH=/home/rosbuild/rpmrepo_updater/src python /home/rosbuild/rpmrepo_updater/scripts/update_trigger.py -f $UPLOAD_DIR --delete

# check that the uploaded successfully
#sudo $CHECKOUT_DIR/scripts/assert_package_present.py $rootdir $aptconffile  $PACKAGE

echo -n "Upload finished: "
date

# clean up work_dir to save space on the slaves
rm -rf $WORKSPACE/output
rm -rf $WORKSPACE/workspace
