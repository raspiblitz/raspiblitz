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
MINUTE=60
HOURQUATER=900
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

# basic local connection & online status
source <(/home/admin/config.scripts/blitz.cache.sh valid internet_localip internet_dhcp internet_rx internet_tx internet_online)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
  echo "updating: /home/admin/config.scripts/internet.sh status local"
  source <(/home/admin/config.scripts/internet.sh status local)
  /home/admin/config.scripts/blitz.cache.sh set internet_localip "${localip}"
  /home/admin/config.scripts/blitz.cache.sh set internet_dhcp "${dhcp}"
  /home/admin/config.scripts/blitz.cache.sh set internet_rx "${network_rx}"
  /home/admin/config.scripts/blitz.cache.sh set internet_tx "${network_tx}"
  /home/admin/config.scripts/blitz.cache.sh set internet_online "${online}"
fi

# info on scan run time
endTime=$(date +%s)
runTime=$((${endTime}-${startTime}))
echo "runtime=${runTime}"
if [ ${runTime} -gt ${MINUTE} ]; then
  echo "WARNING: HANGING SYSTEM ... systemscan took more than a minute!"
fi