#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# managing the copy of blockchain data over LAN"
 echo "# blitz.copychain.sh [status|target|source]"
 echo "error='missing parameters'"
 exit 1
fi

# load basic system settings
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# check that blockchain is set & supported
if [ "${network}" != "bitcoin" ] && [ "${network}" != "litecoin" ]; then
  echo "blockchain='{$network}'"
  echo "error='blockchain type missing or not supported'"
  exit 1
fi

# check that HDD is available
isMounted=$(sudo df | grep -c /mnt/hdd)
if [ "${isMounted}" != "1" ]; then
  echo "error='no datadrive is mounted'"
  exit 1
fi

###################
# STATUS
###################

# check if copy is in progress
copyBeginTime=$(cat /mnt/hdd/${network}/copy_begin.time 2>/dev/null | tr -cd '[[:digit:]]')
if [ ${#copyBeginTime} -eq 0 ]; then
  copyBeginTime=0
fi
copyEndTime=$(cat /mnt/hdd/${network}/copy_end.time 2>/dev/null | tr -cd '[[:digit:]]')
if [ ${#copyEndTime} -eq 0 ]; then
  copyEndTime=0
fi
copyInProgress=0
if [ ${copyBeginTime} -gt ${copyEndTime} ]; then
  copyInProgress=1
fi

# output status data & exit
if [ "$1" = "status" ]; then
  echo "# blitz.copychain.sh"
  echo "copyInProgress=${copyInProgress}"
  echo "copyBeginTime=${copyBeginTime}"
  echo "copyEndTime=${copyEndTime}"
  exit 1
fi

###################
# COPYTARGET
###################

# output status data & exit
if [ "$1" = "target" ]; then

  # Basic Options
  OPTIONS=(WINDOWS "Windows" \
         MACOS "Apple MacOSX" \
         LINUX "Linux" \
         BLITZ "RaspiBlitz"
        )
  CHOICE=$(dialog --clear --title " Copy Blockchain from another laptop/node over LAN " --menu "\nWhich system is running on the other laptop/node you want to copy the blockchain from?\n " 14 60 9 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  clear
  case $CHOICE in
        MACOS) echo "Steve";;
        LINUX) echo "Linus";;
        WINDOWS) echo "Bill";;
        BLITZ) echo "Satoshi";;
        *) exit 1;;
  esac

  # setting copy state
  sed -i "s/^state=.*/state=copytarget/g" /home/admin/raspiblitz.info
  sed -i "s/^message=.*/message='Receiving Blockchain over LAN'/g" /home/admin/raspiblitz.info

  echo "stopping services ..."
  sudo systemctl stop bitcoind 2>/dev/null
  sudo systemctl disable bitcoind 2>/dev/null

  # check if old blockchain data exists
  hasOldBlockchainData=0
  sizeBlocks=$(sudo du -s /mnt/hdd/bitcoin/blocks 2>/dev/null | tr -dc '[0-9]')
  if [ ${#sizeBlocks} -gt 0 ] && [ ${sizeBlocks} -gt 0 ]; then
    hasOldBlockchainData=1
  fi
  sizeChainstate=$(sudo du -s /mnt/hdd/bitcoin/chainstate 2>/dev/null | tr -dc '[0-9]')
  if [ ${#sizeChainstate} -gt 0 ] && [ ${sizeChainstate} -gt 0 ]; then
    hasOldBlockchainData=1
  fi

  dialog --title " Old Blockchain Data Found " --yesno "\nDo you want to delete the existing blockchain data now?" 7 60
  response=$?
  clear
  echo "response(${response})"
  if [ "${response}" = "1" ]; then
    echo "OK - keep old blockchain - just try to repair by copying over it"
    sleep 3
  else
    echo "OK - delete old blockchain"
    sudo rm -rfv /mnt/hdd/bitcoin/blocks/* 2>/dev/null
    sudo rm -rfv /mnt/hdd/bitcoin/chainstate/* 2>/dev/null
    sleep 3
  fi

  # make sure /mnt/hdd/bitcoin exists
  sudo mkdir /mnt/hdd/bitcoin 2>/dev/null

  # allow all users write to it
  sudo chmod 777 /mnt/hdd/bitcoin

  echo 
  clear
  if [ "${CHOICE}" = "WINDOWS" ]; then
    echo "****************************************************************************"
    echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from a WINDOWS computer"
    echo "****************************************************************************"
    echo ""
    echo "ON YOUR WINDOWS COMPUTER download and validate the blockchain with the Bitcoin"
    echo "Core wallet software (>=0.17.1) from: bitcoincore.org/en/download"
    echo "If the Bitcoin Blockchain is synced up - make sure that your Windows computer &"
    echo "your RaspiBlitz are in the same local network."
    echo ""
    echo "Open a fresh terminal on your Windows computer & change into the directory that"
    echo "contains the blockchain data - should see folders named 'blocks' & 'chainstate'"
    echo "there. Normally on Windows thats: C:\Users\YourUserName\Appdata\Roaming\Bitcoin"
    echo "Make sure that the Bitcoin Core Wallet is not running in the background anymore."
    echo ""
    echo "COPY, PASTE & EXECUTE the following command on your Windows computer terminal:"
    echo "scp -r ./chainstate ./blocks bitcoin@${localip}:/mnt/hdd/bitcoin"
    echo ""
    echo "If asked for a password use PASSWORD A (or 'raspiblitz')."
  fi
  if [ "${CHOICE}" = "MACOS" ]; then
    echo "****************************************************************************"
    echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from a MacOSX computer"
    echo "****************************************************************************"
    echo ""
    echo "ON YOUR MacOSX COMPUTER download and validate the blockchain with the Bitcoin"
    echo "Core wallet software (>=0.17.1) from: bitcoincore.org/en/download"
    echo "If the Bitcoin Blockchain is synced up - make sure that your MacOSX computer &"
    echo "your RaspiBlitz are in the same local network."
    echo ""
    echo "Open a fresh terminal on your MacOSX computer and change into the directory that"
    echo "contains the blockchain data - should see folders named 'blocks' & 'chainstate'"
    echo "there. Normally on MacOSX thats: cd ~/Library/Application Support/Bitcoin/"
    echo "Make sure that the Bitcoin Core Wallet is not running in the background anymore."
    echo ""
    echo "COPY, PASTE & EXECUTE the following command on your MacOSX terminal:"
    echo "sudo rsync -avhW --progress ./chainstate ./blocks bitcoin@${localip}:/mnt/hdd/bitcoin"
    echo ""
    echo "You will be asked for passwords. First can be the user password of your MacOSX"
    echo "computer and the last is the PASSWORD A (or 'raspiblitz') of this RaspiBlitz."
  fi
  if [ "${CHOICE}" = "LINUX" ]; then
    echo "****************************************************************************"
    echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from a LINUX computer"
    echo "****************************************************************************"
    echo ""
    echo "ON YOUR LINUX COMPUTER download and validate the blockchain with the Bitcoin"
    echo "Core wallet software (>=0.17.1) from: bitcoincore.org/en/download"
    echo "If the Bitcoin Blockchain is synced up - make sure that your Linux computer &"
    echo "your RaspiBlitz are in the same local network."
    echo ""
    echo "Open a fresh terminal on your Linux computer and change into the directory that"
    echo "contains the blockchain data - should see folders named 'blocks' & 'chainstate'"
    echo "there. Normally on Linux thats: cd ~/.bitcoin/"
    echo "Make sure that the Bitcoin Core Wallet is not running in the background anymore."
    echo ""
    echo "COPY, PASTE & EXECUTE the following command on your Linux terminal:"
    echo "sudo rsync -avhW --progress ./chainstate ./blocks bitcoin@${localip}:/mnt/hdd/bitcoin"
    echo ""
    echo "You will be asked for passwords. First can be the user password of your Linux"
    echo "computer and the last is the PASSWORD A (or 'raspiblitz') of this RaspiBlitz."
  fi
  if [ "${CHOICE}" = "BLITZ" ]; then
    echo "****************************************************************************"
    echo "Instructions to COPY/TRANSFER SYNCED BLOCKCHAIN from another RaspiBlitz"
    echo "****************************************************************************"
    echo ""
    echo "The other RaspiBlitz needs a minimum version of 1.6 (if lower, update first)."
    echo "Make sure that the other RaspiBlitz is on the same local network."
    echo ""
    echo "Open a fresh terminal and login per SSH into that other RaspiBlitz."
    echo "Once in the main menu go: MAINMENU > REPAIR > COPY-SOURCE"
    echo "Follow the given instructions ..."
    echo ""
    echo "The LOCAL IP of this target RaspiBlitz is: ${localip}"
  fi
  echo "" 
  echo "It can take multiple hours until transfer is complete - be patient."
  echo "****************************************************************************"
  echo "PRESS ENTER if transfers is done OR if you want to choose another option."
  sleep 2
  read key

  # make quick check if data is there
  anyDataAtAll=0
  quickCheckOK=1
  count=$(sudo find /mnt/hdd/bitcoin/ -iname *.dat -type f | wc -l)
  if [ ${count} -gt 0 ]; then
    echo "Found data in /mnt/hdd/bitcoin/blocks"
    anyDataAtAll=1
  fi
  if [ ${count} -lt 300 ]; then
    echo "FAIL: transfer seems invalid - less then 300 .dat files (${count})"
    quickCheckOK=0
  fi
  count=$(sudo find /mnt/hdd/bitcoin/ -iname *.ldb -type f | wc -l)
  if [ ${count} -gt 0 ]; then
    echo "Found data in /mnt/hdd/bitcoin/chainstate"
    anyDataAtAll=1
  fi
  if [ ${count} -lt 700 ]; then
    echo "FAIL: transfer seems invalid - less then 700 .ldb files (${count})"
    quickCheckOK=0
  fi

  echo "*********************************************"
  echo "QUICK CHECK RESULT"
  echo "*********************************************"

  # just if any data transferred ..
  if [ ${anyDataAtAll} -eq 1 ]; then

    # data was invalid - ask user to keep?
    if [ ${quickCheckOK} -eq 0 ]; then
      echo "FAIL -> DATA seems incomplete."
    else
      echo "OK -> DATA LOOKS GOOD :D"
      sudo rm /mnt/hdd/bitcoin/debug.log 2>/dev/null
    fi

  else
    echo "CANCEL -> NO DATA was copied."
    quickCheckOK=0
  fi
  echo "*********************************************"


  # REACT ON QUICK CHECK DURING INITAL SETUP
  if [ ${quickCheckOK} -eq 0 ]; then

    echo "*********************************************"
    echo "There seems to be an invalid transfer."

    echo "Wait 5 secs ..."
    sleep 5

    dialog --title " INVALID TRANSFER - TRY AGAIN?" --yesno "Quickcheck shows the data you transferred is invalid/incomplete. Maybe transfere was interrupted and not completed.\n\nDo you want retry/proceed the copy process?" 8 70
    response=$?
    echo "response(${response})"
    if [ "${response}" == "0" ]; then
      /home/admin/config.scripts/blitz.copychain.sh
      exit 0
    fi

    dialog --title " INVALID TRANSFER - DELETE DATA?" --yesno "Quickcheck shows the data you transferred is invalid/incomplete. This can lead further RaspiBlitz setup to get stuck in error state.\nDo you want to reset/delete data?" 8 60
    response=$?
    echo "response(${response})"
    case $response in
      1) quickCheckOK=1 ;;
    esac
  
  fi

  if [ ${quickCheckOK} -eq 0 ]; then
    echo "Deleting invalid Data ... "
    sudo rm -rf /mnt/hdd/bitcoin
    sleep 2
  fi

  echo "restarting services ... (please wait)"
  sudo systemctl enable bitcoind 
  sudo systemctl start bitcoind 
  sleep 10

  # setting copy state
  sed -i "s/^state=.*/state=ready/g" /home/admin/raspiblitz.info
  sed -i "s/^message=.*/message='Node Running'/g" /home/admin/raspiblitz.info
fi

###################
# COPYSOURCE
###################

if [ "$1" = "source" ]; then

  clear
  echo
  echo "# *** Copy Blockchain Source Modus ***"

  echo "# get IP of RaspiBlitz to copy to ..."
  targetIP=$(whiptail --inputbox "\nPlease enter the LOCAL IP of the\nRaspiBlitz to copy Blockchain to:" 10 38 "" --title " Target IP " --backtitle "RaspiBlitz - Copy Blockchain" 3>&1 1>&2 2>&3)
  targetIP=$(echo "${targetIP[0]}")
  localIP=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  if [ ${#targetIP} -eq 0 ]; then
    exit 1
  fi
  if [ "${localIP}" == "${targetIP}" ]; then
    whiptail --msgbox "Dont type in the local IP of this RaspiBlitz,\nthe LOCAL IP of the other RaspiBlitz is needed." 8 54 "" --title " Testing Target IP " --backtitle "RaspiBlitz - Copy Blockchain"
    exit 1
  fi
  canPingIP=$(ping ${targetIP} -c 1 | grep -c "1 received")
  if [ ${canPingIP} -eq 0 ]; then
    whiptail --msgbox "Was not able to contact/ping: ${targetIP}\n\n- check if IP of target RaspiBlitz is correct.\n- check to be on the same local network.\n- try again ..." 11 58 "" --title " Testing Target IP " --backtitle "RaspiBlitz - Copy Blockchain"
    exit 1
  fi
  
  echo "# get Password of RaspiBlitz to copy to ..."
  targetPassword=$(whiptail --passwordbox "\nPlease enter the PASSWORD A of the\nRaspiBlitz to copy Blockchain to:" 10 38 "" --title "Target Password" --backtitle "RaspiBlitz - Copy Blockchain" 3>&1 1>&2 2>&3)
  if [ ${#targetPassword} -eq 0 ]; then
    exit 1
  fi

  sudo rm /root/.ssh/known_hosts 2>/dev/null
  canLogin=$(sudo sshpass -p "${targetPassword}" ssh -t -o StrictHostKeyChecking=no bitcoin@${targetIP} "echo 'working'" 2>/dev/null | grep -c 'working')
  if [ ${canLogin} -eq 0 ]; then
    whiptail --msgbox "Password was not working for IP: ${targetIP}\n\n- check thats the correct IP for correct RaspiBlitz\n- check that you used PASSWORD A and had no typo\n- If you tried too often, wait 1h try again" 11 58 "" --title " Testing Target Password " --backtitle "RaspiBlitz - Copy Blockchain"
    exit 1
  fi

  echo "# stopping services ..."
  sudo systemctl stop background
  sudo systemctl stop lnd
  sudo systemctl stop ${network}d
  sudo systemctl disable ${network}d
  sleep 5
  sudo systemctl stop bitcoind 2>/dev/null
  
  clear
  echo
  echo "# Starting copy over LAN (around 4-6 hours) ..."
  sed -i "s/^state=.*/state=copysource/g" /home/admin/raspiblitz.info
  cd /mnt/hdd/${network}

  # transfere beginning flag
  date +%s > /home/admin/copy_begin.time
  sudo sshpass -p "${targetPassword}" rsync -avhW -e 'ssh -o StrictHostKeyChecking=no -p 22' /home/admin/copy_begin.time bitcoin@${targetIP}:/mnt/hdd/bitcoin
  sudo rm -f /home/admin/copy_begin.time

  # repeat the syncing of directories until
  # a) there are no files left to transfere (be robust against failing connections, etc)
  # b) the user hits a key to break loop after report
  while :
    do

      # transfere blockchain data
      sudo rm -f ./transferred.rsync
      sudo sshpass -p "${targetPassword}" rsync -avhW -e 'ssh -o StrictHostKeyChecking=no -p 22' --info=progress2 --log-file=./transferred.rsync ./chainstate ./blocks bitcoin@${targetIP}:/mnt/hdd/bitcoin

      # check result
      # the idea is even after successfull transfer the loop will run a second time
      # but on the second time there will be no files transfered (log lines are below 4)
      # thats the signal that its done
      linesInLogFile=$(wc -l ./transferred.rsync | cut -d " " -f 1) 
      if [ ${linesInLogFile} -lt 4 ]; then
        echo ""
        echo "OK all files transfered. DONE"
        sleep 2
        break
      fi

      # wait 20 seconds for user exiting loop
      echo ""
      echo -en "OK one sync loop done ... will test in next loop if all was transferred."
      echo -en "PRESS X TO MANUALLY FINISH SYNCING"
      read -n 1 -t 6 keyPressed
      if [ "${keyPressed}" = "x" ]; then
        echo ""
        echo "Ending Sync ..."
        sleep 2
        break
      fi

    done
  
  # transfere end flag
  sed -i "s/^state=.*/state=ready/g" /home/admin/raspiblitz.info
  date +%s > /home/admin/copy_end.time
  sudo sshpass -p "${targetPassword}" rsync -avhW -e 'ssh -o StrictHostKeyChecking=no -p 22' /home/admin/copy_end.time bitcoin@${targetIP}:/mnt/hdd/bitcoin
  sudo rm -f /home/admin/copy_end.time

  echo "# start services again ..."
  sudo systemctl enable ${network}d
  sudo systemctl start ${network}d
  sudo systemctl start lnd
  sudo systemctl start background

  echo "# show final message"
  whiptail --msgbox "OK - Copy Process Finished.\n\nNow check on the target RaspiBlitz if it was sucessful." 10 40 "" --title " DONE " --backtitle "RaspiBlitz - Copy Blockchain"

fi