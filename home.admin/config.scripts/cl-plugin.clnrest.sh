#!/bin/bash

# help
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "clnrest configuration and connection script"
  echo "cl-plugin.clnrest.sh on <mainnet|testnet|signet>"
  echo "cl-plugin.clnrest.sh connect <mainnet|testnet|signet> [?key-value]"
  exit 1
fi

# check and load raspiblitz config to know which network is running
source /mnt/hdd/raspiblitz.conf

echo "# Running: 'cl-plugin.clnrest.sh $*'"

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

if [ "$1" = on ]; then
  clnNeedsRestart=0
  if ! grep "^clnrest-port=${portprefix}7378" "${CLCONF}" >/dev/null; then
    echo "# setting clnrest-port=${portprefix}7378"
    sudo /home/admin/config.scripts/blitz.conf.sh set "clnrest-port" "${portprefix}7378" "${CLCONF}" "noquotes"
    clnNeedsRestart=1
  fi
  if ! grep "^clnrest-host=0.0.0.0" "${CLCONF}" >/dev/null; then
    echo "# setting clnrest-host=0.0.0.0"
    sudo /home/admin/config.scripts/blitz.conf.sh set "clnrest-host" "0.0.0.0" "${CLCONF}" "noquotes"
    clnNeedsRestart=1
  fi
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ] && [ ${clnNeedsRestart} -eq 1 ]; then
    echo "# OK the system is ready so restarting ${netprefix}lightningd to activate the clnrest plugin"
    sudo systemctl restart ${netprefix}lightningd
  fi
fi

if [ "$1" = connect ]; then

  echo "# Allowing port ${portprefix}7378 through the firewall"
  sudo ufw allow "${portprefix}7378" comment "${netprefix}clnrest" 1>/dev/null
  localip=$(hostname -I | awk '{print $1}')
  # hidden service to https://xx.onion
  /home/admin/config.scripts/tor.onion-service.sh ${netprefix}clnrest 443 ${portprefix}7378 1>/dev/null

  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}clnrest/hostname)
  rune=$($lightningcli_alias createrune | jq -r .rune)
  url="https://${localip}:${portprefix}7378/"
  # clnrest://http://your_hidden_service.onion:your_port?&rune=your_rune
  clnrestlan="clnrest://${localip}:${portprefix}7378?&rune=${rune}"
  clnresttor="clnrest://${toraddress}:443?&rune=${rune}"

  if [ "$3" == "key-value" ]; then
    echo "toraddress='${toraddress}:443'"
    echo "local='${url}'"
    echo "rune='${rune}'"
    echo "connectstring='${clnresttor}'"
    exit 0
  fi

  # deactivated
  # shellcheck disable=SC2317
  function showStepByStepQR() {
    clear
    echo
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    echo "The Tor address is shown as a QRcode below and on the LCD"
    echo "Scan it to your phone with a QR scanner app and paste it to: 'Host'"
    echo
    echo "Host: ${toraddress}"
    echo "REST Port: 443"
    echo
    qrencode -t ANSIUTF8 "${toraddress}"
    echo
    echo
    echo "Alternatively to connect through the LAN the address is:"
    echo "https://${localip}"
    echo "REST Port: ${portprefix}7378"
    echo
    echo "# Press enter to continue to show the Rune"
    read -r
    sudo /home/admin/config.scripts/blitz.display.sh hide
    sudo /home/admin/config.scripts/blitz.display.sh qr "${rune}"
    clear
    echo
    echo "The Rune is shown as a QRcode below and on the LCD"
    echo "Scan it to your phone with a QR scanner app and paste it to: 'Rune'"
    echo
    echo "Rune: ${rune}"
    echo
    qrencode -t ANSIUTF8 "${rune}"
    echo
    echo "# Press enter to hide the QRcode from the LCD"
    read -r
    sudo /home/admin/config.scripts/blitz.display.sh hide
    exit 0
  }

  function showClRestQr() {
    # see the format at https://github.com/ZeusLN/zeus/blob/master/utils/ConnectionFormatUtils.ts
    # clnrest://http://your_hidden_service.onion:your_port?&rune=your_rune
    clear
    echo
    sudo /home/admin/config.scripts/blitz.display.sh qr "${clnresttor}"
    echo "The string to connect over Tor is shown as a QRcode below and on the LCD"
    echo "Scan it to Zeus using the CLNrest option"
    echo
    echo "CLNrest connection string:"
    echo "${clnresttor}"
    echo
    qrencode -t ANSIUTF8 "${clnresttor}"
    echo
    echo "# Press enter to show the string to connect over LAN"
    read -r
    sudo /home/admin/config.scripts/blitz.display.sh hide
    sudo /home/admin/config.scripts/blitz.display.sh qr "${clnrestlan}"
    clear
    echo
    echo "The string to connect over the local the network is shown as a QRcode below and on the LCD"
    echo "Scan it to Zeus using the CLNrest option"
    echo "This will only work if your node is connected to the same network"
    echo "To connect reemotely consider using a VPN like ZeroTier or Tailscale"
    echo
    echo "CLNrest connection string:"
    echo "${clnrestlan}"
    echo
    qrencode -t ANSIUTF8 "${clnrestlan}"
    echo
    echo "# Press enter to hide the QRcode from the LCD"
    read -r
    sudo /home/admin/config.scripts/blitz.display.sh hide
    exit 0
  }

  showClRestQr

fi
