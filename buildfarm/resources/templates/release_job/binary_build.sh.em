#!/bin/bash -x

#stop on error
set -o errexit

export ROSDISTRO_INDEX_URL=@(ROSDISTRO_INDEX_URL)
TARGET_REPOSITORY=@(TARGET_REPOSITORY)
ROS_REPO_FQDN=@(FQDN)
PACKAGE=@(PACKAGE)
distro=@(DISTRO)
arch=@(ARCH)
base=/var/cache/pbuilder-$distro-$arch


aptconffile=$WORKSPACE/apt.conf

#increment this value if you have changed something that will invalidate base tarballs. #TODO this will need cleanup eventually.
basetgz_version=6

rootdir=$base/apt-conf-$basetgz_version

basetgz=$base/base-$basetgz_version.tgz
output_dir=$WORKSPACE/output
work_dir=$WORKSPACE/work



if [ $arch == armel ] || [ $arch == armhf ]
then
    mirror=http://ports.ubuntu.com/ubuntu-ports
    debootstrap_type='qemu-debootstrap'
else
    mirror=http://us.archive.ubuntu.com/ubuntu
    debootstrap_type='debootstrap'
fi


CHECKOUT_DIR=$WORKSPACE/monitored_vcs

cd $CHECKOUT_DIR
. setup.sh

# monitor all subprocess and enforce termination, sleep to give python time to startup
sudo python $CHECKOUT_DIR/scripts/subprocess_reaper.py $$ &
sleep 1

#setup the cross platform apt environment
# using sudo since this is shared with pbuilder and if pbuilder is interupted it will leave a sudo only lock file.  Otherwise sudo is not necessary. 
# And you can't chown it even with sudo and recursive 
sudo PYTHONPATH=$PYTHONPATH $CHECKOUT_DIR/scripts/setup_apt_root.py $distro $arch $rootdir --local-conf-dir $WORKSPACE --mirror $mirror --repo "ros@@$APT_TARGET_REPOSITORY"

# update apt update
sudo apt-get update -c $aptconffile -o Apt::Architecture=$arch @(ARCH == 'armel' ? "-o Apt::Architectures::=armel") @(ARCH == 'armhf' ? "-o Apt::Architectures::=armhf")

# check precondition that all dependents exist, don't check if no dependencies
@[if DEPENDENTS]
sudo $CHECKOUT_DIR/scripts/assert_package_dependencies_present.py $rootdir $aptconffile  $PACKAGE
@[end if]

# verify we have a clean workspace and output directory
sudo rm -rf $output_dir
mkdir -p $output_dir

sudo rm -rf $work_dir
mkdir -p $work_dir
cd $work_dir


# Pull the sourcedeb
sudo apt-get source $PACKAGE -c $aptconffile

# extract version number from the dsc file
version=`ls *.dsc | sed s/${PACKAGE}_// | sed s/$distro\.dsc//`
echo "package name ${PACKAGE} version ${version}"


# Setup the pbuilder environment if not existing, or update
if [ ! -e $basetgz ] || [ ! -s $basetgz ] 
then
  #make sure the base dir exists
  sudo mkdir -p $base
  #create the base image
  sudo pbuilder create \
    --distribution $distro \
    --aptconfdir $rootdir/etc/apt \
    --basetgz $basetgz \
    --architecture $arch \
    --mirror $mirror \
    --keyring /etc/apt/trusted.gpg \
    --debootstrap $debootstrap_type \
    --debootstrapopts --arch=$arch \
    --debootstrapopts --keyring=/etc/apt/trusted.gpg
else
  sudo pbuilder --update --basetgz $basetgz
fi


# hooks for changing the binary debs to be timestamped
mkdir -p hooks

echo "#!/bin/bash -ex
echo \`env\`
cd /tmp/buildd/*/
apt-get install devscripts -y
prevversion=\`dpkg-parsechangelog | grep Version | awk '{print \$2}'\`
debchange -D $distro -v \$prevversion-\`date +%Y%m%d-%H%M-%z\` 'Time stamping.'
cat debian/changelog
" >> hooks/A50stamp
chmod +x hooks/A50stamp

#  --binary-arch even if "any" type debs produce arch specific debs
sudo pbuilder  --build \
    --basetgz $basetgz \
    --buildresult $output_dir \
    --debbuildopts \"-b\" \
    --hookdir hooks \
    *.dsc



# Upload invalidate and add to the repo
UPLOAD_DIR=/tmp/upload/${PACKAGE}_${distro}_$arch

ssh rosbuild@@$ROS_REPO_FQDN -- mkdir -p $UPLOAD_DIR
ssh rosbuild@@$ROS_REPO_FQDN -- rm -rf $UPLOAD_DIR/*
scp -r $output_dir/*$distro* rosbuild@@$ROS_REPO_FQDN:$UPLOAD_DIR
ssh rosbuild@@$ROS_REPO_FQDN -- PYTHONPATH=/home/rosbuild/reprepro_updater/src python /home/rosbuild/reprepro_updater/scripts/include_folder.py -d $distro -a $arch -f $UPLOAD_DIR -p $PACKAGE -c --delete --invalidate

# update apt again
sudo apt-get update -c $aptconffile -o Apt::Architecture=$arch @(ARCH == 'armel' ? "-o Apt::Architectures::=armel") @(ARCH == 'armhf' ? "-o Apt::Architectures::=armhf")

# check that the uploaded successfully
sudo $CHECKOUT_DIR/scripts/assert_package_present.py $rootdir $aptconffile  $PACKAGE

# clean up work_dir to save space on the slaves
cd $output_dir && sudo rm -rf $work_dir
