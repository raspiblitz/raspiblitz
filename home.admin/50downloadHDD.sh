#!/bin/bash
echo ""

## get basic info
source /home/admin/raspiblitz.info

# *** BITCOIN (just mainnet) ***
bitcoinList="" # url to list with other sources
#bitcoinUrl="ftp://anonymous:anonymous@91.83.237.185:21/raspiblitz-bitcoin-2018-07-16"
bitcoinUrl="ftp://f00f39c4:download@w0189aba.kasserver.com/"
bitcoinSize=253000000 # 253827180-tolerance

# *** LITECOIN ***
litecoinList="" # url to list with other sources
litecoinUrl="ftp://anonymous:anonymous@ftp.rotzoll.de/pub/raspiblitz-litecoin-2018-11-30"
litecoinSize=22220000 # 22221160-tolerance

# NOTE TO GET THE SIZE RIGHT: for new download add 9999999999 as size. Run download.
# When finished the warning comes up and behind WARNING: copy that number

# settings based on network
list=$bitcoinList
url=$bitcoinUrl
size=$bitcoinSize
if [ "$network" = "litecoin" ]; then
  list=$litecoinList
  url=$litecoinUrl
  size=$litecoinSize
fi

# screen background monitoring settings
name="Download"
targetDir="/mnt/hdd/download/"
targetSize=$size
command="sudo wget -c -r -P ${targetDir} -q --show-progress ${url}"

# starting session if needed
echo "checking if ${name} has a running screen session"
screen -wipe 1>/dev/null
isRunning=$( screen -S ${name} -ls | grep "${name}" -c )
echo "isRunning(${isRunning})"
if [ ${isRunning} -eq 0 ]; then
  echo "Starting screen session"
  sudo mkdir ${targetDir} 2>/dev/null
  screen -S ${name} -dm ${command}
else
  echo "Continue screen session"
fi
sleep 3

# monitor session
screenDump="... started ..."
actualSize=0
while :
  do

    # check if session is still running
    screen -wipe 1>/dev/null
    isRunning=$( screen -S ${name} -ls | grep "${name}" -c )
    if [ ${isRunning} -eq 0 ]; then
      echo "OK - session finished"
      break
    fi

    # calculate progress and write it to file for LCD to read
    freshSize=$( du -s ${targetDir} | head -n1 | awk '{print $1;}' )
    if [ ${#actualSize} -eq 0 ]; then
      freshSize=0
    fi
    progress=$(echo "scale=2; $freshSize*100/$targetSize" | bc)
    echo $progress > ".${name}.progress"

    actualSize=$freshSize

    # display info screen
    clear
    echo "****************************************************"
    echo "Monitoring Screen Session: ${name}"
    echo "Progress: ${progress}% (${actualSize} of ${targetSize})"
    echo "If needed press key x to stop ${name}"
    echo "NOTICE: This can take multiple hours or days !!"
    echo "Its OK to close terminal now and SSH back in later."
    echo "****************************************************"
    screen -S ${name} -X hardcopy .${name}.out
    newScreenDump=$(cat .${name}.out | grep . | tail -8)
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
  echo "proccesses killed"
  sleep 3
 # tell the screen session to quit and wait a bit
  screen -S ${name} -X quit 1>/dev/null
  sleep 3
  echo "cleaning screen"
  screen -wipe 1>/dev/null
  sleep 3
fi

# the path wget will download to
targetPath=$(echo ${url} | cut -d '@' -f2)
echo "path to downloaded data is ${targetPath}"

# calculate progress and write it to file for LCD to read
finalSize=$( du -s ${targetDir} 2>/dev/null | head -n1 | awk '{print $1;}' )
if [ ${#finalSize} -eq 0 ]; then
  finalSize=0
fi
echo "final size is ${finalSize} of targeted size ${targetSize}"

# check result
if [ ${finalSize} -lt ${targetSize} ]; then
 
 # Download failed
  sleep 3
  echo -ne '\007'
  dialog --title " WARNING (${finalSize}) " --yesno "The download failed or is not complete. Maybe try again (later). Do you want keep already downloaded data for next try?" 8 57
  response=$?
  case $response in
    1) sudo rm -rf /mnt/hdd/download ;;
  esac
  ./00mainMenu.sh
  exit 1;
  
else

  # Download worked
  echo "*** Moving Files ***"
  sudo mv ${targetDir}${targetPath} /mnt/hdd/${network}
  echo "OK"

  if [ ${setupStep} -lt 100 ]; then
    # set SetupState
    sudo sed -i "s/^setupStep=.*/setupStep=50/g" /home/admin/raspiblitz.info
    # continue setup
    ./60finishHDD.sh
  fi

fi