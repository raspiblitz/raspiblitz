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
if [ "${setupPhase}" != "done" ] || 
   [ "${state}" == "" ] ||
   [ "${state}" == "copysource" ] ||
   [ "${state}" == "copytarget" ]; then
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

  # IMPORTANT NOTE: If you want to change the update frequency on a certain value
  # with `blitz.cache.sh outdate` do it on the chain specific value - for example:
  # do use: btc_${DEFAULT}net_sync_percentage
  # not use: btc_sync_percentage

  # loop thru mainet, testnet & signet
  networks=( "main" "test" "sig" )
  for CHAIN in "${networks[@]}"
  do

    # check if is default chain (multiple networks can run at the same time - but only one is default)
    isDefaultChain=$(echo "${CHAIN}" | grep -c "${chain}")

    # only continue if network chain is activated on blitz
    networkActive=$(cat /mnt/hdd/raspiblitz.conf | grep -c "^${CHAIN}net=on")
    if [ "${isDefaultChain}" != "1" ] && [ "${networkActive}" != "1" ]; then
      /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_activated "0"
      continue
    fi

    # update basic status values always
    source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net status)
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_activated "1"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_version "${btc_version}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_running "${btc_running}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_ready "${btc_ready}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_online "${btc_online}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_error_short "${btc_error_short}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_error_full "$btc_error_full}"

    # when default chain transfere values
    if [ "${isDefaultChain}" == "1" ]; then
      /home/admin/config.scripts/blitz.cache.sh set btc_activated "1"
      /home/admin/config.scripts/blitz.cache.sh set btc_version "${btc_version}"
      /home/admin/config.scripts/blitz.cache.sh set btc_running "${btc_running}"
      /home/admin/config.scripts/blitz.cache.sh set btc_ready "${btc_ready}"
      /home/admin/config.scripts/blitz.cache.sh set btc_online "${btc_online}"
      /home/admin/config.scripts/blitz.cache.sh set btc_error_short "${btc_error_short}"
      /home/admin/config.scripts/blitz.cache.sh set btc_error_full "$btc_error_full}"
    fi

    # update detail infos only when ready 
    if [ "${btc_ready}" == "1" ]; then 

      # check if network needs update
      source <(/home/admin/config.scripts/blitz.cache.sh valid btc_${CHAIN}net_blocks_headers btc_${CHAIN}net_blocks_verified btc_${CHAIN}net_blocks_behind btc_${CHAIN}net_sync_progress btc_${CHAIN}net_sync_percentage)
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt 30 ]; then
        error=""
        echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net blockchain"
        source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net blockchain)
        if [ "${error}" == "" ]; then
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_blocks_headers "${btc_blocks_headers}"
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_blocks_verified "${btc_blocks_verified}"
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_blocks_behind "${btc_blocks_behind}"
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_sync_progress "${btc_sync_progress}"
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_sync_percentage "${btc_sync_percentage}"
          if [ "${isDefaultChain}" == "1" ]; then
            /home/admin/config.scripts/blitz.cache.sh set btc_blocks_headers "${btc_blocks_headers}"
            /home/admin/config.scripts/blitz.cache.sh set btc_blocks_verified "${btc_blocks_verified}"
            /home/admin/config.scripts/blitz.cache.sh set btc_blocks_behind "${btc_blocks_behind}"
            /home/admin/config.scripts/blitz.cache.sh set btc_sync_progress "${btc_sync_progress}"
            /home/admin/config.scripts/blitz.cache.sh set btc_sync_percentage "${btc_sync_percentage}"
          fi
        else
          echo "!! ERROR --> ${error}"
        fi
      fi

      # check if network needs update
      source <(/home/admin/config.scripts/blitz.cache.sh valid btc_${CHAIN}net_peers btc_${CHAIN}net_address btc_${CHAIN}net_port)
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net network"
        source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net network)
        if [ "${error}" == "" ]; then
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_peers "${btc_peers}"
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_address "${btc_address}"
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_port "${btc_btc_port}"
          if [ "${isDefaultChain}" == "1" ]; then
            /home/admin/config.scripts/blitz.cache.sh set btc_peers "${btc_peers}"
            /home/admin/config.scripts/blitz.cache.sh set btc_address "${btc_address}"
            /home/admin/config.scripts/blitz.cache.sh set btc_port "${btc_btc_port}"
          fi
        else
          echo "!! ERROR --> ${error}"
        fi
      fi

      # check if mempool needs update
      source <(/home/admin/config.scripts/blitz.cache.sh valid btc_${CHAIN}net_mempool_transactions)
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net mempool"
        source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net mempool)
        if [ "${error}" == "" ]; then
          /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_mempool_transactions "${btc_mempool_transactions}"
          if [ "${isDefaultChain}" == "1" ]; then
            /home/admin/config.scripts/blitz.cache.sh set btc_mempool_transactions "${btc_mempool_transactions}"
          fi
        else
          echo "!! ERROR --> ${error}"
        fi
      fi

    # TODO: handle errors?
    #else
    #  # TODO: improve error handling --- also add a state to bitcoin.monitor.sh
    #  echo "!! WARNING Bitcoin (${CHAIN}net) running with error ..."
    #  echo "$btc_error_short"
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