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

# better readbale seconds (slightly off to reduce same time window trigger)
MINUTE=60
MINUTE2=115
MINUTE5=290
MINUTE10=585
HOURQUATER=880
HOURHALF=1775
HOUR=3570
DAYHALF=43165
DAY=86360
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

# default temp
/home/admin/config.scripts/blitz.cache.sh set system_temp_celsius "0"
/home/admin/config.scripts/blitz.cache.sh set system_temp_fahrenheit "0"

####################################################################
# LOOP DATA (BASIC SYSTEM) 
# data that is always available 
####################################################################

#################
# BASIC SYSTEM 

# uptime just do on every run
system_up=$(cat /proc/uptime | grep -o '^[0-9]\+')
/home/admin/config.scripts/blitz.cache.sh set system_up "${system_up}"

# cpu load
cpu_load=$(w | head -n 1 | cut -d 'v' -f2 | cut -d ':' -f2)
/home/admin/config.scripts/blitz.cache.sh set system_cpu_load "${cpu_load}"

# cpu temp - no measurement in a VM
if [ -d "/sys/class/thermal/thermal_zone0/" ]; then
  cpu=$(cat /sys/class/thermal/thermal_zone0/temp)
  tempC=$((cpu/1000))
  tempF=$(((tempC * 18 + 325) / 10))
  /home/admin/config.scripts/blitz.cache.sh set system_temp_celsius "${tempC}"
  /home/admin/config.scripts/blitz.cache.sh set system_temp_fahrenheit "${tempF}"
fi

# ram
ram=$(printf "%sM / %sM" "${ram_avail}" "$(free -m | grep Mem | awk '{ print $2 }')")
ram_avail=$(free -m | grep Mem | awk '{ print $7 }')
/home/admin/config.scripts/blitz.cache.sh set system_ram "${ram}"
/home/admin/config.scripts/blitz.cache.sh set system_ram_available "${ram_avail}"

# undervoltage
source <(/home/admin/config.scripts/blitz.cache.sh valid system_undervoltage_count)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
  echo "updating: undervoltage"
  countReports=$(cat /var/log/syslog | grep -c "Under-voltage detected!")
  /home/admin/config.scripts/blitz.cache.sh set system_undervoltage_count "${countReports}"
fi

# UPS (uninterruptible power supply)
source <(/home/admin/config.scripts/blitz.cache.sh valid system_ups_status)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
  echo "updating: /home/admin/config.scripts/blitz.ups.sh status"
  source <(/home/admin/config.scripts/blitz.ups.sh status)
  /home/admin/config.scripts/blitz.cache.sh set system_ups_status "${upsStatus}"
fi

#################
# DATADRIVE

source <(/home/admin/config.scripts/blitz.cache.sh valid hdd_mounted hdd_ssd hdd_btrfs hdd_raid hdd_uasp hdd_capacity_bytes hdd_capacity_gb hdd_free_bytes hdd_free_gb hdd_used_info hdd_blockchain_data)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE2} ]; then
  echo "updating: /home/admin/config.scripts/blitz.datadrive.sh status"
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)
  /home/admin/config.scripts/blitz.cache.sh set hdd_mounted "${isMounted}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_ssd "${isSSD}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_btrfs "${isBTRFS}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_raid "${isRaid}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_uasp "${hddAdapterUSAP}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_capacity_bytes "${hddBytes}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_capacity_gb "${hddGigaBytes}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_free_bytes "${hddDataFreeBytes}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_free_gb "${hddDataFreeGB}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_used_info "${hddUsedInfo}"
  /home/admin/config.scripts/blitz.cache.sh set hdd_blockchain_data "${hddBlocksBitcoin}"
fi

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

source <(/home/admin/config.scripts/blitz.cache.sh valid tor_web_addr)
if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE5} ]; then
  echo "updating: tor"
  /home/admin/config.scripts/blitz.cache.sh set tor_web_addr "$(cat /mnt/hdd/tor/web80/hostname 2>/dev/null)"
fi

# exit if still setup or higher system stopped
source <(/home/admin/config.scripts/blitz.cache.sh get setupPhase state)
if [ "${setupPhase}" != "done" ] ||
   [ "${state}" == "" ] ||
   [ "${state}" == "copysource" ] ||
   [ "${state}" == "copytarget" ]; then
  echo "skipping deeper system scan (${setupPhase}) - state(${state})"
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

    # check is last status values are still valid (most relaxed check every 10 secs)
    source <(/home/admin/config.scripts/blitz.cache.sh valid btc_${CHAIN}net_activated btc_${CHAIN}net_version btc_${CHAIN}net_running btc_${CHAIN}net_ready btc_${CHAIN}net_online  btc_${CHAIN}net_error_short btc_${CHAIN}net_error_full)
    if [ "${stillvalid}" == "1" ] && [ ${age} -lt 10 ]; then
      continue
    fi

    # only continue if network chain is activated on blitz
    networkActive=$(cat /mnt/hdd/raspiblitz.conf | grep -c "^${CHAIN}net=on")
    if [ "${isDefaultChain}" != "1" ] && [ "${networkActive}" != "1" ]; then
      /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_activated "0"
      continue
    fi

    # update basic status values always
    echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net status"
    source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net status)
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_activated "1"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_version "${btc_version}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_running "${btc_running}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_ready "${btc_ready}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_online "${btc_online}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_error_short "${btc_error_short}"
    /home/admin/config.scripts/blitz.cache.sh set btc_${CHAIN}net_error_full "${btc_error_full}"

    # when default chain transfere values
    if [ "${isDefaultChain}" == "1" ]; then
      /home/admin/config.scripts/blitz.cache.sh set btc_activated "1"
      /home/admin/config.scripts/blitz.cache.sh set btc_version "${btc_version}"
      /home/admin/config.scripts/blitz.cache.sh set btc_running "${btc_running}"
      /home/admin/config.scripts/blitz.cache.sh set btc_ready "${btc_ready}"
      /home/admin/config.scripts/blitz.cache.sh set btc_online "${btc_online}"
      /home/admin/config.scripts/blitz.cache.sh set btc_error_short "${btc_error_short}"
      /home/admin/config.scripts/blitz.cache.sh set btc_error_full "${btc_error_full}"
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

fi

#################
# DONE

# calculate how many seconds the script was running
endTime=$(date +%s)
runTime=$((${endTime}-${startTime}))

# write info on scan runtime into cache (use as signal that the first systemscan worked)
/home/admin/config.scripts/blitz.cache.sh set systemscan_runtime "${runTime}"
echo "SystemScan Loop done in ${runTime} seconds"

# log warning if script took too long
if [ ${runTime} -gt ${MINUTE} ]; then
  echo "WARNING: HANGING SYSTEM ... systemscan loop took too long (${runTime} seconds)!" 1>&2 
fi