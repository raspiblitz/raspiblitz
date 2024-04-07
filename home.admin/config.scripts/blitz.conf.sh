#!/usr/bin/env bash

configFile="/mnt/hdd/raspiblitz.conf"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Config Edit - adds value to file & cache and creates entries if needed:"
  echo "blitz.conf.sh set [key] [value] [?conffile] <noquotes>"
  echo "blitz.conf.sh delete [key] [?conffile]"
  echo "blitz.conf.sh list-add [key] [value] [?conffile]"
  echo "blitz.conf.sh list-remove [key] [value] [?conffile]"
  echo "note: use quotes and escape special characters for sed"
  echo
  exit 1
fi

if [ "$1" = "set" ]; then

  # get parameters
  keystr=$2
  valuestr=$(echo "${3}" | sed 's/\//\\\//g')
  configfileAlternative=$4

  # check that key & value are given
  if [ "${keystr}" == "" ] || [ "${valuestr}" == "" ]; then
    echo "# blitz.conf.sh $*"
    echo "# FAIL: missing parameter"
    exit 1
  fi

  # optional another configfile
  if [ "${configfileAlternative}" != "" ]; then
    configFile="${configfileAlternative}"
  fi

  # update config value in cache
  /home/admin/_cache.sh set ${keystr} "${valuestr}"

  # check that config file exists
  raspiblitzConfExists=$(ls ${configFile} 2>/dev/null | grep -c "${configFile}")
  if [ ${raspiblitzConfExists} -eq 0 ]; then
    echo "# blitz.conf.sh $*"
    exit 3
  fi

  # check if key needs to be added (prepare new entry)
  entryExists=$(grep -c "^${keystr}=" ${configFile})
  if [ ${entryExists} -eq 0 ]; then
    echo "${keystr}=" | sudo tee -a ${configFile} 1>/dev/null
  fi

  # add valuestr in quotes if not standard values and "$5" != "noquotes"
  if [ "${valuestr}" != "on" ] && [ "${valuestr}" != "off" ] && [ "${valuestr}" != "1" ] && [ "${valuestr}" != "0" ] && [ "$5" != "noquotes" ]; then
    valuestr="'${valuestr}'"
  fi

  # set value (sed needs sudo to operate when user is not root)
  sudo sed -i "s/^${keystr}=.*/${keystr}=${valuestr}/g" ${configFile}


elif [ "$1" = "delete" ]; then

  # get parameters
  keystr=$2
  configfileAlternative=$3

  # check that key & value are given
  if [ "${keystr}" == "" ]; then
    echo "# FAIL: missing parameter"
    exit 1
  fi

    # optional another configfile
  if [ "${configfileAlternative}" != "" ]; then
    configFile="${configfileAlternative}"
  fi

  # delete value
  sudo sed -i "/^${keystr}=/d" ${configFile} 2>/dev/null

elif [ "$1" = "list-add" ]; then

  # get parameters
  keystr=$2
  valuestr=$(echo "${3}" | sed 's/\//\\\//g')
  configfileAlternative=$4

  # check that key & value are given
  if [ "${keystr}" == "" ] || [ "${valuestr}" == "" ]; then
    echo "# blitz.conf.sh $*"
    echo "# FAIL: missing parameter"
    exit 1
  fi

  # optional another configfile
  if [ "${configfileAlternative}" != "" ]; then
    configFile="${configfileAlternative}"
  fi

  # check if key needs to be added (prepare new entry)
  entryExists=$(grep -c "^${keystr}=" ${configFile})
  if [ ${entryExists} -eq 0 ]; then
    echo "${keystr}=" | sudo tee -a ${configFile} 1>/dev/null
  fi

  # get list value
  source ${configFile}
  listvalues="${!keystr}"
  echo "# old listvalues(${listvalues})"

  # convert list values to array
  listvalues=($listvalues)
  echo "# number of elements(${#listvalues[@]})"

  # prevent double entries
  for value in "${listvalues[@]}"
  do
     if [ "${value}" == "${valuestr}" ]; then
      echo "# blitz.conf.sh --> value(${valuestr}) already part of list with key(${keystr})"
      exit 1
     fi
  done

  # add value to list
  listvalues+=("${valuestr}")
  
  # set updated value (make sure to be in single quotes)
  listvalues=$( IFS=$' '; echo "${listvalues[*]}" )
  echo "# new listvalues(${listvalues})"
  sudo sed -i "s/^${keystr}=.*/${keystr}='${listvalues}'/g" ${configFile}

  # update config value in cache
  /home/admin/_cache.sh set ${keystr} "${listvalues}"

elif [ "$1" = "list-remove" ]; then

  # get parameters
  keystr=$2
  valuestr=$(echo "${3}" | sed 's/\//\\\//g')
  configfileAlternative=$4

  # check that key & value are given
  if [ "${keystr}" == "" ] || [ "${valuestr}" == "" ]; then
    echo "# blitz.conf.sh $*"
    echo "# FAIL: missing parameter"
    exit 1
  fi

  # optional another configfile
  if [ "${configfileAlternative}" != "" ]; then
    configFile="${configfileAlternative}"
  fi

  # get list value
  source ${configFile}
  listvalues="${!keystr}"
  echo "# old listvalues(${listvalues})"

  # convert list values to array
  listvalues=($listvalues)
  echo "# number of elements(${#listvalues[@]})"

  # sort old value out
  newlistvalues=()
  for value in "${listvalues[@]}"
  do
     if [ "${value}" != "${valuestr}" ]; then
      newlistvalues+=("${value}")
     fi
  done

  # set updated value (make sure to be in single quotes)
  listvalues=$( IFS=$' '; echo "${newlistvalues[*]}" )
  echo "# new listvalues(${listvalues})"
  sudo sed -i "s/^${keystr}=.*/${keystr}='${listvalues}'/g" ${configFile}

  # update config value in cache
  /home/admin/_cache.sh set ${keystr} "${listvalues}"

else
  echo "# FAIL: parameter not known - run with -h for help"
fi

