#!/bin/bash

# This script runs on after start in background
# as a service and gets restarted on failure
# it runs ALMOST every seconds

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# LOGS see: sudo journalctl -f -u background

echo "_background.sh STARTED"
echo "INFO: _background.sh loop started - sudo journalctl -f -u background" >> /home/admin/raspiblitz.log

# global vars
blitzTUIHeartBeatLine=""
/home/admin/_cache.sh set blitzTUIRestarts "0"

# determine correct raspberrypi boot drive path (that easy to access when sd card is insert into laptop)
raspi_bootdir=""
if [ -d /boot/firmware ]; then
  raspi_bootdir="/boot/firmware"
elif [ -d /boot ]; then
  raspi_bootdir="/boot"
fi
echo "# raspi_bootdir(${raspi_bootdir})"

counter=0
while [ 1 ]
do

  ###############################
  # Prepare this loop
  ###############################

  # count up
  counter=$(($counter+1))

  # limit counter to max seconds per week:
  # 604800 = 60sec * 60min * 24hours * 7days
  if [ ${counter} -gt 604800 ]; then
    counter=0
    echo "counter zero reset"
  fi

  # gather the uptime seconds
  upSeconds=$(cat /proc/uptime | grep -o '^[0-9]\+')

  # source info & config file fresh on every loop
  source ${infoFile} 2>/dev/null
  source ${configFile} 2>/dev/null

  ####################################################
  # SKIP BACKGROUND TASK LOOP ON CERTAIN SYSTEM STATES
  # https://github.com/rootzoll/raspiblitz/issues/160
  ####################################################

  if [ "${state}" == "" ] || [ "${state}" == "copysource" ] || [ "${state}" == "copytarget" ]; then
    echo "skipping background loop (${counter}) - state(${state})"
    sleep 1
    continue
  fi

  ####################################################
  # Trigger Final Setup
  ####################################################

  if [ "${setupPhase}" != "done" ] && [ "${state}" == "donefinal" ]; then
    echo "trigger final setup tasks & reboot ..."
    /home/admin/_provision.xfinal.sh
    sleep 120
    exit
  fi

  ####################################################
  # SKIP REST OF THE TASKS IF STILL IN SETUP PHASE
  ####################################################

  if [ "${setupPhase}" != "done" ]; then
    echo "skipping rest of tasks because still in setupPhase(${setupPhase})"
    sleep 1
    continue
  fi

  ####################################################
  # MONITOR LOG SIZES
  # https://github.com/rootzoll/raspiblitz/issues/2659
  ####################################################

  # once a day
  recheckLogs=$((($counter % 86400)+2))
  if [ ${recheckLogs} -eq 1 ]; then
    echo "*** MONITOR LOG SIZES  ***"
    journalctl --vacuum-size=100M
  fi

  ####################################################
  # RECHECK DHCP-SERVER
  # https://github.com/rootzoll/raspiblitz/issues/160
  ####################################################

  # every 5 minutes
  recheckDHCP=$((($counter % 300)+1))
  if [ ${recheckDHCP} -eq 1 ]; then
    echo "*** RECHECK DHCP-SERVER  ***"

    # get the local network IP
    localip=$(hostname -I | awk '{print $1}')
    echo "localip(${localip})"

    # detect a missing DHCP config
    if [ "${localip:0:4}" = "169." ]; then
      echo "Missing DHCP detected ..."
    else
      echo "DHCP OK"
    fi

  fi

  ####################################################
  # RECHECK PUBLIC IP
  #
  # when public IP changes
  #  -  restart bitcoind with new IP
  #  -  restart LND with new IP (if autounlock is enabled)
  #  -  restart BTCRPCexplorer if enabled in config or running)
  ####################################################

  # every 15min - not too often
  # because its a ping to external service
  recheckPublicIP=$((($counter % 1800)+1))

  # prevent when lndAddress is set
  if [ ${#lndAddress} -gt 3 ]; then
    recheckPublicIP=0
  fi

  # prevent also when runBehindTor is on
  if [ "${runBehindTor}" = "1" ] || [ "${runBehindTor}" = "on" ]; then
    recheckPublicIP=0
  fi

  updateDynDomain=0
  if [ ${recheckPublicIP} -eq 1 ]; then
    echo "*** RECHECK PUBLIC IP ***"

    # execute only after setup when config exists
    publicIPChanged=$(/home/admin/config.scripts/internet.sh update-publicip | grep -c 'ip_changed=1')

    # check if changed
    if [ ${publicIPChanged} -gt 0 ]; then

      echo "*** change of public IP detected ***"

      # store the old IP address
      publicIP_Old="${publicIP}"
      # refresh data
      source /mnt/hdd/raspiblitz.conf
      # store the new IP address
      publicIP_New="${publicIP}"
      # some log output
      echo "  old: ${publicIP_Old}"
      echo "  new: ${publicIP_New}"

      # if we run on IPv6 only, the global IPv6 address at the current network device (e.g: eth0) is the public IP
      if [ "${ipv6}" = "on" ]; then
        # if the old or the new IPv6 address is "::1" something has gone wrong in "internet.sh update-publicip" => no need to restart services
        if [ "${publicIP_Old}" != "::1" ] && [ "${publicIP_New}" != "::1" ]; then
          # restart bitcoind as the global IP is stored in the node configuration
          # and we will get more connections if this matches our real IP address
          # otherwise the bitcoin-node connections will slowly decline
          echo "IPv6 only is enabled => restart bitcoind to pickup up new publicIP as local IP"
          systemctl stop bitcoind
          sleep 3
          systemctl start bitcoind

          # if BTCRPCexplorer is currently running
          # it needs to be restarted to pickup the new IP for its "Node Status Page"
          # but this is only needed in IPv6 only mode
          breIsRunning=$(systemctl status btc-rpc-explorer 2>/dev/null | grep -c 'active (running)')
          if [ ${breIsRunning} -eq 1 ]; then
            echo "BTCRPCexplorer is running => restart BTCRPCexplorer to pickup up new publicIP for the bitcoin node"
            systemctl stop btc-rpc-explorer
            systemctl start btc-rpc-explorer
          else
            echo "new publicIP but no BTCRPCexplorer restart because not running"
          fi
        else
          echo "IPv6 only is ON, but publicIP_Old OR publicIP_New is equal ::1 => no need to restart bitcoind nor BTCRPCexplorer"
        fi
      else
        echo "IPv6 only is OFF => no need to restart bitcoind nor BTCRPCexplorer"
      fi

      # only restart LND if auto-unlock is activated
      # AND neither the old nor the new IPv6 address is "::1"
      source <(/home/admin/config.scripts/lnd.autounlock.sh status)
      if [ "${autoUnlock}" = "on" ]; then
        if [ "${publicIP_Old}" != "::1" ] && [ "${publicIP_New}" != "::1" ]; then
          echo "restart LND to pickup up new publicIP"
          systemctl stop lnd
          systemctl start lnd
        else
          echo "publicIP_Old OR publicIP_New is equal ::1 => no need to restart LND"
        fi
      else
        echo "new publicIP but no LND restart because no auto-unlock"
      fi

      # trigger update if dynamic domain (if set)
      updateDynDomain=1

    else
        echo "public IP has not changed"
    fi

  fi

  ###############################
  # UPDATE DYNAMIC DOMAIN
  # like afraid.org
  # ! experimental
  ###############################

  # if not activated above, update every 6 hours
  if [ ${updateDynDomain} -eq 0 ]; then
    # dont +1 so that it gets executed on first loop
    updateDynDomain=$(($counter % 21600))
  fi
  if [ ${updateDynDomain} -eq 1 ]; then
    echo "*** UPDATE DYNAMIC DOMAIN ***"
    # check if update URL for dyn Domain is set
    if [ ${#dynUpdateUrl} -gt 0 ]; then
      /home/admin/config.scripts/internet.dyndomain.sh update
    else
      echo "'dynUpdateUrl' not set in ${configFile}"
    fi
  fi

  ###############################
  # Blockchain Sync Monitor
  ###############################

  # check every 1min
  recheckSync=$(($counter % 60))
  if [ ${recheckSync} -eq 1 ] && [ "${chain}" == "main" ]; then
    source <(/home/admin/config.scripts/bitcoin.monitor.sh mainnet network)
    echo "Blockchain Sync Monitoring: peers=${btc_peers}"
    if [ "${btc_peers}" == "0" ] && [ "${btc_running}" == "1" ]; then
      echo "Blockchain Sync Monitoring: ZERO PEERS DETECTED .. doing out-of-band kickstart"
      /home/admin/config.scripts/bitcoin.monitor.sh mainnet peer-kickstart
    fi
    if [ "${i2pd}" == "on" ] && [ "${btc_peers_i2p}" == "0" ] && [ "${btc_running}" == "1" ]; then
      echo "Blockchain Sync Monitoring: IP2TOR 0 peers .. doing out-of-band kickstart"
      /home/admin/config.scripts/bitcoin.monitor.sh mainnet peer-kickstart i2p
    fi
  fi

  ###############################
  # SYSTEM LOG FILE SIZES
  ###############################

  # check every 15min
  recheckSync=$(($counter % 900))
  if [ ${recheckSync} -eq 1 ]; then
    echo "*** CHECK LOG FILE SIZES ***"
    # check if log file is getting too big
    logsMegaByte=$(sudo du -c -m /var/log | grep "total" | awk '{print $1;}')
    if [ ${logsMegaByte} -gt 5000 ]; then
      echo "WARN # Logs /var/log in are bigger then 5GB .. starting repair"
      debuginfo=$(ls -la /var/log/ 2>/dev/null)
      # dont delete directories - can make services crash
      sudo rm /var/log/*
      sudo touch /var/log/auth.log
      sudo chown root:adm /var/log/auth.log
      sudo service rsyslog restart
      /home/admin/config.scripts/blitz.error.sh _background.sh "log-delete" "REPAIR: /var/log/ >5GB" "Logs in /var/log in were bigger then 5GB and got emergency delete to prevent fillup." "${debuginfo}"
      sleep 10
    else
      echo "OK - logs are at ${logsMegaByte} MB - within safety limit"
    fi
    echo ""
  fi

  ####################################################
  # MONITOR Initial Syncing of Bitcoin & Lightning
  # - turn off recovery mode
  ####################################################

  recheckIBD=$((($counter % 10)+1))
  if [ ${recheckIBD} -eq 1 ]; then
    # loop thru mainet, testnet & signet
    networks=( "main" "test" "sig" )
    for CHAIN in "${networks[@]}"
    do

      # gat values from cache
      source <(/home/admin/_cache.sh meta btc_${CHAIN}net_sync_initial_started)
      flagBtcStarted="${value}"
      source <(/home/admin/_cache.sh meta btc_${CHAIN}net_sync_initialblockdownload)
      flagBtcActive="${value}"
      source <(/home/admin/_cache.sh meta btc_${CHAIN}net_synced)
      flagBtcSynced="${value}"
      source <(/home/admin/_cache.sh meta btc_${CHAIN}net_online)
      flagBtcOnline="${value}"
      source <(/home/admin/_cache.sh meta btc_${CHAIN}net_sync_initial_done)
      flagBtcDone="${value}"
      #echo "CHAIN(${CHAIN}) flagBtcStarted(${flagBtcStarted}) flagBtcActive(${flagBtcActive}) flagBtcSynced(${flagBtcSynced}) flagBtcOnline(${flagBtcOnline}) flagBtcDone(${flagBtcDone})"

      # first check if flags need to be reset (manually delete of blockchain)
      if [ "${flagBtcDone}" == "1" ] && [ "${flagBtcActive}" == "1" ]; then
        flagBtcDone=0
        /home/admin/config.scripts/blitz.conf.sh set btc_${CHAIN}net_sync_initial_done ${flagBtcDone} /home/admin/raspiblitz.info
        echo "EVENT --> btc_${CHAIN}net_sync_initial_done changed to ${flagBtcDone}"
      fi

      # when started flag not set yet - but is now active --> set flag
      if [ "${flagBtcStarted}" != "1" ] && [ "${flagBtcActive}" == "1" ]; then
        flagBtcStarted=1
        /home/admin/_cache.sh set btc_${CHAIN}net_sync_initial_started ${flagBtcStarted}
        echo "EVENT --> btc_${CHAIN}net_sync_initial_started changed to ${flagBtcStarted}"
      fi

      # when started done is set - but not not active anymore --> end of IDB event detected
      if [ "${flagBtcDone}" == "0" ] && [ "${flagBtcOnline}" == "1" ] && [ "${flagBtcSynced}" == "1" ]; then
        flagBtcDone=1
        /home/admin/config.scripts/blitz.conf.sh set btc_${CHAIN}net_sync_initial_done ${flagBtcDone} /home/admin/raspiblitz.info
        echo "EVENT --> btc_${CHAIN}net_sync_initial_done changed to ${flagBtcDone}"
      fi

      # loop thru all second layers
      sedondLayers=( "lnd" "cl" )
      for LN in "${sedondLayers[@]}"
      do

        source <(/home/admin/_cache.sh meta ln_${LN}_${CHAIN}net_sync_chain)
        flagLnSyncChain="${value}"
        source <(/home/admin/_cache.sh meta ln_${LN}_${CHAIN}net_online)
        flagLnOnline="${value}"
        source <(/home/admin/_cache.sh meta ln_${LN}_${CHAIN}net_recovery_mode)
        flagLNRecoveryMode="${value}"
        source <(/home/admin/_cache.sh meta ln_${LN}_${CHAIN}net_recovery_done)
        flagLNRecoveryDone="${value}"
        source <(/home/admin/_cache.sh meta ln_${LN}_${CHAIN}net_sync_initial_done)
        flagLNSyncDone="${value}"
        #echo "LN(${LN}) flagLnSyncChain(${flagLnSyncChain}) flagLnOnline(${flagLnOnline}) flagLNRecoveryMode(${flagLNRecoveryMode}) flagLNRecoveryDone(${flagLNRecoveryDone}) flagLNSyncDone(${flagLNSyncDone})"

        # first check if flags need to be reset (manually a rescan was triggered)
        if [ "${flagLNSyncDone}" == "1" ] && [ "${flagLNRecoveryMode}" == "1" ]; then
          flagLNSyncDone=0
          /home/admin/config.scripts/blitz.conf.sh set ln_${LN}_${CHAIN}net_sync_initial_done ${flagLNSyncDone} /home/admin/raspiblitz.info
          echo "EVENT --> ln_${LN}_${CHAIN}net_sync_initial_done to ${flagLNSyncDone}"
        fi

        # when flag initial sync not done yet - but all chains are in sync with network
        if [ "${flagLNSyncDone}" == "0" ] && [ "${flagBtcDone}" == "1" ] && [ "${flagLnOnline}" == "1" ] && [ "${flagLnSyncChain}" == "1" ]; then

          # then only finished if no LNRecoveryMode or LNRecoveryDone
          if [ "${flagLNRecoveryMode}" == "0" ] || [ "${flagLNRecoveryDone}" == "1" ]; then

            # write event
            flagLNSyncDone=1
            /home/admin/config.scripts/blitz.conf.sh set ln_${LN}_${CHAIN}net_sync_initial_done ${flagLNSyncDone} /home/admin/raspiblitz.info
            echo "EVENT --> ln_${LN}_${CHAIN}net_sync_initial_done to ${flagLNSyncDone}"

            # LND if recovery mode was on - deactivate now
            if [ "${LN}" == "lnd" ] && [ "${flagLNRecoveryMode}" == "1" ]; then
              /home/admin/_cache.sh set ln_lnd_mainnet_recovery_mode 0
              /home/admin/config.scripts/lnd.backup.sh mainnet recoverymode off
            fi

            # CLN if recovery mode was on - deactivate now
            if [ "${LN}" == "cl" ] && [ "${flagLNRecoveryMode}" == "1" ]; then
              /home/admin/_cache.sh set ln_cl_mainnet_recovery_mode 0
              /home/admin/config.scripts/cl.backup.sh mainnet recoverymode off
            fi

          fi

        fi

      done

    done
  fi

  ####################################################
  # Check for end of Initial Blockhain & Lightning Sync
  # bitcoin mainnet only / special on dbcache size
  ####################################################

  # check every 60secs
  recheckIBD=$((($counter % 60)+1))
  if [ ${recheckIBD} -eq 1 ]; then

    # check if flag exists (gets created on setup)
    # this flag signals that an initial blockchain sync/chatchup was happening
    flagExists=$(ls /mnt/hdd/bitcoin/blocks/selfsync.flag 2>/dev/null | grep -c "selfsync.flag")
    if [ ${flagExists} -eq 1 ]; then

      source <(/home/admin/_cache.sh get btc_default_sync_initialblockdownload)
      if [ "${btc_default_sync_initialblockdownload}" == "0" ]; then

        echo "CHECK FOR END OF IBD --> reduce RAM for next reboot"

        # remove flag
        rm /mnt/hdd/bitcoin/blocks/selfsync.flag

        # set dbcache back to normal (to give room for other apps after reboot in the future)
        kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')

        # RP4 4GB
        if [ ${kbSizeRAM} -gt 3500000 ]; then
          echo "Detected RAM >=4GB --> normalizing bitcoin.conf"
          sed -i "s/^dbcache=.*/dbcache=512/g" /mnt/hdd/bitcoin/bitcoin.conf
        # RP4 2GB
        elif [ ${kbSizeRAM} -gt 1500000 ]; then
          echo "Detected RAM >=2GB --> normalizing bitcoin.conf"
          sed -i "s/^dbcache=.*/dbcache=256/g" /mnt/hdd/bitcoin/bitcoin.conf
        #RP3/4 1GB
        else
          echo "Detected RAM <=1GB --> normalizing bitcoin.conf"
          sed -i "s/^dbcache=.*/dbcache=128/g" /mnt/hdd/bitcoin/bitcoin.conf
        fi

        # relax sanning on sync progress (after 30 more secs)
        /home/admin/_cache.sh focus btc_default_sync_progress 10 30

      fi
    fi
  fi

  ###############################
  # BlitzTUI Monitoring
  ###############################

  # check every 30sec
  recheckBlitzTUI=$(($counter % 30))
  if [ "${touchscreen}" == "1" ] && [ ${recheckBlitzTUI} -eq 1 ]; then

    echo "BlitzTUI Monitoring Check"
    if [ -d "/var/cache/raspiblitz" ]; then
      latestHeartBeatLine=$(tail -n 300 /var/cache/raspiblitz/pi/blitz-tui.log | grep beat | tail -n 1)
    else
      latestHeartBeatLine=$(tail -n 300 /home/pi/blitz-tui.log | grep beat | tail -n 1)
    fi
    if [ ${#blitzTUIHeartBeatLine} -gt 0 ]; then
      #echo "blitzTUIHeartBeatLine(${blitzTUIHeartBeatLine})"
      #echo "latestHeartBeatLine(${latestHeartBeatLine})"
      if [ "${blitzTUIHeartBeatLine}" == "${latestHeartBeatLine}" ]; then
        echo "FAIL - still no new heart beat .. restarting BlitzTUI"
        source <(/home/admin/_cache.sh increment system_count_start_tui)
        init 3 ; sleep 2 ; init 5
      fi
    else
      echo "blitzTUIHeartBeatLine is empty - skipping check"
    fi
    blitzTUIHeartBeatLine="${latestHeartBeatLine}"
  fi

  ###############################
  # SCB Monitoring (LND)
  ###############################

  # check every 1min (only when lnd active)
  recheckSCB=0
  if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
    recheckSCB=$(($counter % 60))
  fi
  if [ ${recheckSCB} -eq 1 ]; then
    #echo "SCB Monitoring ..."
    source ${configFile}
    # check if channel.backup exists
    scbPath=/mnt/hdd/lnd/data/chain/${network}/${chain}net/channel.backup
    scbExists=$(ls $scbPath 2>/dev/null | grep -c 'channel.backup')
    if [ ${scbExists} -eq 1 ]; then

      # timestamp backup filename
      timestampedFileName=channel-$(date "+%Y%m%d-%H%M%S").backup
      localBackupDir=/home/admin/backups/scb
      localBackupPath=${localBackupDir}/channel.backup
      localTimestampedPath=${localBackupDir}/${timestampedFileName}

      #echo "Found Channel Backup File .. check if changed .."
      md5checksumORG=$(md5sum $scbPath 2>/dev/null | head -n1 | cut -d " " -f1)
      md5checksumCPY=$(md5sum $localBackupPath 2>/dev/null | head -n1 | cut -d " " -f1)
      if [ "${md5checksumORG}" != "${md5checksumCPY}" ]; then
        echo "--> Channel Backup File changed"

        # make copy to sd card (as local basic backup)
        mkdir -p ${localBackupDir} 2>/dev/null
        cp $scbPath $localBackupPath
        if [ $? -eq 0 ]; then
          echo "OK channel.backup copied to '${localBackupPath}'"
        else
          logger -p daemon.err "_background.sh FAIL channel.backup copy to '${localBackupPath}'"
          echo "FAIL channel.backup copy to '${localBackupPath}'"
        fi

        cp $scbPath $localTimestampedPath
        if [ $? -eq 0 ]; then
          echo "OK channel.backup copied to '${localTimestampedPath}'"
        else
          logger -p daemon.err "_background.sh FAIL channel.backup copy to '${localTimestampedPath}'"
          echo "FAIL channel.backup copy to '${localTimestampedPath}'"
        fi

        # copy to boot drive (for easy recovery)
        if [ "${raspi_bootdir}" != "" ]; then
          cp $scbPath ${raspi_bootdir}/channel.backup
          if [ $? -eq 0 ]; then
            echo "OK channel.backup copied to '${raspi_bootdir}/channel.backup'"
          else
            logger -p daemon.err "_background.sh FAIL channel.backup copy to '${raspi_bootdir}/channel.backup'"
            echo "FAIL channel.backup copy to '${raspi_bootdir}/channel.backup'"
          fi
        else
          echo "No boot drive found - skip copy to boot"
        fi

        # check if a additional local backup target is set
        # see ./config.scripts/blitz.backupdevice.sh
        if [ "${localBackupDeviceUUID}" != "" ] && [ "${localBackupDeviceUUID}" != "off" ]; then

          # check if device got mounted on "/mnt/backup" (gets mounted by _bootstrap.sh)
          backupDeviceExists=$(df | grep -c "/mnt/backup")
          if [ ${backupDeviceExists} -gt 0 ]; then

            echo "--> Additional Local Backup Device"
            cp ${localBackupPath} /mnt/backup/
            cp ${localTimestampedPath} /mnt/backup/

            # check results
            result=$?
            if [ ${result} -eq 0 ]; then
              echo "OK - Successful Copy to additional Backup Device"
            else
              echo "FAIL - Copy to additional Backup Device exited with ${result}"
            fi

          else
            echo "FAIL - BackupDrive mount - check if device is connected & UUID is correct" >> $logFile
          fi
        fi

        # check if a SCP backup target is set
        # parameter in raspiblitz.conf:
        # scpBackupTarget='[USER]@[SERVER]:[DIRPATH-WITHOUT-ENDING-/]'
        # optionally a custom option string for the scp command can be set with
        # scpBackupOptions='[YOUR-CUSTOM-OPTIONS]'
        # On target server add the public key of your RaspiBlitz to the authorized_keys for the user
        # https://www.linode.com/docs/security/authentication/use-public-key-authentication-with-ssh/
        if [ ${#scpBackupTarget} -gt 0 ]; then
          echo "--> Offsite-Backup SFTP Server"
          if [ "${scpBackupOptions}" == "" ]; then
            scpBackupOptions="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
          fi
          # its ok to ignore known host, because data is encrypted (worst case of MiM would be: no offsite channel backup)
          # but its more likely that without ignoring known host, script might not run thru and that way: no offsite channel backup
          scp ${scpBackupOptions} ${localBackupPath} ${scpBackupTarget}/
          scp ${scpBackupOptions} ${localTimestampedPath} ${scpBackupTarget}/
          result=$?
          if [ ${result} -eq 0 ]; then
            echo "OK - SCP Backup exited with 0"
          else
            echo "FAIL - SCP Backup exited with ${result}"
          fi
        fi

        # check if Nextcloud backups are enabled
        if [ $nextcloudBackupServer ] && [ $nextcloudBackupUser ] && [ $nextcloudBackupPassword ]; then
          echo "--> Offsite-Backup Nextcloud"
          source <(/home/admin/config.scripts/nextcloud.upload.sh upload ${localBackupPath})
          source <(/home/admin/config.scripts/nextcloud.upload.sh upload ${localTimestampedPath})
          if [ ${#err} -gt 0 ]; then
            echo "FAIL -  ${err}"
          else
            echo "OK - ${upload}"
          fi
        fi

      #else
      #  echo "Channel Backup File not changed."
      fi
    #else
    #  echo "No Channel Backup File .."
    fi
  fi

  ###################################
  # Emergency Backup Monitoring (CLN)
  ###################################

  # check every 1min for cln
  recheckER=0
  if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
    recheckER=$(($counter % 60))
  fi
  if [ ${recheckER} -eq 1 ]; then
    #echo "ER Monitoring ..."
    source ${configFile}
    source <(/home/admin/config.scripts/network.aliases.sh getvars cl ${chain}net)
    # check if emergency.recover exists
    erPath=/home/bitcoin/.lightning/${CLNETWORK}/emergency.recover
    erExists=$(ls $erPath 2>/dev/null | grep -c 'emergency.recover')
    if [ ${erExists} -eq 1 ]; then

      # timestamp backup filename
      timestampedFileName=${netprefix}emergency-$(date "+%Y%m%d-%H%M%S").recover
      localBackupDir=/home/admin/backups/er
      localBackupPath=${localBackupDir}/emergency.recover
      localTimestampedPath=${localBackupDir}/${timestampedFileName}

      #echo "Found Channel Backup File .. check if changed .."
      md5checksumORG=$(md5sum $erPath 2>/dev/null | head -n1 | cut -d " " -f1)
      md5checksumCPY=$(md5sum $localBackupPath 2>/dev/null | head -n1 | cut -d " " -f1)
      if [ "${md5checksumORG}" != "${md5checksumCPY}" ]; then
        echo "--> Channel Backup File changed"

        # make copy to sd card (as local basic backup)
        mkdir -p /home/admin/backups/er/ 2>/dev/null
        cp $erPath $localBackupPath
        cp $erPath $localTimestampedPath
        cp $erPath ${raspi_bootdir}/${netprefix}emergency.recover
        echo "OK emergency.recover copied to '${localBackupPath}' and '${localTimestampedPath}' and '${raspi_bootdir}/${netprefix}emergency.recover'"

        # check if a additional local backup target is set
        # see ./config.scripts/blitz.backupdevice.sh
        if [ "${localBackupDeviceUUID}" != "" ] && [ "${localBackupDeviceUUID}" != "off" ]; then

          # check if device got mounted on "/mnt/backup" (gets mounted by _bootstrap.sh)
          backupDeviceExists=$(df | grep -c "/mnt/backup")
          if [ ${backupDeviceExists} -gt 0 ]; then

            echo "--> Additional Local Backup Device"
            cp ${localBackupPath} /mnt/backup/
            cp ${localTimestampedPath} /mnt/backup/

            # check results
            result=$?
            if [ ${result} -eq 0 ]; then
              echo "OK - Successful Copy to additional Backup Device"
            else
              echo "FAIL - Copy to additional Backup Device exited with ${result}"
            fi

          else
            echo "FAIL - BackupDrive mount - check if device is connected & UUID is correct" >> $logFile
          fi
        fi

        # check if a SCP backup target is set
        # parameter in raspiblitz.conf:
        # scpBackupTarget='[USER]@[SERVER]:[DIRPATH-WITHOUT-ENDING-/]'
        # optionally a custom option string for the scp command can be set with
        # scpBackupOptions='[YOUR-CUSTOM-OPTIONS]'
        # On target server add the public key of your RaspiBlitz to the authorized_keys for the user
        # https://www.linode.com/docs/security/authentication/use-public-key-authentication-with-ssh/
        if [ ${#scpBackupTarget} -gt 0 ]; then
          echo "--> Offsite-Backup SFTP Server"
          if [ "${scpBackupOptions}" == "" ]; then
            scpBackupOptions="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
          fi
          # its ok to ignore known host, because data is encrypted (worst case of MiM would be: no offsite channel backup)
          # but its more likely that without ignoring known host, script might not run thru and that way: no offsite channel backup
          scp ${scpBackupOptions} ${localBackupPath} ${scpBackupTarget}/
          scp ${scpBackupOptions} ${localTimestampedPath} ${scpBackupTarget}/
          result=$?
          if [ ${result} -eq 0 ]; then
            echo "OK - SCP Backup exited with 0"
          else
            echo "FAIL - SCP Backup exited with ${result}"
          fi
        fi

        # check if Nextcloud backups are enabled
        if [ $nextcloudBackupServer ] && [ $nextcloudBackupUser ] && [ $nextcloudBackupPassword ]; then
          echo "--> Offsite-Backup Nextcloud"
          source <(/home/admin/config.scripts/nextcloud.upload.sh upload ${localBackupPath})
          source <(/home/admin/config.scripts/nextcloud.upload.sh upload ${localTimestampedPath})
          if [ ${#err} -gt 0 ]; then
            echo "FAIL -  ${err}"
          else
            echo "OK - ${upload}"
          fi
        fi

      #else
      #  echo "Channel Backup File not changed."
      fi
    #else
    #  echo "No Channel Backup File .."
    fi
  fi

  ###############################
  # SSL CERT RENEWAL
  ###############################
  # check every 10min
  recheckCert=$((($counter % 600)+1))
  if [ ${recheckCert} -eq 10 ]; then

    # TODO: check if letsencrypt certs are valid for more than 10 days & renew if not

    # sets self-signed certs or letsencrypt certs (if valid) to nginx
    sudo -u admin /home/admin/config.scripts/internet.letsencrypt.sh refresh-nginx-certs
  fi

  ###############################
  # SUBSCRIPTION RENEWS
  ###############################

  # check every 20min
  recheckSubscription=$((($counter % 1200)+1))
  if [ ${recheckSubscription} -eq 1 ]; then
    # IP2TOR subscriptions (that will need renew in next 20min = 1200 secs)
    sudo -u admin /home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscriptions-renew 1800
  fi

  ###############################
  # RAID data check (BRTFS)
  ###############################
  # see https://github.com/rootzoll/raspiblitz/issues/360#issuecomment-467698260

  # check every hour
  recheckRAID=$((($counter % 3600)+1))
  if [ ${recheckRAID} -eq 1 ]; then

    # check if BTRTFS raid is active & scrub
    logger -p info "background.sh - RAID data check"
    source <(/home/admin/config.scripts/blitz.datadrive.sh status)
    if [ "${isBTRFS}" == "1" ] && [ "${isRaid}" == "1" ]; then
      echo "STARTING BTRFS RAID DATA CHECK ..."
      btrfs scrub start /mnt/hdd/
    fi

  fi

  ###############################
  # Prepare next loop
  ###############################

  # sleep 1 sec
  sleep 1

done
