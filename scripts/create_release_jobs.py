#!/usr/bin/env python

from __future__ import print_function
import argparse
import os
import tempfile
from subprocess import Popen, PIPE

from buildfarm import jenkins_support, release_jobs

from buildfarm.ros_distro import debianize_package_name

import rospkg.distro

try:
    from urllib.parse import urlsplit
except ImportError:
    from urlparse import urlsplit


def parse_options():
    parser = argparse.ArgumentParser(description='Create a set of jenkins jobs for source packages and binary packages for a catkin package.')
    parser.add_argument('--fqdn', dest='fqdn',
                        help='The source repo to push to, fully qualified something. Default: taken from distro-build.yaml, for Fuerte: repos.ros.org')
    parser.add_argument(dest='rosdistro',
                        help='The ros distro. fuerte, groovy, hydro, ...')
    parser.add_argument('--distros', nargs='+', default=[],
                        help='A list of platform distros. Default: %(default)s')
    parser.add_argument('--arches', nargs='+',
                        help='A list of platform architectures. Default: taken from distro-build.yaml, for Fuerte: [amd64, i386]')
    parser.add_argument('--commit', action='store_true', default=False,
                        help='Really?')
    parser.add_argument('--delete', action='store_true', default=False,
                        help='Delete extra jobs')
    parser.add_argument('--no-update', dest='skip_update', action='store_true', default=False,
                        help='Assume packages have already been downloaded')
    parser.add_argument('--wet-only', action='store_true', default=False,
                        help='Only setup wet jobs')
    parser.add_argument('--repo-workspace', action='store',
                        help='A directory into which all the repositories will be checked out into.')
    parser.add_argument('--repos', nargs='+',
                        help='A list of repository (or stack) names to create. Default: creates all')
    parser.add_argument('--ssh-key-id',
                        help="Jenkins SSH key ID for accessing the package server")
    parser.add_argument('--platform', default='ubuntu',
                        help='Linux platform (ubuntu, fedora)')
    args = parser.parse_args()
    if args.repos and args.delete:
        parser.error('A set of repos to create can not be combined with the --delete option.')

    if args.rosdistro == 'fuerte':
        if args.fqdn is None:
            args.fqdn = 'repos.ros.org'
        if args.arches is None:
            args.arches = ['amd64', 'i386']

    return args


def verify_heads(repo_uri, expected_head):
    expected_head = 'refs/heads/' + expected_head
    process = Popen(['git', 'ls-remote', '--heads', repo_uri], stdout=PIPE, stderr=PIPE)
    heads = process.communicate()[0]
    if not process.poll() == 0:
        tags = ""

    head_list = []
    for head in heads.split('\n'):
        if head != '':
            head_list += [head.split()[-1]]

    if expected_head in head_list:
        return expected_head
    #else:
    #    print("No matching head found. Are you sure you pointed to the right repository or the version is right?, expected %s:\nHeads:\n%s" % (expected_head, heads))
    return None


