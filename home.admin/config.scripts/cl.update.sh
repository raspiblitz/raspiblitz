#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Interim optional Core Lightning updates between RaspiBlitz releases."
  echo "cl.update.sh [info|verified|reckless]"
  echo "info -> get actual state and possible actions"
  echo "verified -> only do recommended updates by RaspiBlitz team"
  echo "  binary will be checked by signature and checksum"
  echo "reckless -> if you just want to update to the latest release"
  echo "  published on Core Lightning GitHub releases without any"
  echo "  testing or security checks."
  echo
  exit 1
fi

# 1. parameter [info|verified|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM
# comment will be shown as "BEWARE Info" when option is choosen (can be multiple lines)
clUpdateVersion="" # example: v23.02.2 # keep empty if no newer version as sd card build is available
clUpdateComment="Please keep in mind that downgrading afterwards is not tested. Also not all additional apps are fully tested with the this update - but it looked good on first tests."

# GATHER DATA

# installed Core Lightning version
clInstalledVersion=$(sudo -u bitcoin lightningd --version) # example output: v23.02.2
clInstalledVersionMajor=$(echo "${clInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f1)
clInstalledVersionMain=$(echo "${clInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f2)
clInstalledVersionMinor=$(echo "${clInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f3)

# test if the installed version already the verified/recommended update version
clUpdateInstalled=$(echo "${clInstalledVersion}" | grep -c "${clUpdateVersion}")

# get latest release from Core Lightning GitHub releases without release candidates
clLatestVersion=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/ElementsProject/lightning/releases | jq -r '.[].tag_name' | grep -v "rc" | head -n1)
# example output: v23.05

# INFO
if [ "${mode}" = "info" ]; then

  echo "# basic data"
  echo "clInstalledVersion='${clInstalledVersion}'"
  echo "clInstalledVersionMajor='${clInstalledVersionMajor}'"
  echo "clInstalledVersionMain='${clInstalledVersionMain}'"
  echo "clInstalledVersionMinor='${clInstalledVersionMinor}'"

  echo "# the verified/recommended update option"
  echo "clUpdateInstalled='${clUpdateInstalled}'"
  echo "clUpdateVersion='${clUpdateVersion}'"
  echo "clUpdateComment='${clUpdateComment}'"

  echo "# reckless update option (latest Core Lightning release from GitHub)"
  echo "clLatestVersion='${clLatestVersion}'"

  exit 1
fi

# verified
if [ "${mode}" = "verified" ]; then

  echo "# cl.update.sh verified"

  # check for optional second parameter: forced update version
  # --> only does the verified update if its the given version
  # this is needed for recovery/update.
  fixedUpdateVersion="$2"
  if [ ${#fixedUpdateVersion} -gt 0 ]; then
    echo "# checking for fixed version update: askedFor(${fixedUpdateVersion}) available(${clUpdateVersion})"
    if [ "${fixedUpdateVersion}" != "${clUpdateVersion}" ]; then
      echo "warn='required update version does not match'"
      echo "# this is normal when the recovery script of a new RaspiBlitz version checks for an old update - just ignore"
      /home/admin/config.scripts/blitz.conf.sh delete clInterimsUpdate
      exit 1
    else
      echo "# OK - update version is matching"
    fi
  fi

  if [ ${#clUpdateVersion} -gt 0 ]; then
    # only update if the clUpdateVersion is different from the installed
    if [ "${clInstalledVersion}" = "${clUpdateVersion}" ]; then
      echo "# clInstalledVersion = clUpdateVersion (${clUpdateVersion})"
      echo "# There is no need to update again."
    else
      /home/admin/config.scripts/cl.install.sh update ${clUpdateVersion}
    fi
  else
    /home/admin/config.scripts/cl.install.sh on
  fi

  # note: install will be done the same as reckless further down
  clInterimsUpdateNew="${clUpdateVersion}"

fi

# RECKLESS
# this mode is just for people running test and development nodes - its not recommended
# for production nodes. In a update/recovery scenario it will not install a fixed version
# it will always pick the latest release from the github
if [ "${mode}" = "reckless" ]; then

  echo "# cl.update.sh reckless"

  # only update if the latest release is different from the installed
  if [ "${clInstalledVersion}" = "${clLatestVersion}" ]; then
    echo "# clInstalledVersion = clLatestVersion (${clLatestVersion})"
    echo "# There is no need to update again."
    clInterimsUpdateNew="${clLatestVersion}"
  else
    /home/admin/config.scripts/cl.install.sh update ${clLatestVersion}
    clInterimsUpdateNew="reckless"
  fi
fi

# JOINED INSTALL (verified & RECKLESS)
if [ "${mode}" = "verified" ] || [ "${mode}" = "reckless" ]; then

  echo "# flag update in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set clInterimsUpdate "${clInterimsUpdateNew}"

  echo "# OK Core Lightning is installed"
  echo "# NOTE: RaspiBlitz may need to reboot now"
  exit 1

else

  echo "error='parameter not known'"
  exit 1

fi
