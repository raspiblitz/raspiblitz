#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz Error Handling"
  echo
  echo "blitz.error.sh [source-script-name] [fixed-short-code] [?detail-message] [?additional-debugdata] [?logfile]"
  echo
  exit 1
fi

###################
# ERROR HANDLING
###################

# get required parameters
script=$2
shortcode=$3

# check reqired parameters
if [ "${script}" == "" ]; then
  /home/admin/config.scripts/blitz.error.sh blitz.error.sh "error-missing-script" "missing any parameter" "$@"
  exit 1
fi
if [ "${shortcode}" == "" ]; then
  /home/admin/config.scripts/blitz.error.sh blitz.error.sh "error-missing-code" "script ${script} missing error code" "$@"
  exit 1
fi

# set error info in cache system state (for DISPLAY on lcd, report to webui, etc)
/home/admin/_cache.sh set state "error"
/home/admin/_cache.sh set message "${shortcode}"

# prepare log error report
dateStr=$(date)
errorReport="ERROR in ${script} --> ${shortcode} on ${dateStr}"

# get optional parameters & extend error report if given
detail=$4
debugdata=$5
if [ "${detail}" != "" ] || [ "${debugdata}" != "" ]; then
  errorReport="${errorReport}\nDETAIL --> ${detail}\nDEBUG --> ${debugdata}"
fi

# A) write error reports to /home/admin
timestampStr=$(date +%s)
filename="/home/admin/error-${script}-${timestampStr}.log"
echo "${errorReport}" > ${filename}
chown admin:admin ${filename}

# B) write error to std outs
>&2 echo "${errorReport} --> ${filename}"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "${errorReport}"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

# C) write error report to given logfile (optional) 
logfile=$6
if [ "${logfile}" !=  "" ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >> ${logFile}
  echo "${errorReport}" >> ${logFile}
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >> ${logFile}
fi

# on serial calls make sure that at least a second is between error reports
sleep 1