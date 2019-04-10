#!/bin/bash

# Based on https://github.com/bamarni/pi64/issues/4#issuecomment-292707581
# sysbench manual: http://imysql.com/wp-content/uploads/2014/10/sysbench-manual.pdf

# check if bechmarking tool is installed
sysbenchInstalled=$(sysbench --version 2>/dev/null | grep -c 'sysbench 0.')
if [ ${sysbenchInstalled} -eq 0 ];then
  sudo apt install -y sysbench
fi

# do debug outputs to the STDERR - so that the STDOUT is just the results in the end
echo "RaspiBlitz powertest v0.1" >&2
echo "Starting sysbench to run for 60 seconds (--max-time=60 --cpu-max-prime=10000)" >&2

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
		echo -e "${Temp}$(printf "%5s" ${SysFSClockspeed}) MHz  ${CoreVoltage}" >&2
	else
	  	echo -e "${Temp}$(printf "%5s" ${RealClockspeed})/$(printf "%4s" ${SysFSClockspeed}) MHz ${CoreVoltage}" >&2
  	fi

    # analyse values
    voltvalue="${CoreVoltage/V/}"
    echo "V -> ${voltvalue}"

	sleep 5
done