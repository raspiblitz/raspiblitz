#!/bin/bash
Maxfreq=$(( $(awk '{printf ("%0.0f",$1/1000); }'  </sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) -15 ))
while true ; do
	# Health=$(perl -e "printf \"%19b\n\", $(vcgencmd get_throttled | cut -f2 -d=)")
	Temp=$(vcgencmd measure_temp | cut -f2 -d=)
	RealClockspeed=$(vcgencmd measure_clock arm | awk -F"=" '{printf ("%0.0f",$2/1000000); }' )
	SysFSClockspeed=$(awk '{printf ("%0.0f",$1/1000); }' </sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
	CoreVoltage=$(vcgencmd measure_volts | cut -f2 -d= | sed 's/000//')
	if [ ${RealClockspeed} -ge ${Maxfreq} ]; then
	  echo -e "${Temp}$(printf "%5s" ${SysFSClockspeed}) MHz $(printf "%019d" ${Health}) ${CoreVoltage}"
	else
	  echo -e "${Temp}$(printf "%5s" ${SysFSClockspeed})/$(printf "%4s" ${RealClockspeed}) MHz ${CoreVoltage}"
  fi
	sleep 5
done