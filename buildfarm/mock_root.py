#!/usr/bin/env python

import em
import getopt
import os
from pkg_resources import resource_string
from platform import machine
from .fedora_vmap import fedora_ver
import sys

repos = {
    'building': 'http://csc.mcs.sdsmt.edu/smd-ros-building',
    # Staging should only be here until the packages are in the official Fedora repo
    'staging': 'http://csc.mcs.sdsmt.edu/smd-ros-staging'
}

def check_mock_config(distro, arch=machine(), use_ramdisk=True, quiet=False, output_dir='/tmp/mock_config', repos=repos):
    # General Stuff
    distro = fedora_ver[distro]
    mock_dir = os.path.normpath('/etc/mock')
    if not os.path.isdir(output_dir):
        os.mkdir(output_dir)
    if not os.path.lexists(os.path.join(output_dir, 'site-defaults.cfg')):
        os.symlink(os.path.join(mock_dir, 'site-defaults.cfg'), os.path.join(output_dir, 'site-defaults.cfg'))
    if not os.path.lexists(os.path.join(output_dir, 'logging.ini')):
        os.symlink(os.path.join(mock_dir, 'logging.ini'), os.path.join(output_dir, 'logging.ini'))

    if arch in ['srpm', 'src', 'source']:
        arch = machine()

    # Arch-specific config
    with open(os.path.join(mock_dir, 'fedora-%s-%s-rpmfusion_free.cfg' % (distro, arch)), 'r') as f:
        rpmfusion_free_cfg = f.read()

    mock_template = resource_string('buildfarm', 'resources/templates/mock.cfg.em')
    arch_config = em.expand(mock_template, **locals())

    user_arch_config = ""
    if os.path.exists(os.path.join(output_dir, 'fedora-%s-%s-ros.cfg'%(distro, arch))):
        with open(os.path.join(output_dir, 'fedora-%s-%s-ros.cfg'%(distro, arch)), 'r') as f:
            user_arch_config = f.read()

    if user_arch_config != arch_config:
        if not quiet:
            print('Updating ' + 'fedora-%s-%s-ros.cfg'%(distro, arch))
        with open(os.path.join(output_dir, 'fedora-%s-%s-ros.cfg'%(distro, arch)), 'w') as f:
            f.write(arch_config)

    # Done
    if not quiet:
        print('Mock configuration is OK in %s'%output_dir)

