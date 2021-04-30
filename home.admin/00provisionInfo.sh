#!/bin/bash
_temp=$(mktemp -p /dev/shm/)

## get basic info
source /home/admin/raspiblitz.info 2>/dev/null

###################
# CHECK IF DNS NEEDS SETTING DURING SETUP
# https://github.com/rootzoll/raspiblitz/issues/787
###################
sudo /home/admin/config.scripts/internet.dns.sh test

# TODO: if DNS is not working --> ask in provision dialog
# TODO: get size of sd card & free space on sd card