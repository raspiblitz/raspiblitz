#!/bin/bash
echo ""

# get blockchain from https://getbitcoinblockchain.com torrents.
# those ore two torrents:
# 1) "blockchain" = blocks up to last month 
# 2) "update" = daily block/index update
# this scripts will download both these torrents

# make sure rtorrent is available
sudo apt-get install rtorrent -y
echo ""

targetDir="/mnt/hdd/getbitcoinblockchain"
sessionDir="/home/admin/.rtorrent.session"
sudo mkdir ${sessionDir} 2>/dev/null

##############################
# CHECK TORRENT 1 "BLOCKCHAIN"
##############################

echo "*** checking torrent 1: blockchain"
torrentComplete1=$(cat ${sessionDir}/blockchain/*.torrent.rtorrent | grep ':completei1' -c)
echo "torrentComplete1(${torrentComplete1})"
if [ ${torrentComplete1} -eq 0 ]; then

  # check if screen session for this torrent
  isRunning1=$( screen -S blockchain -ls | grep "blockchain" -c )
  echo "isRunning1(${isRunning1})"
  if [ ${isRunning1} -eq 0 ]; then

    # start torrent download in screen session
    echo "starting torrent: blockchain"
    command1="sudo rtorrent -n -d ${targetDir} -s ${sessionDir}/blockchain/ https://getbitcoinblockchain.com/blockchain.torrent"
    sudo mkdir ${targetDir} 2>/dev/null
    sudo mkdir ${sessionDir}/blockchain/ 2>/dev/null
    screenCommand="screen -S blockchain -L screen.log -dm ${command1}"
    echo "${screenCommand}"
    bash -c "${screenCommand}"

  fi
fi

##############################
# CHECK TORRENT 2 "UPDATE"
##############################

echo "*** checking torrent 2: update"
torrentComplete2=$(cat ${sessionDir}/update/*.torrent.rtorrent | grep ':completei1' -c)
echo "torrentComplete2(${torrentComplete2})"
if [ ${torrentComplete2} -eq 0 ]; then

  # check if screen session for this torrent
  isRunning2=$( screen -S update -ls | grep "update" -c )
  echo "isRunning2(${isRunning2})"
  if [ ${isRunning2} -eq 0 ]; then
    
    # start torrent download in screen session
    echo "starting torrent: update"
    command2="sudo rtorrent -n -d ${targetDir} -s ${sessionDir}/update/ https://getbitcoinblockchain.com/update.torrent"
    sudo mkdir ${targetDir} 2>/dev/null
    sudo mkdir ${sessionDir}/update/ 2>/dev/null
    screenCommand="screen -S update -L screen.log -dm ${command2}"
    echo "${screenCommand}"
    bash -c "${screenCommand}"

  fi
fi

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
    echo "Monitoring Screen Session: getbitcoinblockchain.com"
    echo "If needed press key x to stop TORRENT download"
    echo "NOTICE: This can take multiple hours or days !!"
    echo "Its OK to close terminal now and SSH back in later."
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
      echo "Aborting getbitcoinblockchain.com"
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

# check result
torrentComplete=0
torrentComplete1=$(cat ${sessionDir}/blockchain/*.torrent.rtorrent | grep ':completei1' -c)
torrentComplete2=$(cat ${sessionDir}/update/*.torrent.rtorrent | grep ':completei1' -c)
if [ ${torrentComplete1} -eq 1 ]; then
  if [ ${torrentComplete2} -eq 1 ]; then
    torrentComplete=1
  fi
fi
if [ ${torrentComplete} -eq 0 ]; then
 
  # User Cancel --> Torrent incomplete
  sleep 3
  echo -ne '\007'
  dialog --title " WARNING " --yesno "The download failed or is not complete. Maybe try again (later). Do you want keep already downloaded data for next try?" 8 57
  response=$?
  case $response in
    1) sudo rm -rf ${targetDir} ;;
  esac
  ./00mainMenu.sh
  exit 1;
  
fi

# the path torrent will download to
targetPath1="${targetDir}/blockchain"
targetPath2="${targetDir}/update/blockchain"

# Download worked / just move, copy on USB2 >4h
echo "*** Moving Files ***"
echo "can take some minutes ..."
date +%s
sudo mkdir /mnt/hdd/bitcoin
sudo mv ${targetPath1}/* /mnt/hdd/bitcoin/
sudo cp -r ${targetPath2}/* /mnt/hdd/bitcoin/
sudo rm -r ${targetDir}
echo "OK"
date +%s

# continue setup
./60finishHDD.sh
