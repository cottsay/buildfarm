@(base_cfg)

config_opts['root'] += '-@(suffix)'

config_opts['plugin_conf']['tmpfs_enable'] = @[if use_ramdisk]True@[else]False@[end if]
config_opts['plugin_conf']['tmpfs_opts']['required_ram_mb'] = 4096
config_opts['plugin_conf']['tmpfs_opts']['max_fs_size'] = '20G'

config_opts['yum.conf'] += """
@[for r in repos]
[@(r)]
name=@(r)
baseurl=@(repos[r])/fedora/linux/@(distro)/@(arch)/
metadata_expire=1
keepcache=0
http_caching=none

[@(r)-debug]
name=@(r)-debug
baseurl=@(repos[r])/fedora/linux/@(distro)/@(arch)/debug/
metadata_expire=1
keepcache=0
http_caching=none
enabled=0

[@(r)-source]
name=@(r)-source
baseurl=@(repos[r])/fedora/linux/@(distro)/SRPMS/
metadata_expire=1
keepcache=0
http_caching=none
enabled=0
@[end for]
"""

