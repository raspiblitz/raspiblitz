#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "run stress test to measure heat and voltage"
 echo "blitz.stresstest.sh [?filenameForReport]"
 exit 1
fi

isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
if [ ${isRaspbian} -eq 0 ]; then
  echo "the OS is not Raspbian - the stresstest is only for the Raspberry Pi"
  exit 0
fi

# Based on https://github.com/bamarni/pi64/issues/4#issuecomment-292707581
# sysbench manual: http://imysql.com/wp-content/uploads/2014/10/sysbench-manual.pdf

# get parameter
filenameForReport=$1

# check if bechmarking tool is installed
sysbenchInstalled=$(sysbench --version 2>/dev/null | grep -c 'sysbench 0.')
if [ ${sysbenchInstalled} -eq 0 ];then
  sudo apt install -y sysbench
fi

# do debug outputs to the STDERR - so that the STDOUT is just the results in the end
echo "RaspiBlitz Hardwaretest v0.2" >&2

# detect hardware version of RaspberryPi
# https://www.unixtutorial.org/command-to-confirm-raspberry-pi-model
raspberryPi=$(cat /proc/device-tree/model | cut -d " " -f 3 | sed 's/[^0-9]*//g')
if [ ${#raspberryPi} -eq 0 ]; then
  raspberryPi=0
fi
echo "RaspberryPi Model Version: ${raspberryPi}"
if [ ${raspberryPi} -lt 4 ]; then
  # raspberryPi 3 and lower (microUSB power connector)
  voltWARN=1230000
  voltFAIL=1200100
  tempWARNING=6500
  tempCRTICAL=6999
else
  # raspberryPi 4 and up (USB-C power connector)
  voltWARN=833200
  voltFAIL=823200
  tempWARNING=6900
  tempCRTICAL=7799
fi

echo "Starting sysbench to run for 60 seconds (--max-time=60 --cpu-max-prime=100000)" >&2

# result values
powerWARN=0
powerFAIL=0
powerMIN=9999999
tempWARN=0
tempFAIL=0
tempMAX=0

# starting bench mark
sysbench --max-time=60 --test=cpu --cpu-max-prime=100000 --num-threads=4 run 1>/dev/null 2>&1 & 

# keep monitoring in the background
Maxfreq=$(( $(awk '{printf ("%0.0f",$1/1000); }'  </sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) -15 ))
for (( n=0; n<15; ++n )); do

    # make measurements
	Temp=$(sudo vcgencmd measure_temp | cut -f2 -d=)
	RealClockspeed=$(sudo vcgencmd measure_clock arm | awk -F"=" '{printf ("%0.0f",$2/1000000); }' )
	SysFSClockspeed=$(awk '{printf ("%0.0f",$1/1000); }' </sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
	CoreVoltage=$(sudo vcgencmd measure_volts | cut -f2 -d= | sed 's/000//')

    # debug output
	if [ ${RealClockspeed} -ge ${Maxfreq} ]; then
		echo "${Temp}$(printf "%5s" ${SysFSClockspeed}) MHz  ${CoreVoltage}" >&2
	else
	  	echo "${Temp}$(printf "%5s" ${RealClockspeed})/$(printf "%4s" ${SysFSClockspeed}) MHz ${CoreVoltage}" >&2
  	fi

    # analyse Voltage
    voltFloat=$(echo "${CoreVoltage/V/}*1000000" | bc)
    voltInt=${voltFloat/.*}
    #echo "V -> ${voltFloat}/${voltInt}"
    if [ ${voltInt} -lt ${voltFAIL} ] && [ ${powerWARN} -gt 1 ]; then
      ((powerFAIL=powerFAIL+1))
      echo "--> Power CRITICAL detected" >&2
    fi
    if [ ${voltInt} -lt ${voltWARN} ]; then
      ((powerWARN=powerWARN+1))
      echo "--> Power WARN detected" >&2
    fi
    if [ ${voltInt} -lt ${powerMIN} ]; then
      powerMIN=${voltInt}
    fi

    # analyse Temp
    tempFloat=$(echo "${Temp/\'C/}*100" | bc)
    tempInt=${tempFloat/.*}
    #echo "T -> ${tempFloat}/${tempInt}"
    if [ ${tempInt} -gt ${tempCRTICAL} ]; then
      ((tempFAIL=tempFAIL+1))
      echo "--> Temp CRITICAL detected" >&2
    fi
    if [ ${tempInt} -gt ${tempWARNING} ]; then
      ((tempWARN=tempWARN+1))
      echo "--> Temp WARN detected" >&2
    fi
    if [ ${tempInt} -gt ${tempMAX} ]; then
      tempMAX=${tempInt}
    fi

	sleep 5
done

if [ ${#filenameForReport} -eq 0 ]; then
  echo "raspberryPi=${raspberryPi}"
  echo "powerFAIL=${powerFAIL}"
  echo "powerWARN=${powerWARN}"
  echo "powerMIN='${powerMIN} microVolt'"
  echo "tempFAIL=${tempFAIL}"
  echo "tempWARN=${tempWARN}"
  echo "tempMAX='${tempMAX} centiGrad'"
else
  echo "raspberryPi=${raspberryPi}" >${filenameForReport}
  echo "powerFAIL=${powerFAIL}" >>${filenameForReport}
  echo "powerWARN=${powerWARN}" >>${filenameForReport}
  echo "powerMIN='${powerMIN} microVolt'" >>${filenameForReport}
  echo "tempFAIL=${tempFAIL}" >>${filenameForReport}
  echo "tempWARN=${tempWARN}" >>${filenameForReport}
  echo "tempMAX='${tempMAX} centiGrad'" >>${filenameForReport}
  sudo chmod 744 ${filenameForReport}
fi
