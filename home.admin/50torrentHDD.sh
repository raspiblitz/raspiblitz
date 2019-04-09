#!/bin/bash
echo ""

# see background_downloadBlockchain.md for info
# why there are two torrent files

## get basic info
source /home/admin/raspiblitz.info


# if setup was done - remove old data
if [ "${setupStep}" = "100" ]; then
  echo "stopping servcies ..."
  sudo systemctl stop lnd 
  sudo systemctl stop ${network}d
fi

# make sure rtorrent is available
sudo apt-get install rtorrent -y
echo ""

echo ""
echo "*** Torrent Files ***"

# torrent files that are available
# in directory /home.admin/assets/
# WITHOUT THE '.torrent' ENDING

bitcoinBase="raspiblitz-bitcoin1-2018-10-13-base"
bitcoinUpdate="raspiblitz-bitcoin1-2019-04-09-update"

litecoinBase="raspiblitz-litecoin1-2018-11-18-base"
litecoinUpdate="raspiblitz-litecoin1-2018-11-18-update"

# set final based on selected network
baseTorrentFile=${bitcoinBase}
updateTorrentFile=${bitcoinUpdate}
if [ "$network" = "litecoin" ]; then
  baseTorrentFile=${litecoinBase}
  updateTorrentFile=${litecoinUpdate}
fi
echo "base   : ${baseTorrentFile}"
echo "update : ${updateTorrentFile}"
sleep 1

targetDir="/mnt/hdd/torrent"
sessionDir="/home/admin/.rtorrent.session"
sudo mkdir ${sessionDir} 2>/dev/null

##############################
# CHECK TORRENT 1 "BLOCKCHAIN"
##############################

