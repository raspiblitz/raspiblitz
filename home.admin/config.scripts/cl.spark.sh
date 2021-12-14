#!/bin/bash

#https://github.com/shesek/spark-wallet/releases
SPARKVERSION="v0.3.0rc"

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install, remove or get info about the Spark Wallet for C-lightning"
  echo "version: $SPARKVERSION"
  echo "Usage:"
  echo "cl.spark.sh [on|off|menu] <testnet|mainnet|signet> "
  echo
  exit 1
fi

# source <(/home/admin/config.scripts/network.aliases.sh getvars cl <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)
systemdService="${netprefix}spark"

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}spark-wallet/hostname)
  toraddresstext="Hidden Service address for the Tor Browser (QRcode on LCD):\n$toraddress"
  if [ ${#toraddress} -eq 0 ];then
    toraddresstext="Activate Tor to access the web interface from outside of the local network."
  else
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
  fi
  fingerprint=$(openssl x509 -in /home/bitcoin/.lightning/spark-tls/cert.pem -fingerprint -noout | cut -d"=" -f2)

  whiptail --title "\
spark - $CHAIN" --msgbox "Open in your local web browser:
https://${localip}:${portprefix}8000\n
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

if [ $1 = on ];then

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # set up npm-global
  sudo -u bitcoin mkdir /home/bitcoin/.npm-global
  sudo -u bitcoin npm config set prefix '/home/bitcoin/.npm-global'
  sudo bash -c "echo 'PATH=$PATH:/home/bitcoin/.npm-global/bin' >> /home/bitcoin/.bashrc"

  echo "# Create data folder on the disk"
  echo "# make sure the data directory exists"
  sudo mkdir -p /mnt/hdd/app-data/.spark-wallet
  echo "# symlink"
  sudo rm -rf /home/bitcoin/.spark-wallet # not a symlink.. delete it silently
  sudo ln -s /mnt/hdd/app-data/.spark-wallet/ /home/bitcoin/.spark-wallet
  sudo chown bitcoin:bitcoin -R /mnt/hdd/app-data/.spark-wallet

  cd /home/bitcoin || exit 1
  sudo -u bitcoin git clone https://github.com/shesek/spark-wallet
  cd spark-wallet || exit 1
  sudo -u bitcoin git reset --hard ${SPARKVERSION} || exit 1
  sudo -u bitcoin npm install @babel/cli
  sudo -u bitcoin npm run dist:npm || exit 1

  if [ ! -f /home/bitcoin/.spark-wallet/tls/key.pem ];then
    # create a self signed cert https://github.com/fiatjaf/spark#how-to-use
    /home/admin/config.scripts/internet.selfsignedcert.sh
    # spark looks for specific filenames
    sudo -u bitcoin mkdir -p /home/bitcoin/.spark-wallet/tls/
    sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.key \
        /home/bitcoin/.spark-wallet/tls/key.pem
    sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.cert \
        /home/bitcoin/.spark-wallet/tls/cert.pem
  fi

  ##########
  # Config #
  ##########
  if [ -f /home/bitcoin/.spark-wallet/${netprefix}config ];then
    echo "# ${netprefix}spark config is already present"
  else
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
echo "\
login=blitz:${PASSWORD_B}
host=0.0.0.0
proxy=socks5h://127.0.0.1:9050
tls-path=/home/bitcoin/.lightning/spark-tls
onion
"   | sudo -u bitcoin tee /home/bitcoin/.spark-wallet/${netprefix}config
  fi

  #################
  # SYSTEMD SERVICE
  #################
  # https://raw.githubusercontent.com/shesek/spark-wallet/master/scripts/spark-wallet.service
  echo "# Create Systemd Service: ${systemdService}.service"
  echo "
# Systemd unit for ${systemdService}

[Unit]
Description=${systemdService} Lightning Wallet
Wants=${netprefix}lightningd.service
After=${netprefix}lightningd.service

[Service]
WorkingDirectory=/home/bitcoin/spark-wallet
ExecStart=/home/bitcoin/spark-wallet/dist/cli.js\
 --ln-path /home/bitcoin/.lightning/${CLNETWORK}  --port 8000\
 --config /home/bitcoin/.spark-wallet/config
User=bitcoin
Restart=on-failure
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${systemdService}.service
  sudo chown root:root /etc/systemd/system/${systemdService}.service

  echo "# Allowing port ${portprefix}8000 through the firewall"
  sudo ufw allow "${portprefix}8000" comment "${netprefix}spark-wallet"

  /home/admin/config.scripts/tor.onion-service.sh ${netprefix}spark-wallet 443 ${portprefix}8000

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}spark "on"
  
  sudo systemctl enable ${systemdService}
  sudo systemctl start ${systemdService}
  echo "# OK - the ${systemdService}.service is now enabled & started"
  echo "# Monitor with: sudo journalctl -f -u ${systemdService}"
  exit 0

fi

if [ $1 = off ];then

  sudo systemctl stop ${systemdService} 2>/dev/null
  sudo systemctl disable ${systemdService} 2>/dev/null

  /home/admin/config.scripts/tor.onion-service.sh off ${netprefix}spark-wallet

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete install directory"
    sudo rm -rf /home/bitcoin/spark-wallet
  fi
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}spark "off"
  echo "# ${netprefix}spark was uninstalled"
fi