#!/usr/bin/env bash

# the cache concept of RaspiBlitz has two options
# 1) RAMDISK for files under /var/cache/raspiblitz
# 2) KEY-VALUE STORE for system state infos (REDIS)

# SECURITY NOTE: The files on the RAMDISK can be set with unix file permissions and so restrict certain users access.
# But all data stored in the KEY-VALUE STORE has to be asumed as system-wide public information.

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Cache"
  echo
  echo "_cache.sh ramdisk [on|off]"
  echo "_cache.sh keyvalue [on|off]"
  echo
  echo "_cache.sh set [key] [value] [?expire-seconds]"
  echo "_cache.sh get [key1] [?key2] [?key3] ..."
  echo 
  echo "_cache.sh increment [key1]"
  echo
  echo "_cache.sh outdate [key] [value] [?duration-seconds]"
  echo "# set in how many seconds value is marked as outdated or"
  echo "# -1 = never outdated (default)"  
  echo "# 0  = always outdated"
  echo "# set a 'duration-seconds' after defaults to -1 (optional)"
  echo 
  echo "_cache.sh meta [key] [?default]"
  echo "# get single key with additional metadata:"
  echo "# outdatesecs= see above"
  echo "# stillvalid=0/1 if value is still valid or outdated"
  echo "# lasttouch= last update timestamp in unix seconds"
  echo 
  echo "_cache.sh valid [key1] [?key2] [?key3] ..."
  echo "# check multiple keys if all are still not outdated"
  echo "# use for example to check if a complex call needs"
  echo "# to be made that covers multiple single data points"
  echo 
  echo "_cache.sh import [bash-keyvalue-file]"
  echo "# import a bash style key-value file into store"
  echo
  echo "_cache.sh export [?key-prefix]"
  echo "# export bash-style key-value to stdout"
  echo "# can be used with a key-prefix just get a subset"
  echo
  exit 1
fi

# BACKGROUND: we need to build outdated meta info manually, 
# because there is nothing as "AGE" in redis: https://github.com/redis/redis/issues/1147
# only feature that can be used uis the EXPIRE feature to determine if a value is still valid

# postfixes for metadata in key/value store
META_OUTDATED_SECONDS=":out"
META_LASTTOUCH_TS=":ts"
META_VALID_FLAG=":val"

# path of the raspiblitz.info file (persiting cache values)
infoFile="/home/admin/raspiblitz.info"

###################
# RAMDISK
# will be available under /var/cache/raspiblitz
###################

# install
if [ "$1" = "ramdisk" ] && [ "$2" = "on" ]; then

  echo "# Turn ON: RAMDISK"

  if ! grep -Eq '^tmpfs.*/var/cache/raspiblitz' /etc/fstab; then

    if grep -Eq '/var/cache/raspiblitz' /etc/fstab; then
      # entry is in file but most likely just disabled -> re-enable it
      sudo sed -i -E 's|^#(tmpfs.*/var/cache/raspiblitz.*)$|\1|g' /etc/fstab
    else
      # missing -> add
      echo "" | sudo tee -a /etc/fstab >/dev/null
      echo "tmpfs         /var/cache/raspiblitz  tmpfs  nodev,nosuid,size=32M  0  0" | sudo tee -a /etc/fstab >/dev/null
    fi
  fi

  if ! findmnt -l /var/cache/raspiblitz >/dev/null; then
    sudo mkdir -p /var/cache/raspiblitz
    sudo mount /var/cache/raspiblitz
  fi


# uninstall
elif [ "$1" = "ramdisk" ] && [ "$2" = "off" ]; then

  echo "# Turn OFF: RAMDISK"

  if grep -Eq '/var/cache/raspiblitz' /etc/fstab; then
    sudo sed -i -E 's|^(tmpfs.*/var/cache/raspiblitz.*)$|#\1|g' /etc/fstab
  fi

  if findmnt -l /var/cache/raspiblitz >/dev/null; then
    sudo umount /var/cache/raspiblitz
  fi

###################
# KEYVALUE (REDIS)
###################

# install
elif [ "$1" = "keyvalue" ] && [ "$2" = "on" ]; then

  echo "# Turn ON: KEYVALUE-STORE (REDIS)"
  sudo apt install -y redis-server

  # edit config: dont save to disk
  sudo sed -i "/^save .*/d" /etc/redis/redis.conf

  # restart with new config
  sudo systemctl restart redis-server

  # clean old databases if exist
  sudo rm /var/lib/redis/dump.rdb 2>/dev/null

  # restart again this time there is no old data dump to load
  sudo systemctl restart redis-server

# uninstall
elif [ "$1" = "keyvalue" ] && [ "$2" = "off" ]; then

  echo "# Turn OFF: KEYVALUE-STORE (REDIS)"
  sudo apt remove -y redis-server

