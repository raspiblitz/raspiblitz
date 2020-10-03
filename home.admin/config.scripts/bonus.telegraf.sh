#!/bin/bash
#

###############################################################################
#   File:   bonus.telegraf.sh
#   Date:   2020-10-03
###############################################################################

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the telegraf metric collection on or off"
 echo "bonus.telegraf.sh [on|off|status]"
 exit 1
fi

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# Check if HDD contains configuration
configExists=$(ls ${configFile} | grep -c '.conf')
if [ ${configExists} -ne 1 ]; then
 echo "RaspiBlitz config file '${configFile}' not found"
 exit 1
fi
# at this point the config file exists and can be sourced
source ${configFile}

# this variables is used repeatedly in this script
resources_dir=/home/admin/assets/telegraf/etc-telegraf


###############################
# give status
if [ "$1" = "status" ]; then

  echo "##### STATUS TELEGRAF SERVICE"

  # check if "telegrafMonitoring" is enabled ("1"|"on") in raspiblitz.conf
  if [ "${telegrafMonitoring}" = "1" ] || [ "${telegrafMonitoring}" = "on" ]; then
    echo "configured=1"
  else
    echo "configured=0"
  fi

  serviceInstalled=$(sudo systemctl status telegraf --no-page 2>/dev/null | grep -c "telegraf.service - The plugin-driven")
  echo "serviceInstalled=${serviceInstalled}"
  if [ ${serviceInstalled} -eq 0 ]; then
    echo "infoMessage='Telegraf service not installed'"
  fi

  serviceRunning=$(sudo systemctl status telegraf --no-page 2>/dev/null | grep -c "active (running)")
  echo "serviceRunning=${serviceRunning}"
  if [ ${serviceRunning} -eq 1 ]; then
    echo "infoMessage='Telegraf service is running'"
  else
    echo "infoMessage='Not running - check: sudo journalctl -u telegraf'"
  fi

  exit 0
fi


###############################
# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL TELEGRAF ***"
  # soure and target dir for copy operation
  telegraf_source_dir=${resources_dir}
  telegraf_target_dir=/etc/telegraf
  #
  # full path to telegraf config file for sed-replace operation
  telegraf_conf_file=${telegraf_target_dir}/telegraf.conf

  echo "*** telegraf installation: apt-get part"
  # get the repository publy key for apt-get
  curl -sL https://repos.influxdata.com/influxdb.key | apt-key add -
  DISTRIB_ID=$(lsb_release -c -s)
  # 
  # changed according suggestion from @frennkie in #1501
  echo "deb https://repos.influxdata.com/debian ${DISTRIB_ID} stable" | sudo tee -a /etc/apt/sources.list.d/influxdb.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y telegraf

  echo "*** telegraf installation: usermod part"
  # enable telegraf user to call "/opt/vc/bin/vcgencmd" for frequency and temperatures measurements
  sudo usermod -aG video telegraf
  #
  # enable telegraf as admin for lnd
  sudo usermod telegraf -a -G lndadmin

  # stop telegraf service
  sudo systemctl stop telegraf.service

  echo "*** telegraf installation: copying telegraf config templates"
  # copy custom "telegraf.conf" template to the telegraf target dir
  # the telegraf inputs part goes into telegraf.d subdir
  # this split into "telegraf.conf" and "telegraf.d/teöegraf_inputs.conf" is necessary
  # as the the [[inputs.***]] part contains lines with the keywords
  # "urls", "database", "username" "password"
  # so the sed-replacement-part would get confused
  #
  # Note: the apt-get install should have already created the path /etc/telegraf and /etc/telegraf/telegraf.d
  #
  sudo cp -v ${telegraf_source_dir}/telegraf.conf                     ${telegraf_target_dir}/telegraf.conf
  sudo cp -v ${telegraf_source_dir}/telegraf.d/telegraf_inputs.conf   ${telegraf_target_dir}/telegraf.d/telegraf_inputs.conf
  #
  # copy shell script for service uptime metrics
  sudo cp -v ${telegraf_source_dir}/getserviceuptime.sh               ${telegraf_target_dir}/getserviceuptime.sh
  sudo chmod 755 ${telegraf_target_dir}/getserviceuptime.sh
  #
  # copy shell script for IP address tracking
  sudo cp -v ${telegraf_source_dir}/getraspiblitzipinfo.sh            ${telegraf_target_dir}/getraspiblitzipinfo.sh
  sudo chmod 755 ${telegraf_target_dir}/getraspiblitzipinfo.sh

  echo "*** telegraf installation: replace influxDB url and creds"
  # here comes the sed-replace-part
  #
  # make sure that raspiblitz.conf has the telegraf-variables properly set
  #   telegrafInfluxUrl
  #   telegrafInfluxDatabase
  #   telegrafInfluxUsername
  #   telegrafInfluxPassword
  #
  echo "*** telegraf installation: telegrafInfluxUrl      = '${telegrafInfluxUrl}'"
  # due to the occurance of '/' in the ${telegrafInfluxUrl} we need to switch to '#' as the sed-separator
  sudo sed -i "s#^urls = .*#urls = \[\"${telegrafInfluxUrl}\"\]#g" ${telegraf_conf_file}
  #
  # the other replacements work with the std separator '/'
  #
  # CAUTION: make sure that *none* of the following variables (especially "password") contains a '/'
  #          this would break the sed-replacement
  #
  echo "*** telegraf installation: telegrafInfluxDatabase = '${telegrafInfluxDatabase}'"
  sudo sed -i "s/^database = .*/database = \"${telegrafInfluxDatabase}\"/g" ${telegraf_conf_file}
  #
  echo "*** telegraf installation: telegrafInfluxUsername = '${telegrafInfluxUsername}'"
  sudo sed -i "s/^username = .*/username = \"${telegrafInfluxUsername}\"/g" ${telegraf_conf_file}
  #
  echo "*** telegraf installation: telegrafInfluxPassword = '${telegrafInfluxPassword}'"
  sudo sed -i "s/^password = .*/password = \"${telegrafInfluxPassword}\"/g" ${telegraf_conf_file}


  echo "*** telegraf installation: restart telegraf service with updated config files"
  # restart telegraf service
  sudo systemctl start telegraf.service
  # ...and push some status into the logfile
  sleep 2
  sudo systemctl status telegraf.service --no-page 2>/dev/null

  echo "*** telegraf installation: set 'telegrafMonitoring=on' in config file '${configFile}'"
  sudo sed -i "s/^telegrafMonitoring=.*/telegrafMonitoring=on/g" ${configFile}


  echo "*** install telegraf done ***"

  exit 0
fi


###############################
# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** REMOVE TELEGRAF ***"

  # let apt-get remove the package
  sudo apt-get remove -y telegraf

  echo "*** telegraf remove: set 'telegrafMonitoring=off' in config file '${configFile}'"
  sudo sed -i "s/^telegrafMonitoring=.*/telegrafMonitoring=off/g" ${configFile}

  echo "*** remove telegraf done ***"

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
