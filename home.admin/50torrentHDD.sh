#!/bin/bash
echo ""

# *** BITCOIN Torrent ***
bitcoinTorrent="raspiblitz-bitcoin-2018-07-16"
bitcoinTorrentsize=231230512
                   
# *** LITECOIN Torrent ***
litecoinTorrent="raspiblitz-litecoin-2018-07-29"
litecoinTorrentsize=10240000

# load network
network=`cat .network`

# settings based on network
torrent=$bitcoinTorrent
size=$bitcoinTorrentsize
if [ "$network" = "litecoin" ]; then
  torrent=$litecoinTorrent
  size=$litecoinTorrentsize
fi

# screen background monitoring settings
name="Torrent"
targetDir="/mnt/hdd/torrent/"
targetSize=$size
maxTimeoutLoops=100000
command="sudo lftp -c \"torrent -O ${targetDir} /home/admin/assets/${torrent}.torrent; bye\""

# starting session if needed
echo "checking if ${name} has a running screen session"
screen -wipe 1>/dev/null
isRunning=$( screen -S ${name} -ls | grep "${name}" -c )
echo "isRunning(${isRunning})"
if [ ${isRunning} -eq 0 ]; then
  echo "Starting screen session"
  sudo mkdir ${targetDir} 2>/dev/null
  echo "screen -S ${name} -dm ${command}"
  screen -S ${name} -dm ${command}
else
  echo "Continue screen session"
fi
sleep 3

# monitor session
screenDump="... started ..."
actualSize=0
timeout=1
timeoutInfo="-"
while :
  do

    # check if session is still running
    screen -wipe 1>/dev/null
    isRunning=$( screen -S ${name} -ls | grep "${name}" -c )
    if [ ${isRunning} -eq 0 ]; then
      timeout=0
      echo "OK - session finished"
      break
    fi

    # calculate progress and write it to file for LCD to read
    freshSize=$( du -s ${targetDir} | head -n1 | awk '{print $1;}' )
    if [ ${#actualSize} -eq 0 ]; then
      freshSize=0
    fi
    progress=$(echo "scale=2; $freshSize*100/$targetSize" | bc)
    echo $progress > '.${name}.progress'

    # detect if since last loop any progress occured
    if [ ${actualSize} -eq ${freshSize} ]; then
      timeoutInfo="${timeout}/${maxTimeoutLoops}"
      timeout=$(( $timeout + 1 ))
    else
      timeout=1
      timeoutInfo="no timeout detected"
    fi
    actualSize=$freshSize

    # detect if mx timeout loop limit is reached
    if [ ${timeout} -gt ${maxTimeoutLoops} ]; then
      echo "FAIL - download hit timeout"
      break
    fi

    # display info screen
    clear
    echo "****************************************************"
    echo "Monitoring Screen Session: ${name}"
    echo "Progress: ${progress}% (${actualSize} of ${targetSize})"
    echo "Timeout: ${timeoutInfo}"
    echo "If needed press key x to stop ${name}"
    echo "NOTICE: This can take multiple hours or days !!"
    echo "Its OK to close terminal now and SSH back in later."
    echo "****************************************************"
    screen -S ${name} -X hardcopy .${name}.out
    newScreenDump=$(cat .Download.out | grep . | tail -8)
    if [ ${#newScreenDump} -gt 0 ]; then
      screenDump=$newScreenDump
    fi
    echo "$screenDump"

    # wait 2 seconds for key input
    read -n 1 -t 2 keyPressed

    # check if user wants to abort session
    if [ "${keyPressed}" = "x" ]; then
      echo ""
      echo "Aborting ${name}"
      break
    fi

  done

# clean up
rm -f .${name}.out
rm -f .${name}.progress

# quit session if still running
if [ ${isRunning} -eq 1 ]; then
  # get the PID of screen session
  sessionPID=$(screen -ls | grep "${name}" | cut -d "." -f1 | xargs)
  echo "killing screen session PID(${sessionPID})"
  # kill all child processes of screen sceesion
  pkill -P ${sessionPID}
  echo "proccesses klilled"
  sleep 3
 # tell the screen session to quit and wait a bit
  screen -S ${name} -X quit 1>/dev/null
  sleep 3
  echo "cleaning screen"
  screen -wipe 1>/dev/null
  sleep 3
fi

# the path torrent will download to
targetPath="${targetDir}${torrent}"
echo "path to downloaded data is ${targetPath}"

# calculate progress and write it to file for LCD to read
finalSize=$( du -s ${targetDir} 2>/dev/null | head -n1 | awk '{print $1;}' )
if [ ${#finalSize} -eq 0 ]; then
  finalSize=0
fi
echo "final size is ${finalSize} of targeted size ${targetSize}"

echo "PRESS KEY TO CONTINUE"
read key

# check result
if [ ${finalSize} -lt ${targetSize} ]; then
 
 # Download failed
  sleep 3
  echo -ne '\007'
  dialog --title " WARNING " --yesno "The download failed or is not complete. Maybe try again (later). Do you want keep already downloaded data for next try?" 8 57
  response=$?
  case $response in
    1) sudo rm -rf ${targetDir} ;;
  esac
  ./00mainMenu.sh
  exit 1;
  
else

  # Download worked
  echo "*** Moving Files ***"
  sudo mv ${targetPath} /mnt/hdd/${network}
  echo "OK"

  # continue setup
  ./60finishHDD.sh

fi