#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to set a the DNS server that should be used"
 echo "internet.dns.sh [DNS-SERVER|test]"
 exit 1
fi

# 1. parameter
DNSSERVER="$1"

# 2. parameter
NODIALOG="$2"

# just if auto reboot is needed after dialog
autoreboot=0 

# run test if DNS is working (assuming that internet is working)
if [ "${DNSSERVER}" = "test" ]; then

  dnsworking=$(host w3c.org | grep -c "w3c.org has address")

  # when no dialog just return result of test and exit
  if [ "${NODIALOG}" = "nodialog" ] || [ ${dnsworking} -eq 1 ]; then
    echo "dnsworking=${dnsworking}"
    exit 0
  fi

  # dns is not working --> ask in dialog to set a preset DNS
  whiptail --title ' DNS Test Failed ' --yes-button='Set DNS 1.1.1.1' --no-button='Ignore' --yesno "It looks like your DNS within local network is not working.\n
Do you want to set the fixed DNS 1.1.1.1 by Cloudflare (they claim they provide privacy) for your RaspiBlitz and reboot?\n
" 10 64
  if [ $? -eq 0 ]; then
    echo "# SETTING 1.1.1.1"
    DNSSERVER="1.1.1.1"
    autoreboot=1
  else
    echo "# Ignoring DNS-Test fail"
  fi
  
fi

echo "The DNS server you want to set is: ${DNSSERVER}"

# checking parameter
if [[ $DNSSERVER =~ ^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$ ]]; then
  echo "# OK IPv6"
elif [[ $DNSSERVER =~ ^([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
  echo "# OK IPv4"
else
  echo "error='not an IPv4 or IPv6 address'"
  exit 1
fi
echo ""

dnsconfFile="/etc/dhcpcd.conf"
isUbuntu=$(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu')
if [ ${isUbuntu} -gt 0 ]; then
  echo "# adapting dhcpd.conf path for ubuntu"
  dnsconfFile="/etc/dhcp/dhcpd.conf"
fi

# setting DNS address
echo "# Setting DNS server in /etc/dhcpcd.conf ..."
sudo sed -i "s/^static domain_name_servers=.*/static domain_name_servers=${DNSSERVER}/g" /etc/dhcpcd.conf
echo "# OK"
echo ""

# make sure entry in raspiblitz.conf exists
/home/admin/config.scripts/blitz.conf.sh set dnsServer "${DNSSERVER}"
echo "# OK"
echo ""

echo "# DNS Server is set - needs reboot to get active"
if [ ${autoreboot} -eq 1 ]; then
  sudo shutdown -r now
fi