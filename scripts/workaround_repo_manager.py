#!/usr/bin/env python

import argparse
import github
import re
import shutil
import subprocess
import sys
import tempfile

from buildfarm.ros_distro import Rosdistro
from github.GithubException import UnknownObjectException

url_re = re.compile('(http|https|git|ssh)://(git@)?github\.com[:/]([^/]*)/(.*)')

def parse_options():
    parser = argparse.ArgumentParser(description='Manages GitHub workaround release repositories')
    parser.add_argument(dest='key',
                        help='Github OAuth key to authenticate using.')
    parser.add_argument(dest='rosdistro',
                        help='The ros distro. fuerte, groovy, hydro, ...')
    parser.add_argument('--org', dest='org', default='smd-ros-rpm-release',
                        help='GitHub organization to fork the repositories into. Default: smd-ros-rpm-release')
    parser.add_argument('--repos', nargs='+',
                        help='A list of repository (or stack) names to create. Default: forks all')

    args = parser.parse_args()
    return args

def verify_branch(repo, rosdistro=None):
    expected_branch = 'rpm/' if not rosdistro else 'rpm/%s/' % (rosdistro,)
    for b in repo.get_branches():
        if b.name.startswith(expected_branch):
            return True
    return False

if __name__ == '__main__':
    args = parse_options()

    sys.stdout.write('loading rosdistro...')
    sys.stdout.flush()
    rd = Rosdistro(args.rosdistro)
    print('got %s' % (rd._rosdistro,))

    print('connecting to GitHub:')
    gh = github.Github(args.key)
    sys.stdout.write('- getting user...')
    sys.stdout.flush()
    gh_user = gh.get_user()
    print('got %s' % gh_user.login)
    sys.stdout.write('- getting org...')
    sys.stdout.flush()
    gh_org = gh.get_organization(args.org)
    print('got %s' % gh_org.login)
    if not args.repos:
        sys.stdout.write('- getting org\'s repo list...')
        sys.stdout.flush()
        gh_org_repos = dict((r.name, r) for r in gh_org.get_repos())
        print('got %d' % len(gh_org_repos))
    else:
        gh_org_repos = dict()

    print('')

    for repo_name in sorted(rd.get_repo_list()):
        if args.repos and repo_name not in args.repos:
            continue

        r = rd.get_repo(repo_name)
        print('%s %s:' % (r.name, r.full_version))

        r_re = re.match(url_re, r.url)
        if not r_re:
            print('- unable to parse URL')
            continue

        real_org = r_re.group(3)
        real_name = r_re.group(4)[0:-4] if r_re.group(4).endswith('.git') else r_re.group(4)
        real_repo = gh.get_repo('%s/%s' % (real_org, real_name))
        real_ver = r.full_version.split('-')[0]
        real_rel = r.full_version.split('-')[1]

        # Check real repo for an RPM branch in our rosdistro
        if verify_branch(real_repo, args.rosdistro):
            print('- already has valid release repo')
            continue

        # Check for a workaround repo
        if real_name not in gh_org_repos:
            try:
                gh_org_repos[real_name] = gh_org.get_repo(real_name)
            except UnknownObjectException:
                # Workaround repo doesn't exist, so fork it
                sys.stdout.write('- forking...')
                sys.stdout.flush()
                gh_org_repos[real_name] = gh_org.create_fork(real_repo)
                print('done')

        if verify_branch(gh_org_repos[real_name], args.rosdistro):
            print('- already has valid workaround repo')
            continue

        temp_dir = tempfile.mkdtemp()
        sys.stdout.write('- cloning into %s...' % (temp_dir,))
        sys.stdout.flush()
        try:
            subprocess.check_call(['git', 'clone', '--quiet', gh_org_repos[real_name].ssh_url, temp_dir])
            print('done')

            sys.stdout.write('- generating RPM branch...')
            sys.stdout.flush()
            subprocess.check_call('cd %s && git-bloom-generate -y rosrpm --prefix release/%s %s --unsafe -i %s >> /dev/null' % (temp_dir, args.rosdistro, args.rosdistro, real_rel), shell=True)
            print('done')

            sys.stdout.write('- pushing back to GitHub...')
            sys.stdout.flush()
            subprocess.check_call('cd %s && git push --quiet --all && git push --quiet --tags' % (temp_dir,), shell=True)
            print('done')
        except:
            print('failed!')

        if temp_dir:
            sys.stdout.write('- removing %s...' % (temp_dir,))
            shutil.rmtree(temp_dir)
            print('done')

