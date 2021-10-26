#!/usr/bin/env bash

configFile="/mnt/hdd/raspiblitz.conf"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Config Edit - adds value and creates if needed"
  echo "You find config file under: ${configFile}"
  echo
  echo "blitz.cache.sh set [key] [value]"
  echo
  exit 1
fi

if [ "$1" = "set" ]; then

  # get parameters
  keystr=$2
  valuestr=$3

  # check that key & value are given
  if [ "${keystr}" == "" ] || [ "${valuestr}" == "" ]; then
    echo "# Fail: missing parameter"
    exit 1
  fi

  # check that config file exists
  raspiblitzConfExists=$(ls ${configFile} 2>/dev/null | grep -c "${configFile}")
  if [ ${raspiblitzConfExists} -eq 0 ]; then
    echo "# Fail: missing config file: ${configFile}"
    exit 1
  fi
  
  # check if key needs to be added (prepare new entry)
  entryExists=$(grep -c "^${keystr}=" ${configFile})
  if [ ${entryExists} -eq 0 ]; then
    echo "${keystr}=" >> ${configFile}
  fi

  # add valuestr quotes if not standard values
  if [ "${valuestr}" != "on" ] && [ "${valuestr}" != "off" ] && [ "${valuestr}" != "1" ] && [ "${valuestr}" != "0" ]; then
    valuestr="'${valuestr}'"
  fi

  # set value (sed needs sudo to operate when user is not root)
  sudo sed -i "s/^${keystr}=.*/${keystr}=${valuestr}/g" ${configFile}

else
  echo "# FAIL: parameter not known - run with -h for help"
fi
