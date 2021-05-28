#!/bin/bash

# TODO: if DNS is not working --> ask in system-loop
# TODO: get size of sd card & free space on sd card

##################
# CHECK IF DNS NEEDS SETTING DURING SETUP
# https://github.com/rootzoll/raspiblitz/issues/787
###################
sudo /home/admin/config.scripts/internet.dns.sh test