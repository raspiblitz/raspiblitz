# experimental script to let downloads run 
# in background with screen an monitor

name="Download"
targetDir="./test/"
targetSize=2085832
maxTimeoutLoops=10
command="wget -P ${targetDir} http://wiki.fulmo.org/downloads/raspiblitz-2018-07-29b.img.gz"

# starting session if needed
echo "checking if ${name} has a running screen session"
screen -wipe 1>/dev/null
isRunning=$( screen -S ${name} -ls | grep "${name}" -c )
echo "isRunning(${isRunning})"
if [ ${isRunning} -eq 0 ]; then
  echo "Starting screen session"
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
    echo "****************************************"
    echo "Monitoring Screen Session: ${name}"
    echo "Progress: ${progress}% (${actualSize} of ${targetSize})"
    echo "Timeout: ${timeoutInfo}"
    echo "Press key x to abort this process"
    echo "****************************************"
    screen -S ${name} -X hardcopy .${name}.out
    newScreenDump=$(cat .Download.out | grep . | tail -15)
    if [ ${#newScreenDump} -gt 0 ]; then
      screenDump=$newScreenDump
    fi
    echo $screenDump

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
  echo "killing screen session TODO: KILL PROCESS"
  screen -S ${name} -X quit
  sleep 3
fi

# decide on how to continue
