#!/usr/bin/env bash

configFile="/mnt/hdd/raspiblitz.conf"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Config Edit - adds value to file & cache and creates entries if needed:"
  echo "blitz.conf.sh set [key] [value]"
  echo "blitz.conf.sh delete [key]"
  echo "To use values use in shell scripts: source ${configFile}"
  echo
  exit 1
fi

if [ "$1" = "set" ]; then

  # get parameters
  keystr=$2
  valuestr=$3
  overflow=$4

  # check that key & value are given
  if [ "${keystr}" == "" ] || [ "${valuestr}" == "" ]; then
    echo "# blitz.conf.sh $@"
    echo "# FAIL: missing parameter"
    exit 1
  fi

  # check if input quotes are missing (there should be no 4th parameter)
  if [ "${overflow}" != "" ]; then
    echo "# blitz.conf.sh $@"
    echo "# FAIL: possible missing quotes in value string"
    exit 2
  fi 

  # update config value in cache
  /home/admin/_cache.sh set ${keystr} "${valuestr}"

  # check that config file exists
  raspiblitzConfExists=$(ls ${configFile} 2>/dev/null | grep -c "${configFile}")
  if [ ${raspiblitzConfExists} -eq 0 ]; then
    echo "# blitz.conf.sh $@"
    echo "# FAIL: missing config file: ${configFile}"
    exit 3
  fi

  # check if key needs to be added (prepare new entry)
  entryExists=$(grep -c "^${keystr}=" ${configFile})
  if [ ${entryExists} -eq 0 ]; then
    echo "${keystr}=" | sudo tee -a ${configFile}
  fi

  # add valuestr quotes if not standard values
  if [ "${valuestr}" != "on" ] && [ "${valuestr}" != "off" ] && [ "${valuestr}" != "1" ] && [ "${valuestr}" != "0" ]; then
    valuestr="'${valuestr}'"
  fi

  # set value (sed needs sudo to operate when user is not root)
  sudo sed -i "s/^${keystr}=.*/${keystr}=${valuestr}/g" ${configFile}


elif [ "$1" = "delete" ]; then

  # get parameters
  keystr=$2

  # check that key & value are given
  if [ "${keystr}" == "" ]; then
    echo "# FAIL: missing parameter"
    exit 1
  fi

  # delete value
  sudo sed -i "/^${keystr}=/d" ${configFile} 2>/dev/null

else
  echo "# FAIL: parameter not known - run with -h for help"
fi