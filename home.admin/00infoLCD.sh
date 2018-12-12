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
dialog --pause "  Starting services ..." 8 58 12

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
      dialog --backtitle "RaspiBlitz" --infobox "$l1$l2$l3" 5 30
      sleep 3
      continue
    fi

    # waiting for DHCP in general
    if [ "${localip:0:4}" = "169." ]; then
      l1="Waiting for DHCP ...\n"
      l2="Not able to get local IP.\n"
      l3="Will try reboot every 5min.\n"
      dialog --backtitle "RaspiBlitz (${localip})" --infobox "$l1$l2$l3" 5 30
      sleep 3
      continue
    fi

    ## get basic info from SD
    bootstrapInfoExists=$(ls ${infoFile} 2>/dev/null | grep -c '.info')
    if [ ${bootstrapInfoExists} -eq 1 ]; then
      source ${infoFile}
    fi

    # get final config if already avaulable
    configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
    if [ ${configExists} -eq 1 ]; then
      source ${configFile}
      setupStep=100
    fi

    # if no information available from files - set default
    if [ ${#setupStep} -eq 0 ]; then
     setupStep=0
    fi

    ###########################
    # DISPLAY DURING SETUP
    ###########################

    # before setup even started
    if [ ${setupStep} -eq 0 ]; then
            
      # when in presync - get more info on progress
      if [ "${state}" = "presync" ]; then
        # get blockchain sync progress
        blockchaininfo="$(sudo -u root bitcoin-cli -conf=/home/admin/assets/bitcoin.conf getblockchaininfo 2>/dev/null)"
        message="starting"
        if [ ${#blockchaininfo} -gt 0 ]; then
          message="$(echo "${blockchaininfo}" | jq -r '.verificationprogress')"
          message=$(echo "${message}*100" | bc)
          message="${message}%"
        fi
      fi

      # when old data - improve message
      if [ "${state}" = "olddata" ]; then
          message="login for manual migration"
      fi
      
      # setup process has not started yet
      l1="Login to your RaspiBlitz with:\n"
      l2="ssh admin@${localip}\n"
      l3="Use password: raspiblitz\n"
      boxwidth=$((${#localip} + 24))
      sleep 3
      dialog --backtitle "RaspiBlitz (${state}) - ${message}" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 5
      continue
    fi

    # when setup is in progress - password has been changed
    if [ ${setupStep} -lt 100 ]; then
      l1="Login to your RaspiBlitz with:\n"
      l2="ssh admin@${localip}\n"
      l3="Use your Password A\n"
      boxwidth=$((${#localip} + 24))
      sleep 3
      dialog --backtitle "RaspiBlitz ${localip} - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 7
      continue
    fi

    ###########################
    # DISPLAY AFTER SETUP
    ###########################

    # check if bitcoin is ready
    sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 1>/dev/null 2>error.tmp
    clienterror=`cat error.tmp`
    rm error.tmp
    if [ ${#clienterror} -gt 0 ]; then

      l1="Waiting for ${network}d to get ready.\n"
      l2="---> Starting Up\n"
      l3="Can take longer if device was off."
      isVerifying=$(echo "${clienterror}" | grep -c 'Verifying blocks')
      if [ ${isVerifying} -gt 0 ]; then
        l2="---> Verifying Blocks\n"
      fi
      boxwidth=40
      dialog --backtitle "RaspiBlitz ${localip} - Welcome" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 5
      continue
    fi

    # check if locked
    locked=$(sudo -u admin lncli --chain=${network} getinfo 2>&1 | grep -c unlock) 
    if [ "${locked}" -gt 0 ]; then

      # special case: LND wallet is locked ---> show unlock info
      l1="!!! LND WALLET IS LOCKED !!!\n"
      l2="Login: ssh admin@${localip}\n"
      l3="Use your Password A\n"
      if [ "${rtlWebinterface}" = "on" ]; then
        l2="Open: http://${localip}:3000\n"
        l3="Use Password C to unlock\n"
      fi
      boxwidth=$((${#localip} + 24))
      dialog --backtitle "RaspiBlitz ${localip} - ${hostname}" --infobox "$l1$l2$l3" 5 ${boxwidth}
      sleep 5
      continue
    fi

    # if LND is syncing or scanning
    lndSynced=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${network}net getinfo 2>/dev/null | jq -r '.synced_to_chain' | grep -c true)
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
