#!/bin/bash -x -e
RELEASE_URI=@(RELEASE_URI)
FQDN=@(FQDN)
PACKAGE=@(PACKAGE)
ROSDISTRO=@(ROSDISTRO)
SHORT_PACKAGE_NAME=@(SHORT_PACKAGE_NAME)
RET=0

cd $WORKSPACE/monitored_vcs
. setup.sh

# Verify a clean workspace and output directory
rm -rf $WORKSPACE/output
rm -rf $WORKSPACE/workspace

$WORKSPACE/monitored_vcs/scripts/generate_sourcerpm $RELEASE_URI $PACKAGE $ROSDISTRO $SHORT_PACKAGE_NAME --working $WORKSPACE/workspace --output $WORKSPACE/output --repo-fqdn $FQDN --base-mock-cfg fedora-%\(distro\)s-%\(arch\)s-local.cfg || RET=$?

# clean up the workspace to save disk space
rm -rf $WORKSPACE/workspace
exit $RET
