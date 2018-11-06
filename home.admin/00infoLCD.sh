#!/bin/sh
if [ "$USER" = "pi" ]; then

  # check for after setup script
  afterSetupScriptExists=$(ls /home/pi/setup.sh 2>/dev/null | grep -c setup.sh)
  if [ ${afterSetupScriptExists} -eq 1 ]; then
    echo "*** SETUP SCRIPT DETECTED ***"
    sudo cat /home/pi/setup.sh
    sudo /home/pi/setup.sh
    sudo rm /home/pi/setup.sh
    echo "DONE wait 6 secs ... one more reboot needed ... "
    sudo shutdown -r now
  fi

  # load network
  network=`sudo cat /home/admin/.network 2>/dev/null`

  ### USER PI AUTOSTART (LCD Display)
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

  # check if bitcoin service is configured
  bitcoinInstalled=$(sudo -u bitcoin ls /mnt/hdd/${network}/ 2>/dev/null | grep -c ${network}.conf)
  if [ ${bitcoinInstalled} -eq 1 ]; then
    # wait enough secs to let bitcoind init
    dialog --pause "  Waiting for ${network} to startup and init ..." 8 58 130
  fi

  # show updating status in loop
  chain=""
  while :
     do

      # refresh network
      network=`sudo cat /home/admin/.network 2>/dev/null`

      # get the setup state
      setupStepExists=$(sudo -u admin ls -la /home/admin/.setup 2>/dev/null | grep -c .setup)
      if [ ${setupStepExists} -eq 1 ]; then
        setupStep=$(sudo -u admin cat /home/admin/.setup)
      else
        setupStep=0
      fi

      if [ ${setupStep} -eq 0 ]; then

        # setup process has not started yet
        l1="Login to your RaspiBlitz with:\n"
        l2="ssh admin@${localip}\n"
        l3="Use password: raspiblitz\n"
        boxwidth=$((${#localip} + 24))
        sleep 3
        dialog --backtitle "RaspiBlitz - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
        sleep 5

      elif [ ${setupStep} -lt 65 ]; then

          # setup process has not started yet
          l1="Login to your RaspiBlitz with:\n"
          l2="ssh admin@${localip}\n"
          l3="Use your password A\n"
          boxwidth=$((${#localip} + 24))
        sleep 3
        dialog --backtitle "RaspiBlitz - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
        sleep 5

      elif [ ${setupStep} -lt 100 ]; then

        # setup process init is done and not finished
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
          boxwidth=$((${#localip} + 24))
          dialog --backtitle "RaspiBlitz - Action Required" --infobox "$l1$l2$l3" 5 ${boxwidth}
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
          dialog --backtitle "RaspiBlitz - Welcome (${setupStep})" --infobox "$l1$l2$l3" 5 ${boxwidth}
          sleep 10

        fi

      else

        # RaspiBlitz is full Setup

        chain=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')
        locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null | grep -c unlock) 
        if [ ${locked} -gt 0 ]; then
        
          # special case: LND wallet is locked ---> show unlock info
          l1="!!! LND WALLET IS LOCKED !!!\n"
          l2="Login: ssh admin@${localip}\n"
          l3="Use your Password A\n"
          boxwidth=$((${#localip} + 24))
          dialog --backtitle "RaspiBlitz - Welcome" --infobox "$l1$l2$l3" 5 ${boxwidth}
          sleep 5
        
        else

          # no special case - show status display
	        # /home/admin/00infoBlitz.sh
	        /home/admin/00infoBlitz.py
	        sleep 5
	      
        fi

      fi
    done

else

  echo "plz run as user pi --> su pi"

fi
