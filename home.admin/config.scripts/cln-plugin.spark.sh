#!/bin/bash

#https://github.com/shesek/spark-wallet/releases
sparkVERSION="v0.3.0rc"

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install, remove, connect or get info about the Spark Wallet plugin for C-lightning"
  echo "version: $SPARKVERSION"
  echo "Usage:"
  echo "cln-plugin.spark-wallet.sh [on|off|menu|connect] [testnet|mainnet|signet]"
  echo
  exit 1
fi

# source <(/home/admin/config.scripts/network.aliases.sh getvars cln <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cln $2)

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}spark/hostname)
  toraddresstext="Hidden Service address for the Tor Browser (QRcode on LCD):\n$toraddress"
  if [ ${#toraddress} -eq 0 ];then
    toraddresstext="Activate Tor to access the web interface from outside of the local network."
  else
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
  fi
  fingerprint=$(openssl x509 -in /home/bitcoin/.lightning/spark-tls/cert.pem -fingerprint -noout | cut -d"=" -f2)

  whiptail --title "\
spark - $CHAIN" --msgbox "Open in your local web browser:
https://${localip}:${portprefix}9000\n
username: blitz
password: 'your Password B'\n
Accept the self-signed SSL certificate with the fingerprint:
${fingerprint}\n
${toraddresstext}
" 17 67
  
  /home/admin/config.scripts/blitz.display.sh hide

  echo "# please wait ..."
  exit 0
fi

# add default value to raspi config if needed
configEntry="${netprefix}spark"
configEntryExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "${configEntry}")
if [ "${configEntryExists}" == "0" ]; then
  echo "# adding default config entry for '${configEntry}'"
  sudo /bin/sh -c "echo '${configEntry}=off' >> /mnt/hdd/raspiblitz.conf"
else
  echo "# default config entry for '${configEntry}' exists"
fi

if [ $1 = connect ];then
  localip=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}spark/hostname)
  accesskey=$(sudo cat ${CLNCONF} | grep "^spark-keys=" | cut -d= -f2 | cut -d';' -f1) 
  url="https://${localip}:${portprefix}9000/"
  string="${url}?access-key=${accesskey}"

  /home/admin/config.scripts/blitz.display.sh qr "$string"
  clear
  echo "connection string (shown as a QRcode on the top and on the LCD):"
  echo "$string"
  qrencode -t ANSIUTF8 "${string}"
  echo
  echo "Tor address (shown as a QRcode below):"
  echo "${toraddress}"
  qrencode -t ANSIUTF8 "${toraddress}"
  echo
  echo "# Press enter to hide the QRcode from the LCD"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
fi

if [ $1 = on ];then

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on
  
  # create spark user
  sudo adduser --disabled-password --gecos "" spark
  
  # set up npm-global
  sudo -u spark mkdir /home/spark/.npm-global
  sudo -u spark npm config set prefix '/home/spark/.npm-global'
  sudo bash -c "echo 'PATH=$PATH:/home/spark/.npm-global/bin' >> /home/spark/.bashrc"
  
 echo "# Create data folder on the disk"
  # move old data if present
  sudo mv /home/spark/.spark /mnt/hdd/app-data/ 2>/dev/null
  echo "# make sure the data directory exists"
  sudo mkdir -p /mnt/hdd/app-data/.spark
  echo "# symlink"
  sudo rm -rf /home/spark/.spark # not a symlink.. delete it silently
  sudo ln -s /mnt/hdd/app-data/.spark/ /home/spark/.spark
  sudo chown spark:spark -R /mnt/hdd/app-data/.spark



  npm install -g spark-wallet
  
  if [ ! -f /home/bitcoin/cln-plugins-available/spark ];then
    sudo -u bitcoin mkdir /home/bitcoin/cln-plugins-available
    # download binary
    sudo -u bitcoin wget https://github.com/fiatjaf/spark/releases/download/${sparkVERSION}/spark_${DISTRO}\
    -O /home/bitcoin/cln-plugins-available/spark || exit 1
    # make executable
    sudo chmod +x /home/bitcoin/cln-plugins-available/spark
  fi

  if [ ! -L /home/bitcoin/${netprefix}cln-plugins-enabled/spark ];then
    sudo ln -s /home/bitcoin/cln-plugins-available/spark \
               /home/bitcoin/${netprefix}cln-plugins-enabled
  fi

  if [ ! -f /home/bitcoin/.lightning/spark-tls/key.pem ];then
    # create a self signed cert https://github.com/fiatjaf/spark#how-to-use
    /home/admin/config.scripts/internet.selfsignedcert.sh   
    # spark looks for specific filenames
    sudo -u bitcoin mkdir /home/bitcoin/.lightning/spark-tls
    sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.key \
        /home/bitcoin/.lightning/spark-tls/key.pem
    sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.cert \
        /home/bitcoin/.lightning/spark-tls/cert.pem
  fi

  ##########
  # Config #
  ##########
  if ! grep -Eq "^spark" ${CLNCONF};then
    echo "# Editing ${CLNCONF}"
    echo "# See: https://github.com/fiatjaf/spark#how-to-use"
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    # Spark wallet only allows alphanumeric characters
    masterkeythatcandoeverything=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
    secretaccesskeythatcanreadstuff=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
    verysecretkeythatcanpayinvoices=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
    keythatcanlistentoallevents=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
  echo "
spark-host=0.0.0.0
spark-port=${portprefix}9000
spark-tls-path=/home/bitcoin/.lightning/spark-tls
spark-login=blitz:$PASSWORD_B
spark-keys=${masterkeythatcandoeverything}; ${secretaccesskeythatcanreadstuff}: getinfo, listchannels, listnodes; ${verysecretkeythatcanpayinvoices}: pay; ${keythatcanlistentoallevents}: stream
" | sudo tee -a ${CLNCONF}
  else
    echo "# spark is already configured in ${CLNCONF}"
  fi

  echo "# Allowing port ${portprefix}9000 through the firewall"
  sudo ufw allow "${portprefix}9000" comment "${netprefix}spark"

  # hidden service to https://xx.onion
  /home/admin/config.scripts/internet.hiddenservice.sh ${netprefix}spark 443 ${portprefix}9000

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}spark=.*/${netprefix}spark=on/g" /mnt/hdd/raspiblitz.conf

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# Restart the ${netprefix}lightningd.service to activate spark"
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo "# spark was installed"
  echo "# Monitor with:"
  echo "sudo journalctl | grep spark | tail -n5"
  echo "sudo tail -n 100 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log | grep spark"
  
fi

if [ $1 = off ];then
  # delete symlink
  sudo rm -rf /home/bitcoin/${netprefix}cln-plugins-enabled/spark
  
  echo "# Editing ${CLNCONF}"
  sudo sed -i "/^spark/d" ${CLNCONF}

  echo "# Restart the ${netprefix}lightningd.service to deactivate spark"
  sudo systemctl restart ${netprefix}lightningd

  echo "# Deny port ${portprefix}9000 through the firewall"
  sudo ufw deny "${portprefix}9000"
  
  /home/admin/config.scripts/internet.hiddenservice.sh off ${netprefix}spark

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin"
    sudo rm -rf /home/bitcoin/cln-plugins-available/spark
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}spark=.*/${netprefix}spark=off/g" /mnt/hdd/raspiblitz.conf
  echo "# spark was uninstalled"

fi
