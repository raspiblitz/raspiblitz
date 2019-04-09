#!/bin/bash

### USER PI AUTOSTART (LCD Display)
# this script gets started by the autologin of the pi user and
# and its output is gets displayed on the LCD or the RaspiBlitz

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# check that user is pi
if [ "$USER" != "pi" ]; then
  echo "plz run as user pi --> su pi"
  exit 1
fi

# display a 10s startup time
source /home/admin/_version.info
dialog --pause "  Starting RaspiBlitz v${codeVersion} ..." 8 58 12

# DISPLAY LOOP
chain=""
while :
    do

    ###########################
    # CHECK BASIC DATA
    ###########################   

    # get the local network IP to be displayed on the lCD
    localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

    # waiting for IP in general
    if [ ${#localip} -eq 0 ]; then
      l1="Waiting for Network ...\n"
      l2="Not able to get local IP.\n"
      l3="Is LAN cable connected?\n"
      dialog --backtitle "RaspiBlitz ${codeVersion}" --infobox "$l1$l2$l3" 5 40
      sleep 3
      continue
    fi

    # waiting for DHCP in general
    if [ "${localip:0:4}" = "169." ]; then
      l1="Waiting for DHCP ...\n"
      l2="Not able to get local IP.\n"
      l3="Will try reboot every 5min.\n"
      dialog --backtitle "RaspiBlitz ${codeVersion} (${localip})" --infobox "$l1$l2$l3" 5 40
      sleep 3
      continue
    fi

    # get config info if already available
    configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
    if [ ${configExists} -eq 1 ]; then
      source ${configFile}
    fi

    # if setup not marked as done (=100) load boostrap info file
    if [ "${setupStep}" != "100" ]; then
      source ${infoFile}
    fi

    # if no information available from files - set default
    if [ ${#setupStep} -eq 0 ]; then
     setupStep=0
    fi

    # before setup even started
    if [ ${setupStep} -eq 0 ]; then

      # check for internet connection
      online=$(ping 1.0.0.1 -c 1 -W 2 | grep -c '1 received')
      if [ ${online} -eq 0 ]; then
        # re-test with other server
        online=$(ping 8.8.8.8 -c 1 -W 2 | grep -c '1 received')
      fi
      if [ ${online} -eq 0 ]; then
        # re-test with other server
        online=$(ping 208.67.222.222 -c 1 -W 2 | grep -c '1 received')
      fi

      if [ ${online} -eq 0 ]; then
        message="no internet connection"

      # when in presync - get more info on progress
      elif [ "${state}" = "presync" ]; then
        # get blockchain sync progress
        blockchaininfo="$(sudo -u root ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 2>/dev/null)"
        message="starting"
        if [ ${#blockchaininfo} -gt 0 ]; then
          message="$(echo "${blockchaininfo}" | jq -r '.verificationprogress')"
          message=$(echo $message | awk '{printf( "%.2f%%", 100 * $1)}')
        fi

      # when old data - improve message
      elif [ "${state}" = "olddata" ]; then
          message="login for manual migration"

      # when no HDD - improve message
      elif [ "${state}" = "nohdd" ]; then
          message="Connect HHD"
      fi
      
      # setup process has not started yet
      l1="Login to your RaspiBlitz with:\n"
      l2="ssh admin@${localip}\n"
      l3="Use password: raspiblitz\n"
      boxwidth=$((${#localip} + 24))
      sleep 3
      dialog --backtitle "RaspiBlitz ${codeVersion} (${state}) - ${message}" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 5
      continue
    fi

    # check if recovering/upgrade is running
    if [ "${state}" = "recovering" ]; then
      if [ ${#message} -eq 0 ]; then
        message="Setup in Progress"
      fi
      l1="Upgrade/Recover/Provision\n"
      l2="---> ${message}\n"
      l3="Please keep running until reboot."
      boxwidth=$((${#localip} + 28))
      dialog --backtitle "RaspiBlitz ${codeVersion} (${state}) ${setupStep} ${localip}" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 3
      continue
    fi
    
    # if freshly recovered 
    if [ "${state}" = "recovered" ]; then
      l1="FINAL RECOVER LOGIN NEEDED:\n"
      l2="ssh admin@${localip}\n"
      l3="Use password: raspiblitz\n"
      boxwidth=$((${#localip} + 28))
      dialog --backtitle "RaspiBlitz ${codeVersion} (${state})" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 3
      continue
    fi

    # if re-indexing 
    if [ "${state}" = "reindex" ]; then
      l1="REINDEXING BLOCKCHAIN\n"
      l2="To monitor & detect finish:\n"
      l3="ssh admin@${localip}\n"
      boxwidth=$((${#localip} + 28))
      dialog --backtitle "RaspiBlitz ${codeVersion} (${state})" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 3
      continue
    fi

    # when setup is in progress - password has been changed
    if [ ${setupStep} -lt 100 ]; then
      l1="Login to your RaspiBlitz with:\n"
      l2="ssh admin@${localip}\n"
      l3="Use your Password A\n"
      boxwidth=$((${#localip} + 24))
      sleep 3
      dialog --backtitle "RaspiBlitz ${codeVersion} ${localip} - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 7
      continue
    fi

    ###########################
    # DISPLAY AFTER SETUP
    ###########################

    if [ "${state}" = "repair" ]; then
      l1="Repair Mode\n"
      l2="ssh admin@${localip}\n"
      l3="Use password: PasswordA\n"
      boxwidth=$((${#localip} + 28))
      dialog --backtitle "RaspiBlitz ${codeVersion} (${state}) ${setupStep} ${localip}" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 3
      continue
    fi

    if [ "${state}" = "retorrent" ]; then
      l1="Repair Mode- TORRENT\n"
      l2="ssh admin@${localip}\n"
      l3="Use password: PasswordA\n"
      boxwidth=$((${#localip} + 28))
      dialog --backtitle "RaspiBlitz ${codeVersion} (${state}) ${setupStep} ${localip}" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 3
      continue
    fi

    if [ "${state}" = "recopy" ]; then
      l1="Repair Mode - COPY\n"
      l2="ssh admin@${localip}\n"
      l3="Use password: PasswordA\n"
      boxwidth=$((${#localip} + 28))
      dialog --backtitle "RaspiBlitz ${codeVersion} (${state}) ${setupStep} ${localip}" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 3
      continue
    fi

    # check if bitcoin is ready
    sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 1>/dev/null 2>error.tmp
    clienterror=`cat error.tmp`
    rm error.tmp
    if [ ${#clienterror} -gt 0 ]; then
      boxwidth=40
      l1="Waiting for ${network}d to get ready.\n"
      l2="---> ${clienterror/error*:/}\n"
      l3="Can take longer if device was off."
      uptimeSeconds="$(cat /proc/uptime | grep -o '^[0-9]\+')"
      if [ ${uptimeSeconds} -gt 600 ]; then
        l3="!!Please login for more details!!"
      fi
      dialog --backtitle "RaspiBlitz ${codeVersion} (${localip}) - Welcome Back" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 5
      continue
    fi

    # check if locked
    locked=$(sudo -u bitcoin lncli --chain=${network} --network=${chain}net getinfo 2>&1 | grep -c unlock) 
    if [ "${locked}" -gt 0 ]; then

      # special case: LND wallet is locked ---> show unlock info
      h=5
      l1="!!! LND WALLET IS LOCKED !!!\n"
      l2="Login: ssh admin@${localip}\n"
      l3="Use your Password A\n"
      l4=""
      if [ "${rtlWebinterface}" = "on" ]; then
        l2="Browser: http://${localip}:3000\n"
        l3="PasswordB=login / PasswordC=unlock\n"
        l4="PasswordA: ssh admin@${localip}"
        h=6
      fi
      if [ "${autoUnlock}" = "on" ]; then
        l2="ssh admin@${localip}\n"
        l3="Waiting for AUTO-UNLOCK"
      fi
      boxwidth=$((${#localip} + 26))
      dialog --backtitle "RaspiBlitz ${codeVersion} (${localip}) - ${hostname}" --infobox "$l1$l2$l3$l4" ${h} ${boxwidth}
      sleep 5
      continue
    fi

    # if LND is syncing or scanning
    lndSynced=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net getinfo 2>/dev/null | jq -r '.synced_to_chain' | grep -c true)
    if [ ${lndSynced} -eq 0 ]; then
      /home/admin/80scanLND.sh
      sleep 20
      continue
    fi

    # no special case - show status display
	  /home/admin/00infoBlitz.sh
	  sleep 5

  done

fi