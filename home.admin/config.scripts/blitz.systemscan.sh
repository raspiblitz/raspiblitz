#!/bin/bash

# This script is called regularly in the background to gather basic system information.
# Ut will place those values in the `blitz.cache.sh` system and take care about updates.
# Certain values have a default maximum age to get updated by this script.
# Every single value can be set to update more frequently by `blitz.cache.sh outdate`.

if [ "$EUID" -ne 0 ]; then
  echo "FAIL: need to be run as root user"
  exit 1
fi

# better readbale seconds
MINUTE1=60
MINUTE10=600
HOURHALF=1800
HOUR=3600
DAYHALF=43200
DAY=86400
WEEK=604800
MONTH=2592000
YEAR=31536000

# measure time of scan
startTime=$(date +%s)

#################
# BASIC SYSTEM 

# just do on every run
system_up=$(cat /proc/uptime | grep -o '^[0-9]\+')
/home/admin/config.scripts/blitz.cache.sh set system_up "${system_up}"

#################
# INTERNET

# TODO: seperate local network from online to not always target online pings when local info updating
# TODO: rename values to network_ so thatz they fit more nicely

# basic local connection & online status
source <(/home/admin/config.scripts/blitz.cache.sh valid localip dhcp network_rx network_tx online)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE10} ]; then
  echo "updating: /home/admin/config.scripts/internet.sh status local"
  source <(/home/admin/config.scripts/internet.sh status local)
  /home/admin/config.scripts/blitz.cache.sh set localip "${localip}"
  /home/admin/config.scripts/blitz.cache.sh set dhcp "${dhcp}"
  /home/admin/config.scripts/blitz.cache.sh set network_rx "${network_rx}"
  /home/admin/config.scripts/blitz.cache.sh set online "${online}"
else
  echo "stillvalid: /home/admin/config.scripts/internet.sh status local"
fi

# info on scan run time
endTime=$(date +%s)
runTime=$(echo "${endTime}-${startTime}" | bc)
echo "scriptRuntime=${runTime}"
if [ ${scriptRuntime} -gt $MINUTE1 ]; then
  echo "WARNING: HANGING SYSTEM ... systemscan took more than a minute!"
else
  echo "OK"
fi