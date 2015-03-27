%include /usr/share/spin-kickstarts/fedora-live-desktop.ks
%include /usr/share/spin-kickstarts/fedora-live-minimization.ks

part / --size 5120

repo --name=rpmfusion-free --mirrorlist=http://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-$releasever&arch=$basearch
repo --name=rpmfusion-free-updates --mirrorlist=http://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-updates-released-$releasever&arch=$basearch
repo --name=rpmfusion-nonfree --mirrorlist=http://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-$releasever&arch=$basearch
repo --name=rpmfusion-nonfree-updates --mirrorlist=http://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-updates-released-$releasever&arch=$basearch
repo --name=smd-pub --baseurl=http://csc.mcs.sdsmt.edu/smd-pub/fedora/linux/$releasever/$basearch
repo --name=smd-ros --baseurl=http://csc.mcs.sdsmt.edu/smd-ros/fedora/linux/$releasever/$basearch

firewall --disable

%packages

rpmfusion-free-release
rpmfusion-nonfree-release
smd-ros-release
@(ros_pkgs)

# Slimming
-@@dial-up
-@@libreoffice
-@@multimedia
-@@printing
-evolution*
-abrt*
-rhythmbox*
-totem*

%end
