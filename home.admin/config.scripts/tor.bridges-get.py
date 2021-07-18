#!/usr/bin/python3

# This file is part of TorBox, an easy to use anonymizing router based on Raspberry Pi.
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
# This file fetches one new bridge. The return values is:
# obfs4 <IP address>:<Port> <Fingerprint> <Certificate> <iat-mode>
#
# IMPORTANT
# The bridge database delivers only 1-3 bridges approximately every 24 hours,
# of which we pick one. With the bridges already delivered this should be sufficient.
#
# SYNTAX
# ./bridges_get.py

# where we store the temporal captchas to solve (full path)
TMP_DIR = '/tmp'
# url where we get the bridges
BRIDGES_URL = 'https://bridges.torproject.org/bridges?transport=obfs4'
# Tor socks
SOCKS_HOST = '127.0.0.1'
SOCKS_PORT = 9050

# -

from PIL import Image, ImageFilter
from pytesseract import image_to_string
from mechanize import Browser

import socks
import socket
import re
import os
import base64

def create_connection(address, timeout=None, source_address=None):
    sock = socks.socksocket()
    sock.connect(address)
    return sock

bridges = False
while bridges == False:
    # open page first
    br = Browser()
    br.set_handle_robots(False)

    try:
        # Clearnet request
        res = br.open(BRIDGES_URL)
    except:
        # Tor request
        socks.setdefaultproxy(socks.PROXY_TYPE_SOCKS5,
                              SOCKS_HOST,
                              SOCKS_PORT)

        # patch socket module
        socket.socket = socks.socksocket
        socket.create_connection = create_connection
        try:
            res = br.open(BRIDGES_URL)
        except:
            print("0")
            quit()

    # look for the captcha image / re.findall returns all the findings as a list
    html = str(res.read())
    q = re.findall(r'src="data:image/jpeg;base64,(.*?)"', html, re.DOTALL)
    img_data = q[0]

    # store captcha image
    f = open('%s/captcha.jpg' % TMP_DIR, 'wb')
    f.write( base64.b64decode(img_data) )
    f.close()

    # cleaning captcha / convert is part of imagemagick
    os.system(f'convert {TMP_DIR}/captcha.jpg '\
              f'-threshold 15% {TMP_DIR}/captcha.tif')
    os.system(f'convert {TMP_DIR}/captcha.tif '\
              f'-morphology Erode Disk:2 {TMP_DIR}/captcha.tif')

    # solve the captcha
    captcha_text = image_to_string(Image.open(f'{TMP_DIR}/captcha.tif'),
                            config='-c tessedit_char_whitelist='\
                                    '0123456789'\
                                    'ABCDEFGHIJKMNLOPKRSTUVWXYZ'\
                                    'abcdefghijklmnopqrstuvwxyz')
    captcha_text = captcha_text.strip()

    # if captcha len doesn't match on what we look, we just try again
    # ATTENTION: the length has to match with the captcha on
    # https://bridges.torproject.org/bridges?transport=obfs4 !!
    if len(captcha_text) != 7:
        continue

    # reply to server with the captcha text
    br.select_form(nr=0)
    br['captcha_response_field'] = captcha_text
    reply = br.submit()

    # look for the bridges if the captcha was beaten
    html = str(reply.read())
    q = re.findall(r'<div class="bridge-lines" id="bridgelines">(.*?)</div>',
                    html,
                    re.DOTALL)
    try:
        txt = q[0]
        b = txt.split('<br />')

        for l in b:
            # clean string for newlines and spaces
            _b = l.strip().replace('\\n', '')
            if _b != '':
                bridges = _b
    # captcha failed, try again
    except Exception as e:
        pass

print(bridges)
