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
NODIALOG="$1"

# just in case a reboot is needed after test dialog
autoreboot=0

# run test if DNS is working (assuming that internet is working)
if [ "${DNSSERVER}" = "test" ]; then

  dnsworking=$(host w3c.org | grep -c "w3c.org has address")

  # when no dialog just return result of test and exit
  if [ "${NODIALOG}" = "nodialog" ]; then
    echo "dnsworking=${dnsworking}"
    exit 0
  fi

  # when dns not working ask in dialog to set a preset DNS
  whiptail --title ' DNS Test Failed ' --yes-button='Set DNS 1.1.1.1' --no-button='Ignore' --yesno "It looks like your DNS within local network is not working.\n
Do you want to set the fixed DNS 1.1.1.1 by cloudfare (they claim they provide privacy) for your RaspiBlitz and reboot?\n
  " 10 64
  if [ $? -eq 0 ]; then
    echo "SETTING 1.1.1.1"
    DNSSERVER="1.1.1.1"
    autoreboot=1
  else
    echo "Ignoring DNS-Test fail"
  fi
  exit 1

fi

echo "The DNS server you want to set is: ${DNSSERVER}"

# checking parameter
if [[ $DNSSERVER =~ ^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$ ]]; then
  echo "OK IPv6"
elif [[ $DNSSERVER =~ ^([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
  echo "OK IPv4"
else
  echo "FAIL - not an IPv4 or IPv6 address"
  exit 1
fi
echo ""

# setting DNS address
echo "Setting DNS server in /etc/dhcpcd.conf ..."
sudo sed -i "s/^static domain_name_servers=.*/static domain_name_servers=${DNSSERVER}/g" /etc/dhcpcd.conf
echo "OK"
echo ""

# make sure entry in raspiblitz.conf exists
source /mnt/hdd/raspiblitz.conf
if [ ${#dnsServer} -eq 0 ]; then
  echo "Adding value to /mnt/hdd/raspiblitz.conf"
  echo "dnsServer=${DNSSERVER}" >> /mnt/hdd/raspiblitz.conf
else
  echo "Updating value in /mnt/hdd/raspiblitz.conf"
  sudo sed -i "s/^dnsServer=.*/dnsServer=${DNSSERVER}/g" /mnt/hdd/raspiblitz.conf
fi
echo "OK"
echo ""

echo "DNS Server is set - reboot needed before active"
if [ ${autoreboot} -eq 1 ]; then
  sudo shutdown -r now
fi