###################
# SET/GET/IMPORT
# basic key value
###################

# set
elif [ "$1" = "set" ]; then

  # get parameters
  keystr=$2
  valuestr=$3
  expire=$4

  # check that key & value are given
  if [ "${keystr}" == "" ]; then
    echo "# Fail: missing parameter"
    exit 1
  fi

  # filter from expire just numbers
  expire="${expire//[^0-9.]/}"

  # add an expire flag if given
  additionalParams=""
  if [ "${expire}" != "" ]; then
    additionalParams="EX ${expire}"
  fi

  # set in redis key value cache
  redis-cli set ${keystr} "${valuestr}" ${additionalParams} 1>/dev/null

  # set in redis the timestamp
  timestamp=$(date +%s)
  redis-cli set ${keystr}${META_LASTTOUCH_TS} "${timestamp}" ${additionalParams} 1>/dev/null
  #echo "# lasttouch(${timestamp})"

  # check if the value has a outdate policy
  outdatesecs=$(redis-cli get ${keystr}${META_OUTDATED_SECONDS})
  if [ "${outdatesecs}" == "" ]; then
    outdatesecs="-1"
  fi 
  #echo "# outdatesecs(${outdatesecs})"
  if [ "${outdatesecs}" != "-1" ]; then
    # set exipire valid flag (if its gone - value is considered as outdated)
    redis-cli set ${keystr}${META_VALID_FLAG} "1" EX ${outdatesecs} 1>/dev/null
  fi

  # also update value if part of raspiblitz.info (persiting values to survice boot)
  persistKey=$(cat ${infoFile} | grep -c "^${keystr}=")
  if [ ${persistKey} -gt 0 ]; then
    sudo sed -i "s/^${keystr}=.*/${keystr}='${valuestr}'/g" ${infoFile}
  fi

# get
elif [ "$1" = "get" ]; then

  position=0
  for keystr in $@
  do
    
    # skip first parameter
    ((position++))
    if [ $position -eq 1 ]; then
      echo "# _cache.sh $@"
      continue
    fi

    # get redis value
    valuestr=$(redis-cli get ${keystr})

    # output key value in bash script compatible way
    echo "${keystr}=\"${valuestr}\""
  done

# import values from bash key-value store
elif [ "$1" = "import" ]; then

  # get parameter
  filename=$2

  # source values from given file (to be used for import later)
  source ${filename}

  # read file and go thru line by line
  n=1
  while read line; do

    # skip comment lines
    isComment=$(echo "${line}" | grep -c "^#")
    if [ ${isComment} -eq 1 ]; then
      continue
    fi

    # skip if not a value line
    isValueLine=$(echo "${line}" | grep -c "=")
    if [ ${isValueLine} -eq 0 ]; then
      continue
    fi

    # import key from line & value from source above (that way quotes are habdled correctly)
    keyValue=$(echo "$line" | cut -d "=" -f1)
    echo "# redis-cli set ${keyValue} ${!keyValue}"
    redis-cli set ${keyValue} "${!keyValue}" 1>/dev/null

    # also set the timestamp on import for each value
    timestamp=$(date +%s)
    redis-cli set ${keyValue}${META_LASTTOUCH_TS} "${timestamp}" 1>/dev/null

  done < $filename

# import values from bash key-value store
elif [ "$1" = "export" ]; then

  # get parameter
  keyfilter="${2}*"

  # go thru all keys by keyfilter
  keylist=$(redis-cli KEYS "${keyfilter}")
  readarray -t arr <<< "${keylist}"
  for key in "${arr[@]}";do

    # skip empty keys
    if [ "${key}" == "" ]; then
      continue
    fi

    # skip metadata keys
    isMeta=$(echo "${key}" | grep -c ":")
    if [ ${isMeta} -gt 0 ]; then
      continue
    fi

    # print out key/value
    value=$(redis-cli get "${key}")
    echo "${key}=\"${value}\""
  done

##################################
# COUNT
# count value up
##################################

# set
elif [ "$1" = "increment" ]; then

  # get parameters
  keystr=$2

  # check that key & value are given
  if [ "${keystr}" == "" ]; then
    echo "# Fail: missing parameter"
    exit 1
  fi
  # set in redis key value cache
  redis-cli incr ${keystr} 1>/dev/null

  # set in redis the timestamp
  timestamp=$(date +%s)
  redis-cli set ${keystr}${META_LASTTOUCH_TS} "${timestamp}" 1>/dev/null


##################################
# PUT/POLL TEMP CACHE
# key value with update metadata
##################################

