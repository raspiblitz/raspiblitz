#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to set a the DNS server that should be used"
  echo "internet.dns.sh [DNS-SERVER|test|off]"
  exit 1
fi

# 1. parameter
DNSSERVER="$1"

# 2. parameter
NODIALOG="$2"

# just if auto reboot is needed after dialog
autoreboot=0

if [ "${DNSSERVER}" = "off" ]; then
  # setting DNS address
  echo "# turning static DNS off"
  sudo /home/admin/config.scripts/blitz.conf.sh delete "static domain_name_servers" /etc/dhcpcd.conf
  /home/admin/config.scripts/blitz.conf.sh delete dnsServer
  echo "# OK - needs reboot to activate"
  echo
  exit 0
fi

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
    # for IPv6: DNSSERVER="2606:4700:4700::1111"
    autoreboot=1
  else
    echo "# Ignoring DNS-Test fail"
  fi

fi

echo "The DNS server you want to set is: ${DNSSERVER}"

# checking parameter
if [[ $DNSSERVER =~ ^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$ ]]; then
  echo "# OK ipv6"
  DNSTYPE=ipv6
elif [[ $DNSSERVER =~ ^([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
  echo "# OK ipv4"
  DNSTYPE=ipv4
else
  echo "error='not an IPv4 or IPv6 address'"
  exit 1
fi
echo

# check if /etc/dhcpcd.conf or /etc/dhcp/dhcpd.conf exists

if sudo test -f /etc/dhcpcd.conf || sudo test -f /etc/dhcp/dhcpd.conf; then
  dnsconfFile="/etc/dhcpcd.conf"
  if grep Ubuntu /etc/os-release; then
    echo "# adapting dhcpd.conf path for ubuntu"
    dnsconfFile="/etc/dhcp/dhcpd.conf"
  fi

  # setting DNS address
  echo "# Setting DNS server ${DNSSERVER} in ${dnsconfFile} ..."
  sudo /home/admin/config.scripts/blitz.conf.sh set "static domain_name_servers" "${DNSSERVER}" "${dnsconfFile}"
  echo "# OK"
  echo
else
  # Get a list of all active Ethernet and Wi-Fi connections
  ACTIVE_CONNECTIONS=$(nmcli -t -f TYPE,NAME con show --active | grep -E 'ethernet|wireless' | cut -d: -f2)

  for CON in $ACTIVE_CONNECTIONS; do
    if [[ -n "$CON" && "$CON" != "-" ]]; then
      echo "Setting ${DNSTYPE} DNS $DNSSERVER for $CON..."
      # Set the DNS servers for this connection
      if sudo nmcli con mod "$CON" $DNSTYPE.dns "$DNSSERVER" &&
        sudo nmcli con mod "$CON" $DNSTYPE.ignore-auto-dns yes &&
        sudo nmcli con mod "$CON" $DNSTYPE.method auto; then
        # if set successfully restart the connection to apply changes
        sudo nmcli con down "$CON"
        sudo nmcli con up "$CON"
        echo "${DNSTYPE} DNS set for $CON."
      else
        echo "Error: Failed to set DNS for $CON. It might not be an active connection."
      fi
    else
      echo "Skipping invalid or inactive connection name: $CON"
    fi
  done

  echo "DNS settings updated for all active Ethernet and Wi-Fi connections."
  # show the DNS setting
  nmcli dev show  | grep DNS
fi

# make sure entry in raspiblitz.conf exists
/home/admin/config.scripts/blitz.conf.sh set dnsServer "${DNSSERVER}"
echo "# OK"
echo ""

echo "# DNS Server is set - needs reboot to get active"
if [ ${autoreboot} -eq 1 ]; then
  sudo shutdown -r now
fi