def doit(rd, distros, arches, target_repository, fqdn, jobs_graph, rosdistro, packages, dry_maintainers, commit=False, delete_extra_jobs=False, whitelist_repos=None, sourcepkg_timeout=None, binarypkg_timeout=None, ssh_key_id=None, platform='ubuntu'):
    jenkins_instance = None
    if args.commit or delete_extra_jobs:
        jenkins_instance = jenkins_support.JenkinsConfig_to_handle(jenkins_support.load_server_config_file(jenkins_support.get_default_catkin_debs_config()))

    # Figure out default distros.  Command-line arg takes precedence; if
    # it's not specified, then read targets.yaml.
    if distros:
        default_distros = distros
    else:
        default_distros = rd.get_target_distros()[platform]

    # TODO: pull arches from rosdistro
    target_arches = arches

    # We take the intersection of repo-specific targets with default
    # targets.
    results = {}

    for repo_name in sorted(rd.get_repo_list()):
        if whitelist_repos and repo_name not in whitelist_repos:
            continue

        r = rd.get_repo(repo_name)
        #todo add support for specific targets, needed in rosdistro.py too
        #if 'target' not in r or r['target'] == 'all':
        target_distros = default_distros
        #else:
        #    target_distros = list(set(r['target']) & set(default_distros))

        print('Configuring WET repo "%s" at "%s" for "%s"' % (r.name, r.url, target_distros))

        # TODO: Workaround until repos have rpm branches
        if platform == 'fedora':
            expected_branch = 'rpm/' + rosdistro + '/' + r.name
            if not verify_heads(r.url, expected_branch):
                temporary_url = '://github.com/smd-ros-rpm-release/%s-release.git' % r.name
                if verify_heads('git' + temporary_url, expected_branch):
                    r.url = 'https' + temporary_url
                    print('- using workaround URL since no RPM branch exists: %s' % r.url)
                else:
                    print('- skipping all of "%s" since no RPM branch or workaround repo exist' % r.name)
                    continue
        # End workaround

        for p in sorted(r.packages.iterkeys()):
            if not r.version:
                print('- skipping "%s" since version is null' % p)
                continue
            pkg_name = rd.debianize_package_name(p)
            results[pkg_name] = release_jobs.doit(r.url,
                                                  pkg_name,
                                                  packages[p],
                                                  target_distros,
                                                  target_arches,
                                                  target_repository,
                                                  fqdn,
                                                  jobs_graph,
                                                  rosdistro=rosdistro,
                                                  short_package_name=p,
                                                  commit=commit,
                                                  jenkins_instance=jenkins_instance,
                                                  sourcepkg_timeout=sourcepkg_timeout,
                                                  binarypkg_timeout=binarypkg_timeout,
                                                  ssh_key_id=ssh_key_id,
                                                  platform=platform)
            #time.sleep(1)
            #print ('individual results', results[pkg_name])

    if args.wet_only:
        print("wet only selected, skipping dry and delete")
        return results

    if rosdistro == 'backports' or platform == 'fedora':
        print("No dry backports support")
        return results

    if rosdistro == 'fuerte':
        packages_for_sync = 300
    elif rosdistro == 'groovy':
        packages_for_sync = 740
    elif rosdistro == 'hydro':
        packages_for_sync = 865
    elif rosdistro == 'indigo':
        packages_for_sync = 1
    else:
        packages_for_sync = 10000

    if rosdistro == 'groovy':
        #dry stacks
        # dry dependencies
        d = rospkg.distro.load_distro(rospkg.distro.distro_uri(rosdistro))

        for s in sorted(d.stacks.iterkeys()):
            if whitelist_repos and s not in whitelist_repos:
                continue
            print("Configuring DRY job [%s]" % s)
            if not d.stacks[s].version:
                print('- skipping "%s" since version is null' % s)
                continue
            results[rd.debianize_package_name(s)] = release_jobs.dry_doit(s, dry_maintainers[s], default_distros, target_arches, fqdn, rosdistro, jobgraph=jobs_graph, commit=commit, jenkins_instance=jenkins_instance, packages_for_sync=packages_for_sync, ssh_key_id=ssh_key_id)
            #time.sleep(1)

    # special metapackages job
    if not whitelist_repos or 'metapackages' in whitelist_repos:
        results[rd.debianize_package_name('metapackages')] = release_jobs.dry_doit('metapackages', [], default_distros, target_arches, fqdn, rosdistro, jobgraph=jobs_graph, commit=commit, jenkins_instance=jenkins_instance, packages_for_sync=packages_for_sync, ssh_key_id=ssh_key_id)

    if not whitelist_repos or 'sync' in whitelist_repos:
        results[rd.debianize_package_name('sync')] = release_jobs.dry_doit('sync', [], default_distros, target_arches, fqdn, rosdistro, jobgraph=jobs_graph, commit=commit, jenkins_instance=jenkins_instance, packages_for_sync=packages_for_sync, ssh_key_id=ssh_key_id)

    if delete_extra_jobs:
        assert(not whitelist_repos)
        # clean up extra jobs
        configured_jobs = set()

        for jobs in results.values():
            release_jobs.summarize_results(*jobs)
            for e in jobs:
                configured_jobs.update(set(e))

        existing_jobs = set([j['name'] for j in jenkins_instance.get_jobs()])
        relevant_jobs = existing_jobs - configured_jobs
        relevant_jobs = [j for j in relevant_jobs if rosdistro in j and ('_sourcedeb' in j or '_binarydeb' in j)]

        for j in relevant_jobs:
            print('Job "%s" detected as extra' % j)
            if commit:
                jenkins_instance.delete_job(j)
                print('Deleted job "%s"' % j)

    return results


