#!/bin/bash

# This script will loop in the background to gather basic system information.
# It will place those values in the `_cache.sh` system and take care about updates.
# You can use `_cache.sh focus` to make the scanning of a certain value more often.

# LOGS see: sudo journalctl -f -u background.scan

# start with parameter "only-one-loop" (use for testing)
ONLY_ONE_LOOP="0"
if [ "$1" == "only-one-loop" ]; then
  ONLY_ONE_LOOP="1"
fi
# start with parameter "install" (to setup service as systemd background running)
if [ "$1" == "install" ]; then

  # write systemd service
  cat > /etc/systemd/system/background.scan.service <<EOF
# Monitor the RaspiBlitz State
# /etc/systemd/system/background.scan.service

[Unit]
Description=RaspiBlitz Background Monitoring Service
Wants=redis.service
After=redis.service

[Service]
User=root
Group=root
Type=simple
ExecStart=/home/admin/_background.scan.sh
Restart=always
TimeoutSec=10
RestartSec=10
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

  # enable systemd service & exit
  sudo systemctl enable background.scan
  echo "# background.scan.service will start after reboot or calling: sudo systemctl start background.scan"
  exit
fi

# check user running
if [ "$EUID" -ne 0 ]; then
  echo "FAIL: need to be run as root user"
  exit 1
fi

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - persited state data
infoFile="/home/admin/raspiblitz.info"

# better readable seconds (slightly off to reduce same time window trigger)
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

# make sure root is in group bitcoin and allowed to read macaroons
usermod -G bitcoin root

####################################################################
# INIT
####################################################################

# init values
/home/admin/_cache.sh init system_temp_celsius "0"
/home/admin/_cache.sh init system_temp_fahrenheit "0"
/home/admin/_cache.sh init system_count_longscan "0"
/home/admin/_cache.sh init system_count_undervoltage "0"
/home/admin/_cache.sh init system_count_start_blockchain "0"
/home/admin/_cache.sh init system_count_start_lightning "0"
/home/admin/_cache.sh init system_count_start_tui "0"
/home/admin/_cache.sh init btc_default_peers "0"
/home/admin/_cache.sh init btc_default_sync_percentage "0"
/home/admin/_cache.sh init btc_default_address ""
/home/admin/_cache.sh init btc_default_port ""

# import all base values from raspiblitz.info
echo "importing: ${infoFile}"
/home/admin/_cache.sh import $infoFile

# import all base values from raspiblitz.config (if exists)
configFileExists=$(ls ${configFile} | grep -c "${configFile}")
if [ "${configFileExists}" != "0" ]; then
  echo "importing: ${configFile}"
  /home/admin/_cache.sh import ${configFile}
fi

# version info
echo "importing: _version.info"
/home/admin/_cache.sh import /home/admin/_version.info

# get hardware info
source <(/home/admin/config.scripts/blitz.hardware.sh status)
/home/admin/_cache.sh set system_board "${board}"
/home/admin/_cache.sh set system_ram_mb "${ramMB}"
/home/admin/_cache.sh set system_ram_gb "${ramGB}"

# flag that init was done (will be checked on each loop)
/home/admin/_cache.sh set system_init_time "$(date +%s)"

# add info about start to raspiblitz.log
echo "INFO: _bootstrap.scan.sh loop started > sudo journalctl -f -u background.scan" >> /home/admin/raspiblitz.log

