#!/bin/bash

# LOAD DATA & PRECHECK

# path to old or init configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# check if there is a config file
configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
  echo "FAIL: no config file (${configFile}) found to init or upgrade!"
  exit 1
fi

# load old or init raspiblitz config
source ${configFile}

# check if config files contains basic: network
if [ ${#network} -eq 0 ]; then
  echo "FAIL: missing network in (${configFile})!"
  exit 1
fi

# check if config files contains basic: chain
if [ ${#chain} -eq 0 ]; then
  echo "FAIL: missing chain in (${configFile})!"
  exit 1
fi

# check if config files contains basic: hostname
if [ ${#hostname} -eq 0 ]; then
  echo "FAIL: missing hostname in (${configFile})!"
  exit 1
fi

# load codeVersion
source /home/admin/_version.info

# check if code version was loaded
if [ ${#codeVersion} -eq 0 ]; then
  echo "FAIL: no code version (/home/admin/_version.info) found!"
  exit 1
fi

# DEFAULT VALUES - MISSING data fields on init or upadte

echo ""
echo "*****************************"
echo "Default Values"
echo "*****************************"

# AUTOPILOT
# autoPilot=off|on
if [ ${#autoPilot} -eq 0 ]; then
  echo "autoPilot=off" >> $configFile
fi

# AUTO NAT DISCOVERY
# autoNatDiscovery=off|on
if [ ${#autoNatDiscovery} -eq 0 ]; then
  echo "autoNatDiscovery=off" >> $configFile
fi

# TOR
# runBehindTor=off|on
if [ ${#runBehindTor} -eq 0 ]; then
  echo "runBehindTor=off" >> $configFile
fi

# RideTheLightning RTL
# rtlWebinterface=off|on
if [ ${#rtlWebinterface} -eq 0 ]; then
  echo "rtlWebinterface=off" >> $configFile
fi

# MIGRATION - DATA CONVERSION when updating config
# this is the place if on a future version change
# a conversion of config data or app data is needed 

echo ""
echo "*****************************"
echo "Version Migration Steps"
echo "*****************************"
echo "Version Code: ${codeVersion}"
echo "Version Data: ${raspiBlitzVersion}"

if [ "${raspiBlitzVersion}" != "${codeVersion}" ]; then
  echo "detected version change ... starting migration script"
  echo "TODO: Update Migration check ... only needed after version 1.0"
else
  echo "OK - version of config data is up to date"
fi

echo ""
exit 0

