# -*- coding: utf8 -*-
fedora_ver = {u'schrödinger’s': 19,
               'heisenbug': 20}
fedora_rel = {v: k for k, v in fedora_ver.items()}

def get_fedora_key(v):
    if v > 20:
        return '%s' % (v,)
    else:
        return fedora_rel[v]

def get_fedora_ver(v):
    if v.isdigit():
        return int(v)
    else:
        return fedora_ver[v]
