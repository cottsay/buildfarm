#!/usr/bin/env python

from __future__ import print_function

import gzip
import logging
import os
import socket
from StringIO import StringIO
import time
import urllib2
from xml.dom import minidom
import yaml

from rospkg.distro import distro_uri
from apt_data import RosdistroVersion, load_url

from fedora_vmap import fedora_ver

def get_version_data(rootdir, rosdistro_name, ros_repos, distro_arches, update_cache=True):
    rosdistro_data = RosdistroData(rosdistro_name)

    rpm_data = RpmData(rosdistro_name)

    # repo type (building, shadow-fixed, ros)
    for repo_type in ros_repos:
        for d in set([d for (d, a) in distro_arches]):
            # download list of source packages
            da_str = "SRPMS/%s" % fedora_ver[d]
            url = os.path.join(ros_repos[repo_type], 'linux/%s/SRPMS' % fedora_ver[d])
            datafile = fetch_primary_xml_file(rootdir, repo_type, da_str, url, reuse_existing=not update_cache)
            # extract information
            rpm_data.fill_versions_xml(repo_type, d, 'source', datafile)

        for (d, a) in distro_arches:
            # download list of binary packages
            da_str = "%s/%s" % (a, fedora_ver[d])
            url = os.path.join(ros_repos[repo_type], 'linux/%s/%s' % (fedora_ver[d], a))
            datafile = fetch_primary_xml_file(rootdir, repo_type, da_str, url, reuse_existing=not update_cache)
            # extract information
            rpm_data.fill_versions_xml(repo_type, d, a, datafile)

    return rosdistro_data, rpm_data


class RosdistroData(object):

    def __init__(self, rosdistro_name):
        self.packages = {}
        from buildfarm.ros_distro import Rosdistro
        # for fuerte we still fetch the new groovy rosdistro to get a list of distros
        rd = Rosdistro(rosdistro_name if rosdistro_name != 'fuerte' else 'groovy')
        self.rosdistro_index = rd._index
        self.rosdistro_dist = rd._dist

        # load wet rosdistro packages
        if rosdistro_name == 'fuerte':
            from buildfarm.ros_distro_fuerte import Rosdistro as RosdistroFuerte
            rd = RosdistroFuerte(rosdistro_name)

        for pkg_name in rd.get_package_list():
            version = rd.get_version(pkg_name, full_version=True)
            if version:
                self.packages[pkg_name] = RosdistroVersion(pkg_name, 'wet', version)

        # load dry rosdistro stacks
        if rosdistro_name == 'groovy':
            dry_yaml = yaml.load(urllib2.urlopen(distro_uri(rosdistro_name)))
            stacks = dry_yaml['stacks'] or {}
            for stack_name, d in stacks.items():
                if stack_name == '_rules':
                    continue
                version = d.get('version')
                if version:
                    if stack_name in self.packages:
                        logging.warn("Stack '%s' exists in dry (%s) as well as in wet (%s) distro. Ignoring dry package." % (stack_name, version, self.packages[stack_name].version))
                        continue
                    self.packages[stack_name] = RosdistroVersion(stack_name, 'dry', version)

            # load variants
            variants = dry_yaml['variants'] or {}
            for variant in variants:
                if len(variant) != 1:
                    logging.warn("Not length 1 dict in variant '%s': skipping" % variant)
                    continue
                variant_name = variant.keys()[0]
                if variant_name in self.packages:
                    logging.warn("Variant '%s' exists also as a package in %s. Ignoring variant." % (variant_name, self.packages[variant_name].type))
                    continue
                self.packages[variant_name] = RosdistroVersion(variant_name, 'variant', '1.0.0')


class RpmData(object):
    def __init__(self, rosdistro_name):
        self.rosdistro_name = rosdistro_name
        self.rpm_packages = {}

    def get_packages(self):
        return self.rpm_packages

    def get_version(self, rpm_name, repo_type, distro_arch):
        if not rpm_name in self.rpm_packages:
            return None
        return self.rpm_packages[rpm_name].get_version(repo_type, distro_arch)

    def fill_versions_xml(self, repo_type, distro, arch, datafile):
        """
        Extract information from rpm primary.xml files and fill in the versions.
        """
        logging.debug('Reading file: %s' % datafile)
        data = {}
        # split package blocks
        with open(datafile, 'r') as f:
            pkgdb = minidom.parseString(f.read())

        for pkg in pkgdb.getElementsByTagName('package'):
            if pkg.getAttribute('type') != 'rpm':
                continue
            rpm_name = pkg.getElementsByTagName('name')[0].firstChild.data
            rpm_version_obj = pkg.getElementsByTagName('version')[0]
            rpm_version = rpm_version_obj.getAttribute('ver') + '-' + rpm_version_obj.getAttribute('rel')
            if rpm_name not in self.rpm_packages:
                self.rpm_packages[rpm_name] = RpmVersion(rpm_name)
            self.rpm_packages[rpm_name].add_version(repo_type, '%s_%s' % (distro, arch), rpm_version)


class RpmVersion(object):

    def __init__(self, rpm_name):
        self.rpm_name = rpm_name
        self._versions = {}

    def add_version(self, repo_type, distro_arch, version):
        self._versions[(repo_type, distro_arch)] = version

    def get_version(self, repo_type, distro_arch):
        return self._versions.get((repo_type, distro_arch), None)


def parse_primary(repomd_str):
    for data_entry in minidom.parseString(repomd_str).getElementsByTagName('data'):
        if data_entry.getAttribute('type') == 'primary':
            return data_entry.getElementsByTagName('location')[0].getAttribute('href')


def fetch_primary_xml_file(rootdir, repo_type, da_str, url, reuse_existing=False):
    path = os.path.join(rootdir, da_str, repo_type)
    gen_path = os.path.join(path, 'gen')
    if not os.path.exists(gen_path):
        os.makedirs(gen_path)
    primary_path = os.path.join(gen_path, 'primary.xml')
    if not reuse_existing or not os.path.exists(primary_path):
        logging.debug('Downloading RPM repomd file: %s' % url)
        repomd_str = load_url(os.path.join(url, 'repodata', 'repomd.xml'))
        #repomd_path = os.path.join(gen_path, 'repomd.xml')
        #with open(repomd_path, 'w') as f:
        #    f.write(repomd_str)
        primary_gz_name = parse_primary(repomd_str)
        primary_gz_str = load_url(os.path.join(url, primary_gz_name))
        #primary_gz_path = os.path.join(path, os.path.basename(primary_gz_name))
        #with open(primary_gz_path, 'wb') as f:
        #    f.write(primary_gz_str)
        primary_gz_stream = StringIO(primary_gz_str)
        g = gzip.GzipFile(fileobj=primary_gz_stream, mode='rb')
        with open(primary_path, 'w') as f:
            f.write(g.read())
    else:
        logging.debug('Reuse RPM list file: %s' % primary_path)
    return primary_path
