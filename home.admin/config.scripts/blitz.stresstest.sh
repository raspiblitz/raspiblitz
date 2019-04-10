#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "run stress test to measure heat and voltage"
 echo "blitz.stresstest.sh [?filenameForReport]"
 exit 1
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
echo "RaspiBlitz Powertest v0.1" >&2
echo "Starting sysbench to run for 60 seconds (--max-time=60 --cpu-max-prime=10000)" >&2

# result values
powerWARN=0
powerFAIL=0
powerMIN=9999999
tempWARN=0
tempFAIL=0
tempMAX=0

# starting bench mark
sysbench --max-time=60 --test=cpu --cpu-max-prime=10000 --num-threads=4 run 1>/dev/null 2>&1 & 

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
    if [ ${voltInt} -lt 1200100 ]; then
      powerFAIL=1
    fi
    if [ ${voltInt} -lt 1250000 ]; then
      powerWARN=1
    fi
    if [ ${voltInt} -lt ${powerMIN} ]; then
      powerMIN=${voltInt}
    fi

    # analyse Temp
    tempFloat=$(echo "${Temp/\'C/}*100" | bc)
    tempInt=${tempFloat/.*}
    #echo "T -> ${tempFloat}/${tempInt}"
    if [ ${tempInt} -gt 6999 ]; then
      tempFAIL=1
    fi
    if [ ${tempInt} -gt 6500 ]; then
      tempWARN=1
    fi
    if [ ${tempInt} -gt ${tempMAX} ]; then
      tempMAX=${tempInt}
    fi

	sleep 5
done

if [ ${#filenameForReport} -eq 0 ]; then
  echo "powerFAIL=${powerFAIL}"
  echo "powerWARN=${powerWARN}"
  echo "powerMIN='${powerMIN} microVolt'"
  echo "tempFAIL=${tempFAIL}"
  echo "tempWARN=${tempWARN}"
  echo "tempMAX='${tempMAX} centiGrad'"
else
  echo "powerFAIL=${powerFAIL}" >${filenameForReport}
  echo "powerWARN=${powerWARN}" >>${filenameForReport}
  echo "powerMIN='${powerMIN} microVolt'" >>${filenameForReport}
  echo "tempFAIL=${tempFAIL}" >>${filenameForReport}
  echo "tempWARN=${tempWARN}" >>${filenameForReport}
  echo "tempMAX='${tempMAX} centiGrad'" >>${filenameForReport}
fi