echo "*** checking torrent 1: base blockchain"
torrentComplete1=$(cat ${sessionDir}/blockchain/*.torrent.rtorrent | grep ':completei1' -c)
echo "torrentComplete1(${torrentComplete1})"
if [ ${torrentComplete1} -eq 0 ]; then

  # check if screen session for this torrent
  isRunning1=$( screen -S blockchain -ls | grep "blockchain" -c )
  echo "isRunning1(${isRunning1})"
  if [ ${isRunning1} -eq 0 ]; then

    # start torrent download in screen session
    echo "starting torrent: blockchain"
    command1="sudo rtorrent -n -d ${targetDir} -s ${sessionDir}/blockchain/ /home/admin/assets/${baseTorrentFile}.torrent"
    sudo mkdir ${targetDir} 2>/dev/null
    sudo mkdir ${sessionDir}/blockchain/ 2>/dev/null
    screenCommand="screen -S blockchain -L screen.log -dm ${command1}"
    echo "${screenCommand}"
    bash -c "${screenCommand}"
  fi
fi
sleep 2

##############################
# CHECK TORRENT 2 "UPDATE"
##############################

echo "*** checking torrent 2: update blockchain"
torrentComplete2=$(cat ${sessionDir}/update/*.torrent.rtorrent | grep ':completei1' -c)
echo "torrentComplete2(${torrentComplete2})"
if [ ${torrentComplete2} -eq 0 ]; then

  # check if screen session for this torrent
  isRunning2=$( screen -S update -ls | grep "update" -c )
  echo "isRunning2(${isRunning2})"
  if [ ${isRunning2} -eq 0 ]; then
    
    # start torrent download in screen session
    echo "starting torrent: update"
    command2="sudo rtorrent -n -d ${targetDir} -s ${sessionDir}/update/ /home/admin/assets/${updateTorrentFile}.torrent"
    sudo mkdir ${targetDir} 2>/dev/null
    sudo mkdir ${sessionDir}/update/ 2>/dev/null
    screenCommand="screen -S update -L screen.log -dm ${command2}"
    echo "${screenCommand}"
    bash -c "${screenCommand}"

  fi
fi
sleep 2

##############################
# MONITOR PROGRESS
##############################

sleep 3

# monitor screen session
screenDump1="... started ..."
screenDump2="... started ..."
torrentComplete1=0
torrentComplete2=0
while :
  do

    # display info screen
    clear
    echo "****************************************************"
    echo "Monitoring Screen Session: Torrent base+update"
    echo "NOTICE: This can take multiple hours or days !!"
    echo "Its OK to close terminal now and SSH back in later."
    echo "If u see the torrents 100% downloaded and verified,"
    echo "press X to continue. Also press x to abort download"
    echo "before 100% if you want to switch to another option."
    echo "****************************************************"
    echo ""

    # display torrent 1 info
    echo "*** 1) Status Torrent 'blockchain':"
    torrentComplete1=$(cat ${sessionDir}/blockchain/*.torrent.rtorrent | grep ':completei1' -c)
    if [ ${torrentComplete1} -eq 0 ]; then
      screen -S blockchain -X hardcopy .blockchain.out
      newScreenDump=$(cat .blockchain.out | head -6 | tail -3 )
      if [ ${#newScreenDump} -gt 0 ]; then
        screenDump1=$newScreenDump
      fi
      echo "$screenDump1"
    else
      echo "Completed"
    fi
    echo ""

    # display torrent 2 info
    echo "*** 2) Status Torrent 'update':"
    torrentComplete2=$(cat ${sessionDir}/update/*.torrent.rtorrent | grep ':completei1' -c)
    if [ ${torrentComplete2} -eq 0 ]; then
      screen -S update -X hardcopy .update.out
      newScreenDump=$(cat .update.out| head -6 | tail -3 )
      if [ ${#newScreenDump} -gt 0 ]; then
        screenDump2=$newScreenDump
      fi
      echo "$screenDump2"
    else
      echo "Completed"
    fi
    echo ""

    # check if both torrents completed
    if [ ${torrentComplete1} -eq 1 ]; then
      if [ ${torrentComplete2} -eq 1 ]; then
        echo "OK - all torrents finished"
        break
      fi
    fi

    # wait 2 seconds for key input
    read -n 1 -t 2 keyPressed

    # check if user wants to abort session
    if [ "${keyPressed}" = "x" ]; then
      echo ""
      echo "Aborting"
      break
    fi

  done

# clean up
rm -f .blockchain.out
rm -f .update.out

##############################
# AFTER PARTY & CLEAN UP
##############################

# quit session1
isRunning=$( screen -S blockchain -ls | grep "blockchain" -c )
if [ ${isRunning} -eq 1 ]; then
  # get the PID of screen session
  sessionPID=$(screen -ls | grep "blockchain" | cut -d "." -f1 | xargs)
  echo "killing screen session PID(${sessionPID})"
  # kill all child processes of screen sceesion
  sudo pkill -P ${sessionPID}
  echo "proccesses killed"
  sleep 3
 # tell the screen session to quit and wait a bit
  screen -S blockchain -X quit 1>/dev/null
  sleep 3
  echo "cleaning screen"
  screen -wipe 1>/dev/null
  sleep 3
fi

# quit session2
isRunning=$( screen -S update -ls | grep "update" -c )
if [ ${isRunning} -eq 1 ]; then
  # get the PID of screen session
  sessionPID=$(screen -ls | grep "update" | cut -d "." -f1 | xargs)
  echo "killing screen session PID(${sessionPID})"
  # kill all child processes of screen sceesion
  sudo pkill -P ${sessionPID}
  echo "proccesses killed"
  sleep 3
 # tell the screen session to quit and wait a bit
  screen -S update -X quit 1>/dev/null
  sleep 3
  echo "cleaning screen"
  screen -wipe 1>/dev/null
  sleep 3
fi

# check torrent success
echo ""
echo "*** Torrent Data Check ***"

torrentError=0
torrentComplete1=$(cat ${sessionDir}/blockchain/*.torrent.rtorrent | grep ':completei1' -c)
torrentComplete2=$(cat ${sessionDir}/update/*.torrent.rtorrent | grep ':completei1' -c)
if [ ${torrentComplete1} -eq 0 ]; then
  torrentError=1
fi
if [ ${torrentComplete2} -eq 0 ]; then
  torrentError=2
fi

# the path torrent was download to
targetPath1="${targetDir}/${baseTorrentFile}"
targetPath2="${targetDir}/${updateTorrentFile}"

# check that path exists
contentPath1=$(sudo ls ${targetPath1} 2>/dev/null)
contentPath2=$(sudo ls ${targetPath2} 2>/dev/null)
if [ ${#contentPath1} -eq 0 ]; then
  torrentError=3
fi
if [ ${#contentPath2} -eq 0 ]; then
  torrentError=4
fi

if [ ${torrentError} -gt 0 ]; then
 
  # User Cancel --> Torrent incomplete
  sleep 3
  echo -ne '\007'
  dialog --title " WARNING (${torrentError})" --yesno "The Torrent download failed or is not complete - maybe try COPY option. Do you want keep already downloaded torrent data?" 8 57
  response=$?
  case $response in
    1) sudo rm -rf ${targetDir}; sudo rm -rf ${sessionDir} ;;
  esac
  ./00mainMenu.sh
  exit 1;
  
fi

# if setup was done - remove old data
if [ "${setupStep}" = "100" ]; then
  echo "stopping servcies ..."
  sudo systemctl stop lnd 
  sudo systemctl stop ${network}d
  sudo systemctl disable ${network}d
  sudo cp -f /mnt/hdd/${network}/${network}.conf /home/admin/assets/${network}.conf 
  sudo rm -rfv /mnt/hdd/${network}/* 2>/dev/null
  sudo rm /mnt/hdd/${network}/debug.log
fi

# Download worked / just move, copy on USB2 would be >4h
echo ""
echo "*** Moving Files ***"
date +%s
echo "can take 10-60 minutes... please wait"
sudo mkdir /mnt/hdd/${network} 2>/dev/null
sudo mv ${targetPath1}/* /mnt/hdd/${network}/
sudo cp -r ${targetPath2}/* /mnt/hdd/${network}/
sudo rm -r ${targetDir}
echo "OK"
date +%s

if [ "${setupStep}" = "100" ]; then
  sudo cp /home/admin/assets/${network}.conf /mnt/hdd/${network}/${network}.conf
  rpcpass=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep "${network}d.rpcpass" | cut -d "=" -f2)
  sudo sed -i "s/^rpcpassword=.*/rpcpassword=${rpcpass}/g" /mnt/hdd/${network}/${network}.conf 2>/dev/null
  sudo chown -R bitcoin:bitcoin /mnt/hdd/${network}/
  sudo systemctl enable ${network}d
  echo "DONE - rebooting: sudo shutdown -r now"
  sudo shutdown -r now
else
  # set SetupState
  sudo sed -i "s/^setupStep=.*/setupStep=50/g" /home/admin/raspiblitz.info
  # continue setup
  ./60finishHDD.sh
fi