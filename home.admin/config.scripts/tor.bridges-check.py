#!/usr/bin/python3

# This file is part of TorBox, an easy to use anonymizing router based on Raspberry Pi.
# Copyright (C) 2021 Patrick Truffer
# Contact: anonym@torbox.ch
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it is useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# DESCRIPTION
# This file checks the status of a bridge. Possible return values are:
# 0: bridge exists and is offline
# 1: bridge exists and is online
# 2: bridge doesn't exist
#
# This program uses the Onionoo protocol - for more information go to: https://metrics.torproject.org/onionoo.html
#
# SYNTAX
# ./tor.bridges-check.py [-i] -f <fingerprint> [-s] [--info file_name] [-h]
#
# -h: print the help screen
# --help: print the help screen
# -f <fingerprint>: search with the fingerprint
# -f <fingerprint> -s: search with the hashed fingerprint
# -f <fingerprint> -i: search with the fingerprint and print extended information on stdout
# -f <fingerprint> -s -i: search with the hashed fingerprint and print extended information on stdout
# -f <fingerprint> --info file_name: search with the fingerprint and save the extended information into file_name
# -f <fingerprint> -s --info file_name: search with the hashed fingerprint and save the extended information into file_name

import sys
import getopt
import requests
import json

from binascii import a2b_hex
from hashlib import sha1

# get the options from cmd line
options, remainder = getopt.getopt(sys.argv[1:], 'f:ish', ['fingerprint=',
                                                        'info=',
                                                        'help',
                                                        'hashed-fingerprint'
                                                        ])
fingerprint = False
hashed_fingerprint = False
get_info_file = False
show_info = False

for opt, arg in options:
    if opt in ('-f', '--fingerprint'):
        fingerprint = arg
    elif opt in ('-i', '--info'):
        if arg == '':
            show_info = True
        get_info_file = arg
    elif opt in ('-s', '--hashed-fingerprint'):
        hashed_fingerprint = True
    elif opt in ('-h', '--help'):
        print("Usage:\n %s [-i] -f <fingerprint>\n\nOptions:\n -f, --fingerprint=<fingerprint>\tGet status of a tor bridge (0: offline, 1: online, 2: not exists) [REQUIRED PARAM]\n\t\t\t\t\t Fingerprint must not be hashed\n -s, --hashed-fingerprint\t\tSearch for hashed fingerprint\n -i, --info <file_name>\t\t\tSave the info from bridge and save to file in JSON format (-i prints to stdout)\n -h, --help\t\t\t\tshow this help\n" % sys.argv[0])
        quit()

# if fingerprint not passed, we show how to use it. fingerprint is required
if not fingerprint:
    print("Usage: %s -f <fingerprint>\nCheck '%s --help' for more info" % (sys.argv[0], sys.argv[0]) )
    quit()

# if fingerprint is not hashed, we hash it before search
if not hashed_fingerprint:
    try:
        fingerprint = sha1(a2b_hex(fingerprint)).hexdigest()
    except:
        print("[X] Fingerprint format error")
        quit()

# search for the fingerprint in the torproject
url = 'https://onionoo.torproject.org/details?lookup=%s' % fingerprint
r = requests.get(url)

# load json data
data = json.loads(r.text)

# if we get bridges, then it exist
if len(data['bridges']):
    b = data['bridges'][0]

    # get the info of existing one to file
    if get_info_file:
        f = open(get_info_file, 'w')
        f.write("{}".format(b))
        f.close()

    # Running
    if b['running']:
        res = 1 # ONLINE
    # Not running
    else:
        res = 0 # OFFLINE

    if show_info:
        print("%s:{}".format(b) % (res))
    else:
        print(res)

# else it doesn't exist
else:
    print(2) # NOT EXIST
