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
from time import sleep

url_re = re.compile('(http|https|git|ssh)://(git@)?github\.com[:/]([^/]*)/(.*)')

def parse_options():
    parser = argparse.ArgumentParser(description='Verifies GitHub workaround release repositories')
    parser.add_argument(dest='key',
                        help='Github OAuth key to authenticate using.')
    parser.add_argument(dest='rosdistro',
                        help='The ros distro. fuerte, groovy, hydro, ...')
    parser.add_argument('--org', dest='org', default='smd-ros-rpm-release',
                        help='GitHub organization to check for workaround repos within. Default: smd-ros-rpm-release')
    parser.add_argument('--repos', nargs='+',
                        help='A list of repository (or stack) names to verify. Default: forks all')

    args = parser.parse_args()
    return args

def verify_branch(repo, rosdistro=None):
    expected_branch = 'rpm/' if not rosdistro else 'rpm/%s/' % (rosdistro,)
    for b in repo.get_branches():
        if b.name.startswith(expected_branch):
            return True
    return False

def verify_tag(repo, rosdistro, package, version):
    expected_tag = 'rpm/ros-%s-%s-%s_' % (rosdistro, package.lower().replace('_', '-'), version)
    for t in repo.get_tags():
        if t.name.startswith(expected_tag):
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

    num_valid_release = 0
    num_valid_workaround = 0
    num_invalid_workaround = 0
    num_missing_workaround = 0
    num_total = 0
    num_failed = 0

    for repo_name in sorted(rd.get_repo_list()):
        if args.repos and repo_name not in args.repos:
            continue

        r = rd.get_repo(repo_name)

        if not r.full_version:
            continue

        print('%s %s:' % (r.name, r.full_version))

        num_total += 1

        r_re = re.match(url_re, r.url)
        if not r_re:
            print('- unable to parse URL')
            num_failed += 1
            continue

        real_org = r_re.group(3)
        real_name = r_re.group(4)[0:-4] if r_re.group(4).endswith('.git') else r_re.group(4)
        real_ver = r.full_version.split('-')[0]
        real_rel = r.full_version.split('-')[1]

        sys.stdout.write('- checking real repo...')
        sys.stdout.flush()
        try:
            real_repo = gh.get_repo('%s/%s' % (real_org, real_name))
        except:
            print('\033[91mfailed!\033[0m')
            num_failed += 1
            continue
        else:
            print('done')

        # Check real repo for an RPM branch in our rosdistro
        try:
            if verify_tag(real_repo, args.rosdistro, r.packages.keys()[0], r.full_version):
                print('- \033[92malready has valid release repo\033[0m')
                num_valid_release += 1
                continue
        except ssl.SSLError:
            print('\033[91mfailed to verify release repo!\033[0m')
            num_failed += 1
            continue

        # Check for a workaround repo
        if real_name not in gh_org_repos:
            try:
                gh_org_repos[real_name] = gh_org.get_repo(real_name)
            except UnknownObjectException:
                # Workaround repo doesn't exist
                print('- \033[91mno valid workaround repo\033[0m')
                num_missing_workaround += 1
                continue

        if verify_tag(gh_org_repos[real_name], args.rosdistro, r.packages.keys()[0], r.full_version):
            print('- \033[93malready has valid workaround repo\033[0m')
            num_valid_workaround += 1
            continue

        if verify_branch(gh_org_repos[real_name], args.rosdistro):
            print('- \033[95mworkaround repo exists, but the current tag is out of date\033[0m')
            num_invalid_workaround += 1
        else:
            print('- \033[94mworkaround repo exists, but no valid branches\033[0m')
            num_invalid_workaround += 1

    if num_total == 0:
        num_total = 0.0000001

    print('')
    print('Summary:')
    print('- \033[92mvalid release repo:\033[0m %d (%01.1f%%)' % (num_valid_release, 100.0 * num_valid_release / num_total))
    print('- \033[93mvalid workaround repo:\033[0m %d (%01.1f%%)' % (num_valid_workaround, 100.0 * num_valid_workaround / num_total))
    print('- \033[95minvalid workaround repo:\033[0m %d (%01.1f%%)' % (num_invalid_workaround, 100.0 * num_invalid_workaround / num_total))
    print('- \033[91mmissing workaround repo:\033[0m %d (%01.1f%%)' % (num_missing_workaround, 100.0 * num_missing_workaround / num_total))
    print('- \033[91mfailures:\033[0m %d (%01.1f%%)' % (num_failed, 100.0 * num_failed / num_total))
    print('- total: %d' % (num_total,))
