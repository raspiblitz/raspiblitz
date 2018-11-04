#!/bin/bash

### USER PI AUTOSTART (LCD Display)
# this script gets started by the autologin of the pi user and
# and its output is gets displayed on the LCD or the RaspiBlitz

# check that user is pi
if [ "$USER" != "pi" ]; then
  echo "plz run as user pi --> su pi"
  exit 1
fi

# check if RTL web interface is installed
runningRTL=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')

# DISPLAY LOOP
chain=""
freshstart=1
while :
    do

    # get the local network IP to be displayed on the lCD
    localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
    dhcpMissing=

    if [ ${#localip} -eq 0 ]; then

      # waiting for IP in general
      l1="Waiting for Network ...\n"
      l2="Not able to get local IP.\n"
      l3="Is LAN cable connected?\n"
      dialog --backtitle "RaspiBlitz" --infobox "$l1$l2$l3" 5 30
      sleep 3

    elif [ "${localip:0:4}" = "169." ]; then

      # waiting for IP in general
      l1="Waiting for DHCP ...\n"
      l2="Not able to get local IP.\n"
      l3="Is Router working?\n"
      dialog --backtitle "RaspiBlitz (${localip})" --infobox "$l1$l2$l3" 5 30
      sleep 3

    else

      # refresh network (if information is already available)
      network=`sudo cat /home/admin/.network 2>/dev/null`

      # get the actual step number of setup process
      setupStep=$(sudo -u admin cat /home/admin/.setup 2>/dev/null)
      if [ ${#setupStep} -eq 0 ]; then
       setupStep=0
      fi

      # before initial setup
      if [ ${setupStep} -eq 0 ]; then

        # setup process has not started yet
        l1="Login to your RaspiBlitz with:\n"
        l2="ssh admin@${localip}\n"
        l3="Use password: raspiblitz\n"
        boxwidth=$((${#localip} + 24))
        sleep 3
        dialog --backtitle "RaspiBlitz ${localip} - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
        sleep 5

      # during basic setup
      elif [ ${setupStep} -lt 65 ]; then

        # setup process has not started yet
        l1="Login to your RaspiBlitz with:\n"
        l2="ssh admin@${localip}\n"
        l3="Use your password A\n" 
        boxwidth=$((${#localip} + 24))
        sleep 3
        dialog --backtitle "RaspiBlitz ${localip} - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
        sleep 5

      # when blockchain and lightning are running
      elif [ ${setupStep} -lt 100 ]; then

        # when entering first time after boot -  display a delay
        if [ ${freshstart} -eq 1 ]; then
          dialog --pause "  Waiting for ${network} to startup and init ..." 8 58 130
          freshstart=0
        fi

        # get state of system
        if [ ${#chain} -eq 0 ];then
          # get chain if not available before
          chain=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 2>/dev/null | jq -r '.chain')
        fi
        lndSynced=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} getinfo 2>/dev/null | jq -r '.synced_to_chain' | grep -c true)
        locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null | grep -c unlock)

        if [ ${locked} -gt 0 ]; then

          # special case: LND wallet is locked ---> show unlock info
          l1="!!! LND WALLET IS LOCKED !!!\n"
          l2="Login: ssh admin@${localip}\n"
          l3="Use your Password A\n"
          if [ ${runningRTL} -eq 1 ]; then
            l2="Open: http://${localip}:3000\n"
            l3="Use Password C to unlock\n"
          fi
          boxwidth=$((${#localip} + 24))
          dialog --backtitle "RaspiBlitz ${localip} - Action Required" --infobox "$l1$l2$l3" 5 ${boxwidth}
          sleep 5

        elif [ ${lndSynced} -eq 0 ]; then

          # special case: LND is syncing
          /home/admin/80scanLND.sh
          sleep 20

        else

          # setup in progress without special case - password has been changed
          l1="Login to your RaspiBlitz with:\n"
          l2="ssh admin@${localip}\n"
          l3="Use your Password A\n"
          boxwidth=$((${#localip} + 24))
          sleep 3
          dialog --backtitle "RaspiBlitz ${localip} - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
          sleep 10

        fi

      else

        # RASPIBLITZ iS FULL SETUP

        # check if bitcoin is ready
        sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 1>/dev/null 2>error.tmp
        clienterror=`cat error.tmp`
        rm error.tmp
        if [ ${#clienterror} -gt 0 ]; then
          l1="Waiting for ${network}d to get ready.\n"
          l2="---> Starting Up\n"
          l3="Can take longer if devcie was off."
          isVerifying=$(echo "${clienterror}" | grep -c 'Verifying blocks')
          if [ ${isVerifying} -gt 0 ]; then
            l2="---> Verifying Blocks\n"
          fi
          boxwidth=40
          dialog --backtitle "RaspiBlitz ${localip} - Welcome" --infobox "$l1$l2$l3" 5 ${boxwidth}
          sleep 5
        else

          # check if locked
          locked=$(sudo -u admin lncli --chain=${network} getinfo 2>&1 | grep -c unlock) 
          if [ "${locked}" -gt 0 ]; then

            # special case: LND wallet is locked ---> show unlock info
            l1="!!! LND WALLET IS LOCKED !!!\n"
            l2="Login: ssh admin@${localip}\n"
            l3="Use your Password A\n"
            if [ ${runningRTL} -eq 1 ]; then
              l2="Open: http://${localip}:3000\n"
              l3="Use Password C to unlock\n"
            fi
            boxwidth=$((${#localip} + 24))
            dialog --backtitle "RaspiBlitz ${localip} - Welcome" --infobox "$l1$l2$l3" 5 ${boxwidth}
            sleep 5

          else

            # no special case - show status display
	          /home/admin/00infoBlitz.sh
	          sleep 5

          fi

        fi

      fi

    fi

  done

fi