while [ 1 ]
do

  ####################################################################
  # LOOP DATA (BASIC SYSTEM)
  # data that is always available
  ####################################################################

  # check that redis contains init data (detect possible restart of redis)
  source <(/home/admin/_cache.sh get system_init_time)
  if [ "${system_init_time}" == "" ]; then
    echo "FAIL: CACHE IS MISSING INIT DATA ... exiting to let systemd restart"
    echo "INFO: _bootstrap.scan.sh -> cache not running - exiting" >> /home/admin/raspiblitz.log
    exit 1
  fi

  # measure time of loop scan
  startTime=$(date +%s)

  #################
  # BASIC SYSTEM

  # uptime just do on every run
  system_up=$(cat /proc/uptime | grep -o '^[0-9]\+')
  system_up_text=$(uptime -p | cut -d ' ' -f 2- | cut -d ',' -f 1 | awk '{print $1 substr($2, 1, 1)}')
  /home/admin/_cache.sh set system_up "${system_up}"
  /home/admin/_cache.sh set system_up_text "${system_up_text}"

  # cpu load
  cpu_load=$(w | head -n 1 | cut -d 'v' -f2 | cut -d ':' -f2)
  /home/admin/_cache.sh set system_cpu_load "${cpu_load}"

  # cpu temp - no measurement in a VM
  if [ -d "/sys/class/thermal/thermal_zone0/" ]; then
    cpu=$(cat /sys/class/thermal/thermal_zone0/temp)
    tempC=$((cpu/1000))
    tempF=$(((tempC * 18 + 325) / 10))
    /home/admin/_cache.sh set system_temp_celsius "${tempC}"
    /home/admin/_cache.sh set system_temp_fahrenheit "${tempF}"
  fi

  # ram
  ram_avail=$(free -m | grep -E 'Mem|Speicher' | awk '{ print $7 }')
  /home/admin/_cache.sh set system_ram_available_mb "${ram_avail}"

  # undervoltage
  source <(/home/admin/_cache.sh valid system_count_undervoltage)
  if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
    echo "updating: undervoltage"
    countReports=$(cat /var/log/syslog | grep -c "Under-voltage detected!")
    /home/admin/_cache.sh set system_count_undervoltage "${countReports}"
  fi

  # update code commit
  codeCommit=$(git -C /home/admin/raspiblitz rev-parse --short HEAD)
  /home/admin/_cache.sh set codeCommit "${codeCommit}"

  #################
  # TOR

  source <(/home/admin/_cache.sh valid tor_web_addr)
  if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE5} ]; then
    echo "updating: tor"
    /home/admin/_cache.sh set tor_web_addr "$(cat /mnt/hdd/tor/web80/hostname 2>/dev/null)"
  fi

  #################
  # UPS (uninterruptible power supply)

  source <(/home/admin/_cache.sh valid system_ups_status)
  if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
    echo "updating: /home/admin/config.scripts/blitz.ups.sh status"
    source <(/home/admin/config.scripts/blitz.ups.sh status)
    /home/admin/_cache.sh set system_ups_status "${upsStatus}"
    /home/admin/_cache.sh set system_ups_battery "${upsBattery}"
  fi

  #################
  # DATADRIVE

  source <(/home/admin/_cache.sh valid \
    hdd_mounted \
    hdd_ssd \
    hdd_btrfs \
    hdd_raid \
    hdd_uasp \
    hdd_capacity_bytes \
    hdd_capacity_gb \
    hdd_free_bytes \
    hdd_free_gb \
    hdd_used_info \
    hdd_blockchain_data \
  )

  #################
  # INTERNET

   # GLOBAL & PUBLIC IP
  source <(/home/admin/_cache.sh get runBehindTor)
  if [ "${runBehindTor}" == "off" ]; then
    source <(/home/admin/_cache.sh valid \
      internet_public_ipv6 \
      internet_public_ip_detected \
      internet_public_ip_forced \
      internet_public_ip_clean \
    )
    if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${HOUR} ]; then
      echo "updating: /home/admin/config.scripts/internet.sh status global"
      source <(/home/admin/config.scripts/internet.sh status global)
      /home/admin/_cache.sh set internet_public_ipv6 "${ipv6}"
      # globalip --> ip detected from the outside
      /home/admin/_cache.sh set internet_public_ip_detected "${globalip}"
      # publicip --> may consider the static IP overide by raspiblitz config
      /home/admin/_cache.sh set internet_public_ip_forced "${publicip}"
      # cleanip --> the publicip with no brackets like used on IPv6
      /home/admin/_cache.sh set internet_public_ip_clean "${cleanip}"
    fi
  fi

  # LOCAL IP & data
  source <(/home/admin/_cache.sh valid \
    internet_localip \
    internet_localiprange \
    internet_dhcp \
    internet_rx \
    internet_tx \
  )
  if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE} ]; then
    echo "updating: /home/admin/config.scripts/internet.sh status local"
    source <(/home/admin/config.scripts/internet.sh status local)
    /home/admin/_cache.sh set internet_localip "${localip}"
    /home/admin/_cache.sh set internet_localiprange "${localiprange}"
    /home/admin/_cache.sh set internet_dhcp "${dhcp}"
    /home/admin/_cache.sh set internet_rx "${network_rx}"
    /home/admin/_cache.sh set internet_tx "${network_tx}"
  fi

  # connection to internet
  source <(/home/admin/_cache.sh valid internet_online)
  if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${HOURQUATER} ]; then
    echo "updating: /home/admin/config.scripts/internet.sh status online"
    source <(/home/admin/config.scripts/internet.sh status online)
    /home/admin/_cache.sh set internet_online "${online}"
  fi

  ###################
  # HARDDRIVE

  # info on storage medium
  source <(/home/admin/_cache.sh valid hdd_mounted)
  if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${MINUTE2} ]; then
    echo "updating: /home/admin/config.scripts/blitz.datadrive.sh status"
    source <(/home/admin/config.scripts/blitz.datadrive.sh status)
    /home/admin/_cache.sh set hdd_mounted "${isMounted}"
    /home/admin/_cache.sh set hdd_ssd "${isSSD}"
    /home/admin/_cache.sh set hdd_btrfs "${isBTRFS}"
    /home/admin/_cache.sh set hdd_raid "${isRaid}"
    /home/admin/_cache.sh set hdd_uasp "${hddAdapterUSAP}"
    /home/admin/_cache.sh set hdd_capacity_bytes "${hddBytes}"
    /home/admin/_cache.sh set hdd_capacity_gb "${hddGigaBytes}"
    /home/admin/_cache.sh set hdd_free_bytes "${hddDataFreeBytes}"
    /home/admin/_cache.sh set hdd_free_gb "${hddDataFreeGB}"
    /home/admin/_cache.sh set hdd_used_info "${hddUsedInfo}"
    /home/admin/_cache.sh set hddTemperature "${hddTemperature}"
    /home/admin/_cache.sh set hddTBSize "${hddTBSize}"
    
  fi

  # exit if still setup or higher system stopped
  source <(/home/admin/_cache.sh get setupPhase state)
  if [ "${setupPhase}" != "done" ] ||
     [ "${state}" == "" ] ||
     [ "${state}" == "copysource" ] ||
     [ "${state}" == "copytarget" ]; then

      # dont skip when setup/recovery is in "waitsync" state
      if [ "${state}" != "waitsync" ]; then
        endTime=$(date +%s)
        runTime=$((${endTime}-${startTime}))
        # write info on scan runtime into cache (use as signal that the first systemscan worked)
        /home/admin/_cache.sh set systemscan_runtime "${runTime}"
        echo "Skipping deeper system scan - setupPhase(${setupPhase}) state(${state})"
        sleep 1
        continue
      fi

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

    # loop thru mainet, testnet & signet
    networks=( "main" "test" "sig" )
    for CHAIN in "${networks[@]}"
    do

      # check if is default chain (multiple networks can run at the same time - but only one is default)
      isDefaultChain=$(echo "${CHAIN}" | grep -c "${chain}")

      # skip if network is not on by config
      if [ "${CHAIN}" == "main" ] && [ "${mainnet}" != "on" ] && [ "${isDefaultChain}" != "1" ]; then
        #echo "skip btc ${CHAIN}net scan - because its off"
        continue
      fi
      if [ "${CHAIN}" == "test" ] && [ "${testnet}" != "on" ]; then
        #echo "skip btc ${CHAIN}net scan - because its off"
        continue
      fi
      if [ "${CHAIN}" == "sig" ] && [ "${signet}" != "on" ]; then
        #echo "skip btc ${CHAIN}net scan - because its off"
        continue
      fi

      # set intervals for non default & non-default (in seconds)
      CYCLE_QUICK=30
      CYCLE_MID=60
      CYCLE_LONG=90
      if [ "${isDefaultChain}" != "1" ]; then
        CYCLE_QUICK=150
        CYCLE_MID=300
        CYCLE_LONG=600
      fi

      # update basic status values always
      source <(/home/admin/_cache.sh valid \
        btc_${CHAIN}net_version \
        btc_${CHAIN}net_running \
        btc_${CHAIN}net_ready \
        btc_${CHAIN}net_online  \
        btc_${CHAIN}net_error_short \
        btc_${CHAIN}net_error_full \
      )
      if [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
        source <(/home/admin/_cache.sh valid \
        btc_default_version \
        btc_default_running \
        btc_default_ready \
        btc_default_online  \
        btc_default_error_short \
        btc_default_error_full \
        )
      fi
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_QUICK} ]; then
        echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net status"
        source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net status)
        /home/admin/_cache.sh set btc_${CHAIN}net_activated "1"
        /home/admin/_cache.sh set btc_${CHAIN}net_version "${btc_version}"
        /home/admin/_cache.sh set btc_${CHAIN}net_running "${btc_running}"
        /home/admin/_cache.sh set btc_${CHAIN}net_ready "${btc_ready}"
        /home/admin/_cache.sh set btc_${CHAIN}net_online "${btc_online}"
        /home/admin/_cache.sh set btc_${CHAIN}net_error_short "${btc_error_short}"
        /home/admin/_cache.sh set btc_${CHAIN}net_error_full "${btc_error_full}"

        # when default chain transfere values
        if [ "${isDefaultChain}" == "1" ]; then
          /home/admin/_cache.sh set btc_default_activated "1"
          /home/admin/_cache.sh set btc_default_version "${btc_version}"
          /home/admin/_cache.sh set btc_default_running "${btc_running}"
          /home/admin/_cache.sh set btc_default_ready "${btc_ready}"
          /home/admin/_cache.sh set btc_default_online "${btc_online}"
          /home/admin/_cache.sh set btc_default_error_short "${btc_error_short}"
          /home/admin/_cache.sh set btc_default_error_full "${btc_error_full}"
        fi
      fi

      # update detail infos only when ready (get as value from cache)
      source <(/home/admin/_cache.sh meta btc_${CHAIN}net_ready)
      if [ "${value}" == "1" ]; then

        # check if network needs update
        source <(/home/admin/_cache.sh valid \
          btc_${CHAIN}net_synced \
          btc_${CHAIN}net_blocks_headers \
          btc_${CHAIN}net_blocks_verified \
          btc_${CHAIN}net_blocks_behind \
          btc_${CHAIN}net_sync_progress \
          btc_${CHAIN}net_sync_percentage \
          btc_${CHAIN}net_sync_initialblockdownload \
        )
        if [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
          source <(/home/admin/_cache.sh valid \
          btc_default_synced \
          btc_default_blocks_headers \
          btc_default_blocks_verified \
          btc_default_blocks_behind \
          btc_default_sync_progress \
          btc_default_sync_percentage \
          btc_default_sync_initialblockdownload \
          )
        fi
        if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_MID} ]; then
          error=""
          echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net info"
          source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net info)
          if [ "${error}" == "" ]; then
            /home/admin/_cache.sh set btc_${CHAIN}net_synced "${btc_synced}"
            /home/admin/_cache.sh set btc_${CHAIN}net_blocks_headers "${btc_blocks_headers}"
            /home/admin/_cache.sh set btc_${CHAIN}net_blocks_verified "${btc_blocks_verified}"
            /home/admin/_cache.sh set btc_${CHAIN}net_blocks_behind "${btc_blocks_behind}"
            /home/admin/_cache.sh set btc_${CHAIN}net_blocks_data_kb "${btc_blocks_data_kb}"
            /home/admin/_cache.sh set btc_${CHAIN}net_sync_progress "${btc_sync_progress}"
            /home/admin/_cache.sh set btc_${CHAIN}net_sync_percentage "${btc_sync_percentage}"
            /home/admin/_cache.sh set btc_${CHAIN}net_sync_initialblockdownload "${btc_sync_initialblockdownload}"

            if [ "${isDefaultChain}" == "1" ]; then
              /home/admin/_cache.sh set btc_default_synced "${btc_synced}"
              /home/admin/_cache.sh set btc_default_blocks_headers "${btc_blocks_headers}"
              /home/admin/_cache.sh set btc_default_blocks_verified "${btc_blocks_verified}"
              /home/admin/_cache.sh set btc_default_blocks_behind "${btc_blocks_behind}"
              /home/admin/_cache.sh set btc_default_blocks_data_kb "${btc_blocks_data_kb}"
              /home/admin/_cache.sh set btc_default_sync_progress "${btc_sync_progress}"
              /home/admin/_cache.sh set btc_default_sync_percentage "${btc_sync_percentage}"
              /home/admin/_cache.sh set btc_default_sync_initialblockdownload "${btc_sync_initialblockdownload}"
            fi

          else
            echo "# ERROR --> ${error}"
          fi
        fi

        # check if network needs update
        source <(/home/admin/_cache.sh valid \
          btc_${CHAIN}net_peers \
          btc_${CHAIN}net_address \
          btc_${CHAIN}net_port \
        )
        if [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
          source <(/home/admin/_cache.sh valid \
          btc_default_peers \
          btc_default_address \
          btc_default_port \
          )
        fi
        if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_MID} ]; then
          error=""
          echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net network"
          source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net network)
          if [ "${error}" == "" ]; then
            /home/admin/_cache.sh set btc_${CHAIN}net_peers "${btc_peers}"
            /home/admin/_cache.sh set btc_${CHAIN}net_address "${btc_address}"
            /home/admin/_cache.sh set btc_${CHAIN}net_port "${btc_port}"
            if [ "${isDefaultChain}" == "1" ]; then
              /home/admin/_cache.sh set btc_default_peers "${btc_peers}"
              /home/admin/_cache.sh set btc_default_address "${btc_address}"
              /home/admin/_cache.sh set btc_default_port "${btc_port}"
            fi
          else
            echo "# ERROR --> ${error}"
          fi
        fi

        # check if mempool needs update
        source <(/home/admin/_cache.sh valid \
          btc_${CHAIN}net_mempool_transactions \
        )
        if [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
          source <(/home/admin/_cache.sh valid \
          btc_default_mempool_transactions \
          )
        fi
        if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_LONG} ]; then
          error=""
          echo "updating: /home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net mempool"
          source <(/home/admin/config.scripts/bitcoin.monitor.sh ${CHAIN}net mempool)
          if [ "${error}" == "" ]; then
            /home/admin/_cache.sh set btc_${CHAIN}net_mempool_transactions "${btc_mempool_transactions}"
            if [ "${isDefaultChain}" == "1" ]; then
              /home/admin/_cache.sh set btc_default_mempool_transactions "${btc_mempool_transactions}"
            fi
          else
            echo "# ERROR --> ${error}"
          fi
        fi
      fi
    done
  fi

  ###################
  # Lightning (lnd)

  # loop thru mainet, testnet & signet
  networks=( "main" "test" "sig" )
  for CHAIN in "${networks[@]}"
  do

    # skip if network is not on by config
    if [ "${CHAIN}" == "main" ] && [ "${lnd}" != "on" ]; then
      #echo "skip lnd ${CHAIN}net scan - because its off"
      continue
    fi
    if [ "${CHAIN}" == "test" ] && [ "${tlnd}" != "on" ]; then
      #echo "skip lnd ${CHAIN}net scan - because its off"
      continue
    fi
    if [ "${CHAIN}" == "sig" ] && [ "${slnd}" != "on" ]; then
      #echo "skip lnd ${CHAIN}net scan - because its off"
      continue
    fi

    # check if default chain & lightning
    isDefaultChain=$(echo "${CHAIN}" | grep -c "${chain}")
    isDefaultLightning=$(echo "${lightning}" | grep -c "lnd")

    # set intervals for non default & non-default (in seconds)
    CYCLE_QUICK=30
    CYCLE_MID=60
    CYCLE_LONG=90
    if [ "${isDefaultChain}" != "1" ] || [ "${isDefaultLightning}" != "1" ]; then
      CYCLE_QUICK=300
      CYCLE_MID=600
      CYCLE_LONG=900
    fi

    # update basic status values always
    source <(/home/admin/_cache.sh valid \
      ln_lnd_${CHAIN}net_locked \
      ln_lnd_${CHAIN}net_version \
      ln_lnd_${CHAIN}net_running \
      ln_lnd_${CHAIN}net_ready \
      ln_lnd_${CHAIN}net_online \
      ln_lnd_${CHAIN}net_error_short \
      ln_lnd_${CHAIN}net_error_full \
    )
    if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
      source <(/home/admin/_cache.sh valid \
      ln_default_locked \
      ln_default_version \
      ln_default_running \
      ln_default_ready \
      ln_default_online \
      ln_default_error_short \
      ln_default_error_full \
      )
    fi
    if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_QUICK} ]; then
      echo "updating: /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net status"
      source <(timeout 30s /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net status)
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_activated "1"
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_locked "${ln_lnd_locked}"
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_version "${ln_lnd_version}"
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_running "${ln_lnd_running}"
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_ready "${ln_lnd_ready}"
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_online "${ln_lnd_online}"
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_error_short "${ln_lnd_error_short}"
      /home/admin/_cache.sh set ln_lnd_${CHAIN}net_error_full "${ln_lnd_error_full}"
      if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
        /home/admin/_cache.sh set ln_default_activated "1"
        /home/admin/_cache.sh set ln_default_locked "${ln_lnd_locked}"
        /home/admin/_cache.sh set ln_default_version "${ln_lnd_version}"
        /home/admin/_cache.sh set ln_default_running "${ln_lnd_running}"
        /home/admin/_cache.sh set ln_default_ready "${ln_lnd_ready}"
        /home/admin/_cache.sh set ln_default_online "${ln_lnd_online}"
        /home/admin/_cache.sh set ln_default_error_short "${ln_lnd_error_short}"
        /home/admin/_cache.sh set ln_default_error_full "${ln_lnd_error_full}"
      fi
    fi

    # update detail infos only when ready
    source <(/home/admin/_cache.sh meta ln_lnd_${CHAIN}net_ready)
    if [ "${value}" == "1" ]; then

      # check if config needs update
      source <(/home/admin/_cache.sh valid ln_lnd_${CHAIN}net_alias)
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_LONG} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net config"
        source <(timeout 30s /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net config)
        if [ "${error}" == "" ]; then
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_alias "${ln_lnd_alias}"
          if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
            /home/admin/_cache.sh set ln_default_alias "${ln_lnd_alias}"
          fi
        else
          echo "# ERROR --> ${error}"
        fi
      fi

      # check if info needs update
      source <(/home/admin/_cache.sh valid \
        ln_lnd_${CHAIN}net_address \
        ln_lnd_${CHAIN}net_tor \
        ln_lnd_${CHAIN}net_sync_chain \
        ln_lnd_${CHAIN}net_sync_graph \
        ln_lnd_${CHAIN}net_channels_pending \
        ln_lnd_${CHAIN}net_channels_active \
        ln_lnd_${CHAIN}net_channels_inactive \
        ln_lnd_${CHAIN}net_channels_total \
        ln_lnd_${CHAIN}net_peers \
        ln_lnd_${CHAIN}net_recovery_mode \
        ln_lnd_${CHAIN}net_recovery_done \
      )
      if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
        source <(/home/admin/_cache.sh valid \
        ln_default_address \
        ln_default_tor \
        ln_default_sync_chain \
        ln_default_sync_progress \
        ln_default_channels_pending \
        ln_default_channels_active \
        ln_default_channels_inactive \
        ln_default_channels_total \
        ln_default_peers \
        ln_default_recovery_mode \
        ln_default_recovery_done \
        )
      fi
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_MID} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net info"
        source <(timeout 30s /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net info)
        if [ "${error}" == "" ]; then
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_address "${ln_lnd_address}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_tor "${ln_lnd_tor}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_sync_chain "${ln_lnd_sync_chain}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_sync_progress "${ln_lnd_sync_progress}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_sync_graph "${ln_lnd_sync_graph}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_channels_pending "${ln_lnd_channels_pending}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_channels_active "${ln_lnd_channels_active}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_channels_inactive "${ln_lnd_channels_inactive}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_channels_total "${ln_lnd_channels_total}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_peers "${ln_lnd_peers}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_recovery_mode "${ln_lnd_recovery_mode}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_recovery_done "${ln_lnd_recovery_done}"
          if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
            /home/admin/_cache.sh set ln_default_address "${ln_lnd_address}"
            /home/admin/_cache.sh set ln_default_tor "${ln_lnd_tor}"
            /home/admin/_cache.sh set ln_default_sync_chain "${ln_lnd_sync_chain}"
            /home/admin/_cache.sh set ln_default_sync_progress "${ln_lnd_sync_progress}"
            /home/admin/_cache.sh set ln_default_channels_pending "${ln_lnd_channels_pending}"
            /home/admin/_cache.sh set ln_default_channels_active "${ln_lnd_channels_active}"
            /home/admin/_cache.sh set ln_default_channels_inactive "${ln_lnd_channels_inactive}"
            /home/admin/_cache.sh set ln_default_channels_total "${ln_lnd_channels_total}"
            /home/admin/_cache.sh set ln_default_peers "${ln_lnd_peers}"
            /home/admin/_cache.sh set ln_default_recovery_mode "${ln_lnd_recovery_mode}"
            /home/admin/_cache.sh set ln_default_recovery_done "${ln_lnd_recovery_done}"
          fi
        else
          echo "# ERROR --> ${error}"
        fi
      fi

      # check if wallet needs update
      source <(/home/admin/_cache.sh valid \
        ln_lnd_${CHAIN}net_wallet_onchain_balance \
        ln_lnd_${CHAIN}net_wallet_onchain_pending \
        ln_lnd_${CHAIN}net_wallet_channels_balance \
        ln_lnd_${CHAIN}net_wallet_channels_pending \
      )
      if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
        source <(/home/admin/_cache.sh valid \
        ln_default_wallet_onchain_balance \
        ln_default_wallet_onchain_pending \
        ln_default_wallet_channels_balance \
        ln_default_wallet_channels_pending \
        )
      fi
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_QUICK} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net wallet"
        source <(timeout 30s /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net wallet)
        if [ "${error}" == "" ]; then
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_wallet_onchain_balance "${ln_lnd_wallet_onchain_balance}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_wallet_onchain_pending "${ln_lnd_wallet_onchain_pending}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_wallet_channels_balance "${ln_lnd_wallet_channels_balance}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_wallet_channels_pending "${ln_lnd_wallet_channels_pending}"
          if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
            /home/admin/_cache.sh set ln_default_wallet_onchain_balance "${ln_lnd_wallet_onchain_balance}"
            /home/admin/_cache.sh set ln_default_wallet_onchain_pending "${ln_lnd_wallet_onchain_pending}"
            /home/admin/_cache.sh set ln_default_wallet_channels_balance "${ln_lnd_wallet_channels_balance}"
            /home/admin/_cache.sh set ln_default_wallet_channels_pending "${ln_lnd_wallet_channels_pending}"
          fi
        else
          echo "# ERROR --> ${error}"
        fi
      fi

      # check if fees needs update
      source <(/home/admin/_cache.sh valid \
        ln_lnd_${CHAIN}net_fees_daily \
        ln_lnd_${CHAIN}net_fees_weekly \
        ln_lnd_${CHAIN}net_fees_month \
        ln_lnd_${CHAIN}net_fees_total \
      )
      if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
        source <(/home/admin/_cache.sh valid \
        ln_default_fees_total \
        )
      fi
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_LONG} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net fees"
        source <(timeout 30s /home/admin/config.scripts/lnd.monitor.sh ${CHAIN}net fees)
        if [ "${error}" == "" ]; then
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_fees_daily "${ln_lnd_fees_daily}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_fees_weekly "${ln_lnd_fees_weekly}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_fees_month "${ln_lnd_fees_month}"
          /home/admin/_cache.sh set ln_lnd_${CHAIN}net_fees_total "${ln_lnd_fees_total}"
          if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
            /home/admin/_cache.sh set ln_default_fees_total "${ln_lnd_fees_total}"
          fi
        else
          echo "# ERROR --> ${error}"
        fi
      fi
    fi
  done

  ###################
  # Lightning (Core Lightning)

  # loop thru mainet, testnet & signet
  networks=( "main" "test" "sig" )
  for CHAIN in "${networks[@]}"
  do

    # skip if network is not on by config
    if [ "${CHAIN}" == "main" ] && [ "${cl}" != "on" ]; then
      #echo "skip c-lightning mainnet scan - because its off"
      continue
    fi
    if [ "${CHAIN}" == "test" ] && [ "${tcl}" != "on" ]; then
      #echo "skip c-lightning testnet scan - because its off"
      continue
    fi
    if [ "${CHAIN}" == "sig" ] && [ "${scl}" != "on" ]; then
      #echo "skip c-lightning signet scan - because its off"
      continue
    fi

    # check if default chain & lightning
    isDefaultChain=$(echo "${CHAIN}" | grep -c "${chain}")
    isDefaultLightning=$(echo "${lightning}" | grep -c "cl")

    # set intervals for non default & non-default (in seconds)
    CYCLE_QUICK=30
    CYCLE_MID=60
    CYCLE_LONG=90
    if [ "${isDefaultChain}" != "1" ] || [ "${isDefaultLightning}" != "1" ]; then
      CYCLE_QUICK=300
      CYCLE_MID=600
      CYCLE_LONG=900
    fi

    # TODO: c-lightning is seen as "always unlocked" for now - needs to be implemented later #2691

    # update basic status values always
    source <(/home/admin/_cache.sh valid \
      ln_cl_${CHAIN}net_version \
      ln_cl_${CHAIN}net_running \
      ln_cl_${CHAIN}net_ready \
      ln_cl_${CHAIN}net_online \
      ln_cl_${CHAIN}net_error_short \
      ln_cl_${CHAIN}net_error_full \
    )
    if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
      source <(/home/admin/_cache.sh valid \
      ln_default_version \
      ln_default_running \
      ln_default_ready \
      ln_default_online \
      ln_default_error_short \
      ln_default_error_full \
      )
    fi
    if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_QUICK} ]; then
      echo "updating: /home/admin/config.scripts/cl.monitor.sh ${CHAIN}net status"
      source <(timeout 30s /home/admin/config.scripts/cl.monitor.sh ${CHAIN}net status)
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_activated "1"
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_version "${ln_cl_version}"
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_running "${ln_cl_running}"
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_ready "${ln_cl_ready}"
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_online "${ln_cl_online}"
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_locked "${ln_cl_locked}"
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_error_short "${ln_cl_error_short}"
      /home/admin/_cache.sh set ln_cl_${CHAIN}net_error_full "${ln_cl_error_full}"
      if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
        /home/admin/_cache.sh set ln_default_activated "1"
        /home/admin/_cache.sh set ln_default_version "${ln_cl_version}"
        /home/admin/_cache.sh set ln_default_running "${ln_cl_running}"
        /home/admin/_cache.sh set ln_default_ready "${ln_cl_ready}"
        /home/admin/_cache.sh set ln_default_online "${ln_cl_online}"
        /home/admin/_cache.sh set ln_default_locked "${ln_cl_locked}"
        /home/admin/_cache.sh set ln_default_error_short "${ln_cl_error_short}"
        /home/admin/_cache.sh set ln_default_error_full "${ln_cl_error_full}"
      fi
    fi

    # update detail infos only when ready
    source <(/home/admin/_cache.sh meta ln_cl_${CHAIN}net_ready)
    if [ "${value}" == "1" ]; then

      # check if info needs update
      source <(/home/admin/_cache.sh valid \
        ln_cl_${CHAIN}net_alias \
        ln_cl_${CHAIN}net_address \
        ln_cl_${CHAIN}net_tor \
        ln_cl_${CHAIN}net_peers \
        ln_cl_${CHAIN}net_sync_chain \
        ln_cl_${CHAIN}net_channels_pending \
        ln_cl_${CHAIN}net_channels_active \
        ln_cl_${CHAIN}net_channels_inactive \
        ln_cl_${CHAIN}net_channels_total \
        ln_cl_${CHAIN}net_fees_total \
      )
      if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
        source <(/home/admin/_cache.sh valid \
        ln_default_alias \
        ln_default_address \
        ln_default_tor \
        ln_default_peers \
        ln_default_sync_chain \
        ln_default_channels_pending \
        ln_default_channels_active \
        ln_default_channels_inactive \
        ln_default_channels_total \
        ln_default_fees_total \
        )
      fi
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_MID} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/cl.monitor.sh ${CHAIN}net info"
        source <(timeout 30s /home/admin/config.scripts/cl.monitor.sh ${CHAIN}net info)
        if [ "${error}" == "" ]; then
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_alias "${ln_cl_alias}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_address "${ln_cl_address}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_tor "${ln_cl_tor}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_peers "${ln_cl_peers}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_sync_chain "${ln_cl_sync_chain}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_sync_progress "${ln_cl_sync_progress}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_channels_pending "${ln_cl_channels_pending}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_channels_active "${ln_cl_channels_active}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_channels_inactive "${ln_cl_channels_inactive}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_channels_total "${ln_cl_channels_total}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_fees_total "${ln_cl_fees_total}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_recovery_mode "${ln_cl_recovery_mode}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_recovery_done "${ln_cl_recovery_done}"

          if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
            /home/admin/_cache.sh set ln_default_alias "${ln_cl_alias}"
            /home/admin/_cache.sh set ln_default_address "${ln_cl_address}"
            /home/admin/_cache.sh set ln_default_tor "${ln_cl_tor}"
            /home/admin/_cache.sh set ln_default_peers "${ln_cl_fees_total}"
            /home/admin/_cache.sh set ln_default_sync_chain "${ln_cl_sync_chain}"
            /home/admin/_cache.sh set ln_default_sync_progress "${ln_cl_sync_progress}"
            /home/admin/_cache.sh set ln_default_hannels_pending "${ln_cl_channels_pending}"
            /home/admin/_cache.sh set ln_default_channels_active "${ln_cl_channels_active}"
            /home/admin/_cache.sh set ln_default_channels_inactive "${ln_cl_channels_inactive}"
            /home/admin/_cache.sh set ln_default_channels_total "${ln_cl_channels_total}"
            /home/admin/_cache.sh set ln_default_fees_total "${ln_cl_fees_total}"
            /home/admin/_cache.sh set ln_default_recovery_mode "${ln_cl_recovery_mode}"
            /home/admin/_cache.sh set ln_default_recovery_done "${ln_cl_recovery_done}"
          fi
        else
          echo "# ERROR --> ${error}"
        fi
      fi

      # check if wallet needs update
      source <(/home/admin/_cache.sh valid \
        ln_cl_${CHAIN}net_wallet_onchain_balance \
        ln_cl_${CHAIN}net_wallet_onchain_pending \
        ln_cl_${CHAIN}net_wallet_channels_balance \
        ln_cl_${CHAIN}net_wallet_channels_pending \
      )
      if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ] && [ "${stillvalid}" == "1" ]; then
        source <(/home/admin/_cache.sh valid \
        ln_default_wallet_onchain_balance \
        ln_default_wallet_onchain_pending \
        ln_default_wallet_channels_balance \
        ln_default_wallet_channels_pending \
        )
      fi
      if [ "${stillvalid}" == "0" ] || [ ${age} -gt ${CYCLE_MID} ]; then
        error=""
        echo "updating: /home/admin/config.scripts/cl.monitor.sh ${CHAIN}net wallet"
        source <(timeout 30s /home/admin/config.scripts/cl.monitor.sh ${CHAIN}net wallet)
        if [ "${error}" == "" ]; then
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_wallet_onchain_balance "${ln_cl_wallet_onchain_balance}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_wallet_onchain_pending "${ln_cl_wallet_onchain_pending}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_wallet_channels_balance "${ln_cl_wallet_channels_balance}"
          /home/admin/_cache.sh set ln_cl_${CHAIN}net_wallet_channels_pending "${ln_cl_wallet_channels_pending}"
          if [ "${isDefaultLightning}" == "1" ] && [ "${isDefaultChain}" == "1" ]; then
            /home/admin/_cache.sh set ln_default_wallet_onchain_balance "${ln_cl_wallet_onchain_balance}"
            /home/admin/_cache.sh set ln_default_wallet_onchain_pending "${ln_cl_wallet_onchain_pending}"
            /home/admin/_cache.sh set ln_default_wallet_channels_balance "${ln_cl_wallet_channels_balance}"
            /home/admin/_cache.sh set ln_default_wallet_channels_pending "${ln_cl_wallet_channels_pending}"
          fi
        else
          echo "# ERROR --> ${error}"
        fi
      fi
    fi
  done

  ##################################
  # DEFAULT & SUMMARIZED SYNC STATUS

  btc_default_sync_initial_done=0
  btc_all_sync_initial_done=1
  ln_default_sync_initial_done=0
  ln_all_sync_initial_done=1
  blitz_sync_initial_done=0
  networks=( "main" "test" "sig" )
  sedondLayers=( "lnd" "cl" )

  # if default is mainnet, then consider mainnet=on
  if [ "${chain}" == "main" ]; then
    mainnet="on"
  fi

  # loop over all chains
  for CHAIN in "${networks[@]}"
  do

    # skip if this network is not switched on
    btc_service_name="${CHAIN}net"
    if [ "${!btc_service_name}" != "on" ]; then
      echo "skipping because ${btc_service_name}=${!btc_service_name}"
      continue
    fi

    # get values from cache
    source <(/home/admin/_cache.sh meta btc_${CHAIN}net_sync_initial_done)
    flagBtcDone="${value}"

    # check if default
    if [ "${CHAIN}" == "${chain}" ]; then
      btc_default_sync_initial_done="${flagBtcDone}"
    fi

    # check for all btc sync
    if [ "${flagBtcDone}" != "1" ]; then
      btc_all_sync_initial_done=0
    fi

    # sub loop over all layer 2 on that chain
    for LN in "${sedondLayers[@]}"
    do

      # skip if this variant is not switched on
      ln_service_name="${LN}"
      if [ "${CHAIN}" == "test" ]; then
        ln_service_name="t${LN}"
      fi
      if [ "${CHAIN}" == "sig" ]; then
        ln_service_name="s${LN}"
      fi
      if [ "${!ln_service_name}" != "on" ]; then
        echo "skipping because ${ln_service_name}=${!ln_service_name}"
        continue
      fi

      # get values from cache
      source <(/home/admin/_cache.sh meta ln_${LN}_${CHAIN}net_sync_initial_done)
      flagLNSyncDone="${value}"

      # check if default
      if [ "${CHAIN}" == "${chain}" ] && [ "${LN}" == "${lightning}" ]; then
        ln_default_sync_initial_done="${flagLNSyncDone}"
      fi

      # check for all ln sync
      if [ "${flagLNSyncDone}" != "1" ]; then
        ln_all_sync_initial_done=0
      fi

    done
  done

  # finalize & writing results to cache
  if [ "${lightning}" == "" ] || [ "${lightning}" == "none" ]; then
    ln_all_sync_initial_done=""
    ln_default_sync_initial_done=""
    blitz_sync_initial_done="${btc_all_sync_initial_done}"
    blitz_default_sync_initial_done="${btc_default_sync_initial_done}"
  else
    # only if ALL btc & ln sync done (multiple can be active) - the complete blitz has done syncing
    if [ "${btc_all_sync_initial_done}" == "1" ] && [ "${ln_all_sync_initial_done}" == "1" ]; then
      blitz_sync_initial_done="1"
    fi
    # only if DEFAULT btc & ln sync done - the complete blitz has done syncing
    if [ "${btc_default_sync_initial_done}" == "1" ] && [ "${ln_default_sync_initial_done}" == "1" ]; then
      blitz_default_sync_initial_done="1"
    fi
  fi
  /home/admin/_cache.sh set blitz_sync_initial_done "${blitz_sync_initial_done}"
  /home/admin/_cache.sh set blitz_default_sync_initial_done "${blitz_default_sync_initial_done}"
  /home/admin/_cache.sh set btc_default_sync_initial_done "${btc_default_sync_initial_done}"
  /home/admin/_cache.sh set btc_all_sync_initial_done "${btc_all_sync_initial_done}"
  /home/admin/_cache.sh set ln_default_sync_initial_done "${ln_default_sync_initial_done}"
  /home/admin/_cache.sh set ln_all_sync_initial_done "${ln_all_sync_initial_done}"

  #################
  # DONE

  # calculate how many seconds the script was running
  endTime=$(date +%s)
  runTime=$((${endTime}-${startTime}))

  # write info on scan runtime into cache (use as signal that the first systemscan worked)
  /home/admin/_cache.sh set systemscan_runtime "${runTime}"
  echo "SystemScan Loop done in ${runTime} seconds"

  # log warning if script took too long
  if [ ${runTime} -gt ${MINUTE} ]; then
    echo "WARNING: HANGING SYSTEM ... systemscan loop took too long (${runTime} seconds)!" 1>&2
    /home/admin/_cache.sh increment system_count_longscan
  fi

  # small sleep before next loop
  sleep 3

  # if was started with special parameter
  if [ "${ONLY_ONE_LOOP}" == "1" ]; then
    echo "Exiting because ONLY_ONE_LOOP==1"
    exit 0
  fi

done
