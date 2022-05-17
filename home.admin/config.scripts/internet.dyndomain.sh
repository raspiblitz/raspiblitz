#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "set a dynamic domain like freeDNS"
 echo "internet.dyndomain.sh status"
 echo "internet.dyndomain.sh on --> interactive setup"
 echo "internet.dyndomain.sh [domainName] [?updateURL]"
 echo "internet.dyndomain.sh update"
 echo "internet.dyndomain.sh off"
 exit 1
fi

## get system configs
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# GETTING STATUS
if [ "$1" = "status" ]; then
  if [ ${#dynDomain} -gt 0 ]; then
    echo "active=1"
    echo "dynDomain='${dynDomain}'"
    echo "dynUpdateUrl='${dynUpdateUrl}'"
    echo "# checking if dyndomain dns resolving is matching public IP"
    dynIPv4=$(host -W 8 ${dynDomain} | grep 'has address' | cut -d ' ' -f 4)
    dynIPv6=$(host -W 8 ${dynDomain} | grep 'has IPv6 address' | cut -d ' ' -f 5)
    source <(/home/admin/config.scripts/internet.sh status global)
    echo "publicip='${publicip}'"
    echo "dynipv4='${dynIPv4}'"
    echo "dynipv6='${dynIPv6}'"
    if [ ${#dynIPv4} -eq 0 ] && [ ${#dynIPv6} -eq 0 ]; then
      echo "exists=0"
    else
      echo "exists=1"
    fi
    if [ "${publicip}" == "${dynIPv4}" ] || [ "${publicip}" == "${dynIPv6}" ]; then
      echo "uptodate=1"
    else
      echo "uptodate=0"
    fi
  else
    echo "active=0"
  fi
  exit
fi

# FUNCTION updating dyndomain (if update URL is set)
updateDynDNS()
{
  if [ ${#dynUpdateUrl} -gt 0 ]; then
    echo "# calling: ${dynUpdateUrl}"
    echo "# to update domain: ${dynDomain}"
    curl -s --connect-timeout 6 ${dynUpdateUrl} 1>&2
  else
    echo "# dynUpdateUrl not set - not updating"
  fi 
}

# UPDATE
if [ "$1" = "update" ]; then
  echo "# internet.dyndomain.sh update"
  if [ ${#dynUpdateUrl} -eq 0 ]; then
    echo "error='no url set for dynamic domain update'"
    exit 1
  fi
  updateDynDNS
  exit
fi

# ON
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  dynDomain=''
  dynUpdateUrl=''

  # when additional parameters are given
  if [ $# > 1 ]; then

    # 2. parameter is dyndomain (required)
    dynDomain=$2

    # 3. parameter is the update url (optional - could be that router is doing the update)
    if [ $# > 2 ]; then
      dynUpdateUrl=$3
    fi
  fi

  # if no parameters --> ask for it interactive
  if [ ${#dynDomain} -eq 0 ]; then

    dynDomain=$(whiptail --inputbox "\nEnter the Dynamic Domain Name:\n(example: freedns.afraid.org)" 10 52 --title "Dynamic Domain" --backtitle "DynamicDNS" 3>&1 1>&2 2>&3)
    # check if domain was entered
    if [ ${#dynDomain} -eq 0 ]; then
      whiptail --title " Error " --msgbox "\n  Domain cannot be empty." 8 30
      exit 1
    fi
    # check if domain exists
    notFound=$(host -W 16 ${dynDomain} | grep -c 'not found')
    if [ ${notFound} -eq 1 ]; then
      whiptail --title " Error " --msgbox "\n  Domain ${dynDomain} not found.\n  Make sure it exists before setup. " 9 50
      exit 1
    fi

    dynUpdateUrl=$(whiptail --inputbox "\nPublic IP Update URL:\n(freedns.afraid.org use 'DirectURL')" 10 52 --title "Update URL (optional)" --backtitle "DynamicDNS" 3>&1 1>&2 2>&3)
  fi

  # check if any input to set
  if [ ${#dynDomain} -eq 0 ]; then
    echo "error='missing parameter'"
    exit 1
  fi

  echo "# switching the DynamicDNS ON"
  echo "# dynDomain(${dynDomain})"
  echo "# dynUpdateUrl(${dynUpdateUrl})"

  # setting dynUpdateUrl is a bit complicated because value can contain chars that break sed replacement
  # so first remove dynUpdateUrl from config and then add fresh as new line at the end

  # remove line & write fresh
  /home/admin/config.scripts/blitz.conf.sh set dynDomain "${dynDomain}"

  # remove line & write fresh
  /home/admin/config.scripts/blitz.conf.sh set dynUpdateUrl "${dynUpdateUrl}"

  # make sure dyndomain is added to lnd config file (just edits the config file)
  sudo /home/admin/config.scripts/lnd.tlscert.sh domain-add ${dynDomain}

  # update the IP of the dyndomain once (if updateurl is set)
  updateDynDNS

  # just if lnd is running make sure to create a new TLS cert
  lndRunning=$(systemctl is-active lnd | grep -c "^active")
  if [ ${lndRunning} -eq 1 ]; then
    echo "# lnd service is running - trigger TLS refresh"
    sudo /home/admin/config.scripts/lnd.tlscert.sh refresh
  else
    # this is important during update/recovery to ensure non-blocking run
    echo "# lnd service is not running - skipping TLS recreation"
  fi

  echo "# DynamicDNS is now ON"
  exit
fi

# OFF
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# switching DynamicDNS OFF"

  # removing values in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh delete dynUpdateUrl
  /home/admin/config.scripts/blitz.conf.sh delete dynDomain

  # lnd.conf: remove domain tls entries
  sudo /home/admin/config.scripts/lnd.tlscert.sh domain-remove ALL

  # just if lnd is running make sure to create a new TLS cert
  lndRunning=$(systemctl is-active lnd | grep -c "^active")
  if [ ${lndRunning} -eq 1 ]; then
    echo "# lnd service is running - trigger TLS refresh"
    sudo /home/admin/config.scripts/lnd.tlscert.sh refresh
  else
    echo "# lnd service is not running - skipping TLS recreation"
  fi

  echo "# DynamicDNS is now OFF"
  exit
fi

# if not matching and exiting on one of the commands above
echo "error='unknown parameter'"
exit 1