# outdate (set outdated policy)
elif [ "$1" = "outdate" ]; then

  # get parameters
  keystr=$2
  outdatesecs=$3
  durationsecs=$4

  # sanatize parameters
  if [ "${outdatesecs}" != "-1" ]; then
    outdatesecs="${outdatesecs//[^0-9.]/}"
  fi

  # check that key & value are given
  if [ "${keystr}" == "" ] || [ "${outdatesecs}" == "" ]; then
    echo "# Fail: missing parameter"
    exit 1
  fi

    # add an expire flag if given
  additionalParams=""
  if [ "${durationsecs//[^0-9.]/}" != "" ]; then
    additionalParams="EX ${durationsecs//[^0-9.]/}"
  fi

  # store the seconds policy
  echo "# redis-cli set ${keystr}${META_OUTDATED_SECONDS} ${outdatesecs} ${additionalParams}"
  redis-cli set ${keystr}${META_OUTDATED_SECONDS} "${outdatesecs}" ${additionalParams}

  # set/renew exipire valid flag (important in case the key had before no expire)
  redis-cli set ${keystr}${META_VALID_FLAG} "1" EX ${outdatesecs} 1>/dev/null

# meta
elif [ "$1" = "meta" ]; then

  # get parameters
  keystr=$2
  default=$3

  # check that key & value are given
  if [ "${keystr}" == "" ]; then
    echo "# Fail: missing parameter"
    exit 1
  fi
  
  # get redis basic value 
  valuestr=$(redis-cli get ${keystr})
  echo "value=\"${valuestr}\""

  # get META_LASTTOUCH_TS
  lasttouch=$(redis-cli get ${keystr}${META_LASTTOUCH_TS})
  if [ "${lasttouch}" == "" ]; then
    echo "initiated=0"
    exit 0
  fi
  echo "initiated=1"
  echo "lasttouch=\"${lasttouch}\""

  # get META_OUTDATED_SECONDS
  outdatesecs=$(redis-cli get ${keystr}${META_OUTDATED_SECONDS})
  if [ "${outdatesecs}" == "" ]; then
    # default is -1 --> never outdate 
    outdatesecs="-1"
  fi
  echo "outdatesecs=\"${outdatesecs}\""

  # get META_VALID_FLAG
  valuestr=$(redis-cli get ${keystr}${META_VALID_FLAG})
  if [ "${valuestr}" == "" ] && [ "${outdatesecs}" != "-1" ]; then
    stillvalid=0
  else
    stillvalid=1
  fi
  echo "stillvalid=\"${stillvalid}\""

# valid
elif [ "$1" = "valid" ]; then

  position=0
  lasttouch_overall=""
  for keystr in $@
  do
    
    # skip first parameter
    ((position++))
    if [ $position -eq 1 ]; then
      echo "# _cache.sh $@"
      continue
    fi

    # get redis value
    valuestr=$(redis-cli get ${keystr}${META_VALID_FLAG})
    #echo "# ${keystr}${META_VALID_FLAG}=\"${valuestr}\""

    # break as soon one value is outdated
    if [ "${valuestr}" == "" ]; then
      # break if value is not protected from outdated  
      outdatesecs=$(redis-cli get ${keystr}${META_OUTDATED_SECONDS})
      #echo "# ${keystr}${META_OUTDATED_SECONDS}=\"${outdatesecs}\""
      if [ "${outdatesecs}" != "" ] && [ "${outdatesecs}" != "-1" ]; then
        echo "stillvalid=\"0\""
        exit 0
      fi
      # of "outdatesecs" has no value it can also be that key does not exist
      if [ "${outdatesecs}" == "" ]; then
        # break if key does not exist in cache (count as outdated)
        notexists=$(redis-cli exists ${keystr} | grep -c "0")
        if [ "${notexists}" == "1" ]; then
          #echo "# '${keystr}' key does not exist"
          echo "stillvalid=\"0\""
          exit 0
        fi
      fi

      # so value is still valid - check if its the oldest value in list
      lasttouch=$(redis-cli get ${keystr}${META_LASTTOUCH_TS})
      #echo "# lasttouch(${lasttouch})"
      if [ "${lasttouch}" != "" ]; then
        # find smallest lasttouch
        if [ "${lasttouch_overall}" == "" ] || [ ${lasttouch_overall} -gt ${lasttouch} ]; then
          lasttouch_overall="${lasttouch}"
        fi
      fi
      #echo "# lasttouch_overall(${lasttouch_overall})"

    fi

  done

  # of all were valid
  echo "stillvalid=\"1\""

  # calculate age in seconds of oldest entry
  if [ "${lasttouch_overall}" != "" ]; then
    timestamp=$(date +%s)
    age=$(($timestamp-$lasttouch_overall))
    echo "age=\"${age}\""
  fi

else
  echo "# FAIL: parameter not known - run with -h for help"
fi