if __name__ == '__main__':
    args = parse_options()

    print('Loading rosdistro %s' % args.rosdistro)

    workspace = args.repo_workspace
    if not workspace:
        workspace = os.path.join(tempfile.gettempdir(), 'repo-workspace-%s' % args.rosdistro)

    if args.rosdistro != 'fuerte':
        from buildfarm.ros_distro import Rosdistro
        rd = Rosdistro(args.rosdistro)
        from buildfarm import dependency_walker
        packages = dependency_walker.get_packages(workspace, rd, skip_update=args.skip_update)
        dependencies = dependency_walker.get_jenkins_dependencies(args.rosdistro, packages)

        # TODO does only work with one build file
        build_config = rd._build_files[0].get_target_configuration()
        target_repository = build_config['apt_target_repository']
        # TODO Building URL Workaround
        if not args.platform == 'ubuntu':
            target_repository = os.path.join(target_repository, args.platform)
        # End Workaround
        if args.fqdn is None:
            fqdn_parts = urlsplit(target_repository)
            args.fqdn = fqdn_parts.netloc
        if args.arches is None:
            args.arches = rd.get_arches()

        # TODO Fedora Arch Workaround
        if 'amd64' in args.arches:
            args.arches.remove('amd64')
            args.arches.append('x86_64',)
        # End Workaround

        # TODO does only work with one build file
        sourcepkg_timeout = rd._build_files[0].jenkins_sourcedeb_job_timeout
        binarypkg_timeout = rd._build_files[0].jenkins_binarydeb_job_timeout
    else:
        target_repository = 'http://' + args.fqdn + '/repos/building'
        from buildfarm.ros_distro_fuerte import Rosdistro
        rd = Rosdistro(args.rosdistro)
        from buildfarm import dependency_walker_fuerte
        stacks = dependency_walker_fuerte.get_stacks(workspace, rd._repoinfo, args.rosdistro, skip_update=args.skip_update)
        dependencies = dependency_walker_fuerte.get_dependencies(args.rosdistro, stacks)
        packages = stacks
        sourcepkg_timeout = None
        binarypkg_timeout = None

    release_jobs.check_for_circular_dependencies(dependencies)

    if args.rosdistro == 'groovy':
        # even for wet_only the dry packages need to be consider, else they are not added as downstream dependencies for the wet jobs
        stack_depends, dry_maintainers = release_jobs.dry_get_stack_dependencies(args.rosdistro)
        dry_jobgraph = release_jobs.dry_generate_jobgraph(args.rosdistro, dependencies, stack_depends)
    else:
        stack_depends, dry_maintainers = {}, {}
        dry_jobgraph = {}

    combined_jobgraph = {}
    for k, v in dependencies.iteritems():
        combined_jobgraph[k] = v
    for k, v in dry_jobgraph.iteritems():
        combined_jobgraph[k] = v

    # setup a job triggered by all other debjobs
    combined_jobgraph[debianize_package_name(args.rosdistro, 'metapackages')] = combined_jobgraph.keys()
    combined_jobgraph[debianize_package_name(args.rosdistro, 'sync')] = [debianize_package_name(args.rosdistro, 'metapackages')]

    results_map = doit(
        rd,
        args.distros,
        args.arches,
        target_repository,
        args.fqdn,
        combined_jobgraph,
        rosdistro=args.rosdistro,
        packages=packages,
        dry_maintainers=dry_maintainers,
        commit=args.commit,
        delete_extra_jobs=args.delete,
        whitelist_repos=args.repos,
        sourcepkg_timeout=sourcepkg_timeout,
        binarypkg_timeout=binarypkg_timeout,
        ssh_key_id=args.ssh_key_id,
        platform=args.platform)

    if not args.commit:
        print('This was not pushed to the server.  If you want to do so use "--commit" to do it for real.')
