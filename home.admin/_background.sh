#!/bin/bash

# This script runs on after start in background
# as a service and gets restarted on failure
# it runs ALMOST every seconds

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# Check if HDD contains configuration
configExists=$(ls ${configFile} | grep -c '.conf')
if [ ${configExists} -eq 1 ]; then
    source ${configFile}
fi

counter=0
while [ 1 ]
do

  ###############################
  # Prepare this loop
  ###############################

  # count up
  counter=$(($counter+1))
  echo "counter($counter)"

  ####################################################
  # RECHECK DHCP-SERVER 
  # https://github.com/rootzoll/raspiblitz/issues/160
  ####################################################

  # every 5 minutes
  recheckDHCP=$((($counter % 300)+1))
  if [ ${recheckDHCP} -eq 1 ]; then
    echo "*** RECHECK DHCP-SERVER  ***"

    # get the local network IP
    localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
    echo "localip(${localip})"

    # detect a missing DHCP config 
    if [ "${localip:0:4}" = "169." ]; then
      echo "Missing DHCP detected ... trying emergency reboot"
      sudo shutdown -r now
    else
      echo "DHCP OK"
    fi

  fi

  ####################################################
  # RECHECK PUBLIC IP
  # when public IP changes, restart LND with new IP
  ####################################################

  # every 15min - not too often
  # because its a ping to external service
  recheckPublicIP=$((($counter % 60)+1))
  if [ ${recheckPublicIP} -eq 1 ]; then
    echo "*** RECHECK PUBLIC IP ***"

    # execute only after setup when config exists
    if [ ${configExists} -eq 1 ]; then

      # get actual public IP
      freshPublicIP=$(curl -s http://v4.ipv6-test.com/api/myip.php 2>/dev/null)
      echo "freshPublicIP(${freshPublicIP})"
      echo "publicIP(${publicIP})"

      # check if changed
      if [ "${freshPublicIP}" != "${publicIP}" ]; then

        # 1) update config file
        echo "update config value"
        sed -i "s/^publicIP=.*/publicIP=${freshPublicIP}/g" ${configFile}
        publicIP=${freshPublicIP}

        # 2) restart the LND
        echo "restart LND with new environment config"
        sudo systemctl restart lnd.service

      else
        echo "public IP has not changed"
      fi

    else
      echo "skip - because setup is still running"
    fi

  fi

  ###############################
  # Prepare next loop
  ###############################

  # sleep 1 sec
  sleep 1

  # limit counter to max seconds per week:
  # 604800 = 60sec * 60min * 24hours * 7days
  if [ ${counter} -gt 1000 ]; then
    counter=0
    echo "counter zero reset"
  fi

done

