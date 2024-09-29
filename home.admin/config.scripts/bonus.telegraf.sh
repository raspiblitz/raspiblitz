#!/bin/bash
#

###############################################################################
#   File:   bonus.telegraf.sh
###############################################################################

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the telegraf metric collection on or off"
 echo "bonus.telegraf.sh status ---> get status of telegraf service"
 echo "bonus.telegraf.sh on     ---> install & config"
 echo "bonus.telegraf.sh off    ---> uninstall & reset config"
 exit 1
fi

# at this point the config file exists and can be sourced
source /mnt/hdd/raspiblitz.conf

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


# Function to check if input is empty
function check_empty() {
    if [ -z "$1" ]; then
        return 1
    else
        return 0
    fi
}

# Function to validate IP address or domain with optional http(s) and port
function validate_url() {
    if [[ "$1" =~ ^(https?://)?([a-zA-Z0-9.-]+|\b\d{1,3}(\.\d{1,3}){3}\b):[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

###############################
# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "*** INSTALL TELEGRAF ***"

  # check installed by looking for service
  serviceInstalled=$(sudo systemctl status telegraf --no-page 2>/dev/null | grep -c "telegraf.service - The plugin-driven")
  if [ ${serviceInstalled} -eq 1 ]; then
    echo "# Telegraf service is installed."
    echo "# If you want to reset config and reinstall, please switch off first."
    exit 0
  fi

  # check if config data in raspiblitz.conf is available
  configMissing=0
  if [ ${#telegrafInfluxUrl} -eq 0 ]; then
    echo "# Missing telegrafInfluxUrl in raspiblitz.conf"
    configMissing=1
  fi
  if [ ${#telegrafInfluxDatabase} -eq 0 ]; then
    echo "# Missing telegrafInfluxDatabase in raspiblitz.conf"
    configMissing=1
  fi
  if [ ${#telegrafInfluxUsername} -eq 0 ]; then
    echo "# Missing telegrafInfluxUsername in raspiblitz.conf"
    configMissing=1
  fi
  if [ ${#telegrafInfluxPassword} -eq 0 ]; then
    echo "# Missing telegrafInfluxPassword in raspiblitz.conf"
    configMissing=1
  fi

  # enter config if missing (first init)
  if [ ${configMissing} -eq 1 ]; then
  
    # Display the info box with whiptail
    whiptail --title "Metrics Setup Information" --yesno "To run the Telegraf metrics service you need an external monitoring server running Grafana & InfluxDB. Please prepare InfluxDB database & user as described in github.com/raspiblitz/raspiblitz/tree/dev/home.admin/assets/telegraf Choose YES if all is ready to config RaspiBlitz Telegraf service." 11 75;
    if [ $? -eq 1 ]; then
      echo "# user cancel"
      exit 0
    fi

    # Collect telegrafInfluxUrl
    telegrafInfluxUrl=""
    while true; do
      telegrafInfluxUrl=$(whiptail --inputbox "Enter the IP address or domain followed by port of your metrics InfluxDB (e.g., http://192.168.1.1:8086):" 8 78 "${telegrafInfluxUrl}" --title "InfluxDB Connection" 3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus -ne 0 ]; then
        echo "Operation canceled by user."
        exit 1
      fi
      if ! check_empty "$telegrafInfluxUrl"; then
        whiptail --msgbox "Input cannot be empty. Please enter a valid URL." 8 78
        continue
      fi
      if ! validate_url "$telegrafInfluxUrl"; then
        whiptail --msgbox "Invalid format. Please enter a valid IP address or domain followed by a port, with optional http(s) prefix." 8 78
        continue
      fi
      # Perform a test using curl to check if the service is running
      [[ $telegrafInfluxUrl =~ ^(http|https):// ]] || telegrafInfluxUrl="http://$telegrafInfluxUrl"
      if curl --output /dev/null --silent --head --fail "${telegrafInfluxUrl}/ping"; then
        echo "OK Service is running at $telegrafInfluxUrl."
        break
      else
        whiptail --msgbox "Was not able to connect to ${telegrafInfluxUrl} - please make sure InfluxDB is running and reachable for RaspiBlitz." 8 78
        continue
      fi
    done

    # Collect telegrafInfluxDatabase
    while true; do
      telegrafInfluxDatabase=$(whiptail --inputbox "Enter the name of the database where to store the metrics:" 8 78 "raspiblitz" --title "InfluxDB Database" 3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus -ne 0 ]; then
        echo "Operation canceled by user."
        exit 1
      fi
      if ! check_empty "$telegrafInfluxDatabase"; then
        whiptail --msgbox "Input cannot be empty. Please enter a valid database name." 8 78
        continue
      fi
      break
    done

    # Collect telegrafInfluxUsername
    while true; do
      telegrafInfluxUsername=$(whiptail --inputbox "Enter the username that is allowed to write on that database:" 8 78 "raspiblitz" --title "InfluxDB Username" 3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus -ne 0 ]; then
        echo "Operation canceled by user."
        exit 1
      fi
      if ! check_empty "$telegrafInfluxUsername"; then
        whiptail --msgbox "Input cannot be empty. Please enter a valid username." 8 78
        continue
      fi
      break
    done

    # Collect telegrafInfluxPassword
    while true; do
      telegrafInfluxPassword=$(whiptail --passwordbox "Enter the password for that username:" 8 78 --title "InfluxDB Password" 3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus -ne 0 ]; then
        echo "Operation canceled by user."
        exit 1
      fi
      if ! check_empty "$telegrafInfluxPassword"; then
        whiptail --msgbox "Input cannot be empty. Please enter a valid password." 8 78
        continue
      fi
      break
    done

    # save the config data to raspiblitz.conf
    /home/admin/config.scripts/blitz.conf.sh set telegrafInfluxUrl "${telegrafInfluxUrl}"
    /home/admin/config.scripts/blitz.conf.sh set telegrafInfluxDatabase "${telegrafInfluxDatabase}"
    /home/admin/config.scripts/blitz.conf.sh set telegrafInfluxUsername "${telegrafInfluxUsername}"
    /home/admin/config.scripts/blitz.conf.sh set telegrafInfluxPassword "${telegrafInfluxPassword}"
  fi

  # source and target dir for copy operation
  telegraf_source_dir=${resources_dir}
  telegraf_target_dir=/etc/telegraf
  
  # full path to telegraf config file for sed-replace operation
  telegraf_conf_file=${telegraf_target_dir}/telegraf.conf

  echo "*** telegraf installation: apt-get part"
  # get the repository public key for apt-get
  curl -sL https://repos.influxdata.com/influxdb.key | sudo apt-key add -
  DISTRIB_ID=$(lsb_release -c -s)
  # 
  # changed according suggestion from @frennkie in #1501
  echo "deb https://repos.influxdata.com/debian ${DISTRIB_ID} stable" | sudo tee -a /etc/apt/sources.list.d/influxdb.list >/dev/null
  #
  # as the key is untrusted, this is a dirty fix
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys D8FF8E1F7DF8B07E
  sudo apt-get update
  sudo apt-get install -y telegraf

  echo "*** telegraf installation: usermod part"
  # enable telegraf user to call "/opt/vc/bin/vcgencmd" for frequency and temperatures measurements
  sudo usermod -aG video telegraf
  #
  # enable telegraf as admin for lnd
  sudo usermod telegraf -a -G lndadmin
  #
  # add telegraf to sudoers (for later application with smartmontools)
  sudo usermod telegraf -a -G sudo

  # stop telegraf service
  sudo systemctl stop telegraf.service

  echo "*** telegraf installation: copying telegraf config templates"
  # copy custom "telegraf.conf" template to the telegraf target dir
  # the telegraf inputs part goes into telegraf.d subdir
  # this split into "telegraf.conf" and "telegraf.d/telegraf_inputs.conf" is necessary
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
  # due to the occurrence of '/' in the ${telegrafInfluxUrl} we need to switch to '#' as the sed-separator
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

  echo "*** telegraf installation: set 'telegrafMonitoring=on' in config file 'raspiblitz.conf'"
  /home/admin/config.scripts/blitz.conf.sh set telegrafMonitoring "on"

  echo "*** install telegraf done ***"

  exit 0
fi


###############################
# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** REMOVE TELEGRAF ***"

  # let apt-get remove the package
  sudo apt-get remove -y telegraf

  echo "*** telegraf switch off and remove config ***"
  /home/admin/config.scripts/blitz.conf.sh set telegrafMonitoring "off"
  /home/admin/config.scripts/blitz.conf.sh delete telegrafInfluxUrl
  /home/admin/config.scripts/blitz.conf.sh delete telegrafInfluxDatabase
  /home/admin/config.scripts/blitz.conf.sh delete telegrafInfluxUsername
  /home/admin/config.scripts/blitz.conf.sh delete telegrafInfluxPassword

  echo "*** remove telegraf done ***"

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
