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

def get_default_confdir():
    return os.path.join(os.path.expanduser('~'), '.mock_config')

def check_mock_config(distro, arch=machine(), use_ramdisk=True, quiet=False, output_dir=get_default_confdir(), repos=repos):
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
        suffix = 'rossrc'
        with open(os.path.join(mock_dir, 'fedora-%s-%s.cfg' % (distro, arch)), 'r') as f:
            base_cfg = f.read()
    else:
        suffix = 'ros'
        with open(os.path.join(mock_dir, 'fedora-%s-%s-rpmfusion_free.cfg' % (distro, arch)), 'r') as f:
            base_cfg = f.read()


    mock_template = resource_string('buildfarm', 'resources/templates/mock.cfg.em')
    arch_config = em.expand(mock_template, **locals())

    user_arch_config = ""
    if os.path.exists(os.path.join(output_dir, 'fedora-%s-%s-%s.cfg'%(distro, arch, suffix))):
        with open(os.path.join(output_dir, 'fedora-%s-%s-%s.cfg'%(distro, arch, suffix)), 'r') as f:
            user_arch_config = f.read()

    if user_arch_config != arch_config:
        if not quiet:
            print('Updating ' + 'fedora-%s-%s-%s.cfg'%(distro, arch, suffix))
        with open(os.path.join(output_dir, 'fedora-%s-%s-%s.cfg'%(distro, arch, suffix)), 'w') as f:
            f.write(arch_config)

    # Done
    if not quiet:
        print('Mock configuration is OK in %s'%output_dir)

