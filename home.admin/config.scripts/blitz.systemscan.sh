#!/bin/bash

# This script is called regularly in the background to gather basic system information.
# Ut will place those values in the `blitz.cache.sh` system and take care about updates.
# Certain values have a default maximum age to get updated by this script.
# Every single value can be set to update more frequently by `blitz.cache.sh outdate`.

# check user running
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

####################################################################
# INIT 
####################################################################

# basic hardware info
source <(/home/admin/config.scripts/blitz.cache.sh valid system_board system_ramMB system_ramMB)
if [ "${stillvalid}" == "0" ]; then
  source <(/home/admin/config.scripts/blitz.hardware.sh status)
  /home/admin/config.scripts/blitz.cache.sh set system_board "${board}"
  /home/admin/config.scripts/blitz.cache.sh set system_ramMB "${ramMB}"
  /home/admin/config.scripts/blitz.cache.sh set system_ramMB "${ramGB}"
fi

####################################################################
# LOOP DATA (BASIC SYSTEM) 
# data that is always available 
####################################################################

#################
# BASIC SYSTEM 

# uptime just do on every run
system_up=$(cat /proc/uptime | grep -o '^[0-9]\+')
/home/admin/config.scripts/blitz.cache.sh set system_up "${system_up}"

#################
# DATADRIVE
# TODO

#################
# INTERNET

# basic local connection
source <(/home/admin/config.scripts/blitz.cache.sh valid internet_localip internet_localiprange internet_dhcp internet_rx internet_tx)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
  echo "updating: /home/admin/config.scripts/internet.sh status local"
  source <(/home/admin/config.scripts/internet.sh status local)
  /home/admin/config.scripts/blitz.cache.sh set internet_localip "${localip}"
  /home/admin/config.scripts/blitz.cache.sh set internet_localiprange "${localiprange}"
  /home/admin/config.scripts/blitz.cache.sh set internet_dhcp "${dhcp}"
  /home/admin/config.scripts/blitz.cache.sh set internet_rx "${network_rx}"
  /home/admin/config.scripts/blitz.cache.sh set internet_tx "${network_tx}"
fi

# connection to internet
source <(/home/admin/config.scripts/blitz.cache.sh valid internet_online)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${HOURQUATER} ]; then
  echo "updating: /home/admin/config.scripts/internet.sh status online"
  source <(/home/admin/config.scripts/internet.sh status online)
  /home/admin/config.scripts/blitz.cache.sh set internet_online "${online}"
fi

#################
# TOR

source <(/home/admin/config.scripts/blitz.cache.sh valid tor_web80_addr)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
  echo "updating: Tor Config Infos"
  /home/admin/config.scripts/blitz.cache.sh set tor_web_addr "$(cat /mnt/hdd/tor/web80/hostname 2>/dev/null)"
fi

# exit if still setup or higher system stopped
source <(/home/admin/config.scripts/blitz.cache.sh get setupPhase state)
if [ "${setupPhase}" != "done" ] || [ "${state}" == "" ] || [ "${state}" == "copysource" ] || [ "${state}" == "copytarget" ]; then
  echo "skipping deeper system scan (${counter}) - state(${state})"
  exit 1
  #sleep 1
  #continue
fi


####################################################################
# LOOP DATA (DEEPER SYSTEM)
# data that may be based on setup phase or configuration
####################################################################

# read/update config values
source /mnt/hdd/raspiblitz.conf


###################
# BITCOIN 
if [ "${network}" == "bitcoin" ]; then

  networks=( "main" "test" "sig" )
  for CHAIN in "${networks[@]}"
  do

    echo "########## ${CHAIN}"
    /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net status
    /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net blockchain
    /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net network
    /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net mempool

    # when default chain
    if [ "${CHAIN}" == "${chain}" ]; then
      echo "DEFAULT!"
    fi

  done


  ###################
  # BITCOIN (mainnet) 
  #if [ "${chain}" == "main" ] || [ "${mainnet}" == "on" ]; then
  #
  #  # always check status
  #  source <(/home/admin/config.scripts/bitcoin.monitor.sh mainnet status)
  #
  #fi

fi

#################
# DONE

# calculate how many seconds the script was running
endTime=$(date +%s)
runTime=$((${endTime}-${startTime}))

# write info on scan runtime into cache (use as signal that the first systemscan worked)
/home/admin/config.scripts/blitz.cache.sh set systemscan_runtime "${runTime}"

# log warning if script took too long
if [ ${runTime} -gt ${MINUTE} ]; then
  echo "WARNING: HANGING SYSTEM ... systemscan took more than a minute!"
fi