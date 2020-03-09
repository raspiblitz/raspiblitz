#!/bin/bash

# https://github.com/cryptoadvance/specter-desktop  
# ~/.config/btc-rpc-explorer.env
# https://github.com/janoside/btc-rpc-explorer/blob/master/.env-sample

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch cryptoadvance specter on or off"
 echo "bonus.cryptoadvance-specter.sh [status|on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.cryptoadvance-specter.sh status)

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=https://$(sudo cat /mnt/hdd/tor/cryptoadvance-specter/hostname 2>/dev/null)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " Cryptoadvance Specter " --msgbox "Open the following URL in your local web browser:
https://${localip}:25441
You have to accept the self-signed-certificate.
Login with the Pin being Password B. If you have connected to a different Bitcoin RPC Endpoint, the Pin is the configured RPCPassword.
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}\n
" 16 70
    /home/admin/config.scripts/blitz.lcd.sh hide
  else

    # IP + Domain
    whiptail --title " Cryptoadvance Specter " --msgbox "Open the following URL in your local web browser:
https://${localip}:25441
You have to accept the self-signed-certificate.
Login with the Pin being Password B. If you have connected to a different Bitcoin RPC Endpoint, the Pin is the configured RPCPassword.\n
Activate TOR to access the web block explorer from outside your local network.
Unfortunately the camera is currently not usable via Tor, though.
" 12 54
  fi

  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^specter=" /mnt/hdd/raspiblitz.conf; then
  echo "specter=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${specter}" = "on" ]; then
    echo "configured=1"

    # check for error
    isDead=$(sudo systemctl status cryptoadvance-specter | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "configured=0"
  fi
  exit 0
fi

# stop service
echo "making sure services are not running"
sudo systemctl stop cryptoadvance-specter 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL Cryptoadvance Specter ***"

  isInstalled=$(sudo ls /etc/systemd/system/cryptoadvance-specter.service 2>/dev/null | grep -c 'cryptoadvance-specter.service')
  if [ ${isInstalled} -eq 0 ]; then

    echo "*** Enable wallets in Bitcoin Core ***"
    sudo sed -i "s/^disablewallet=.*/disablewallet=0/g" /home/bitcoin/.bitcoin/bitcoin.conf
    sudo service bitcoind stop
    sudo service bitcoind start

    echo "*** Installing prerequisites ***"
    sudo apt install libusb-1.0.0-dev libudev-dev virtualenv
    sudo -u bitcoin pip3 install --upgrade cryptoadvance.specter

    # activating Authentication here ...
    echo "*** creating App-config ***"
    cat > /home/admin/config.json <<EOF
{
	"auth":"rpcpasswordaspin"
}
EOF
    sudo mkdir -p /home/bitcoin/.specter
    sudo mv /home/admin/config.json /home/bitcoin/.specter/config.json
    sudo chown -R bitcoin:bitcoin /home/bitcoin/.specter

    echo "*** creating a virtualenv ***"
    sudo -u bitcoin virtualenv --python=python3 /home/bitcoin/.specter/.env

    echo "*** installing specter ***"
    sudo -u bitcoin /home/bitcoin/.specter/.env/bin/python3 -m pip install --upgrade cryptoadvance.specter
    
    
    # Creating self-signed-certificate
    # Mandatory as the camera doesn't work without https
    echo "*** Creating self-signed certificate ***"
   openssl req -x509 -newkey rsa:4096 -nodes -out /tmp/cert.pem -keyout /tmp/key.pem -days 365 -subj "/C=US/ST=Nooneknows/L=Springfield/O=Dis/CN=www.fakeurl.com"
    sudo mv /tmp/cert.pem /home/bitcoin/.specter
    sudo chown -R bitcoin:bitcoin /home/bitcoin/.specter/cert.pem
    sudo mv /tmp/key.pem /home/bitcoin/.specter
    sudo chown -R bitcoin:bitcoin /home/bitcoin/.specter/key.pem

    # open firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow 25441 comment 'cryptoadvance-specter'
    sudo ufw --force enable
    echo ""

    # install service
    echo "*** Install cryptoadvance-specter systemd service ***"
    cat > /home/admin/cryptoadvance-specter.service <<EOF
# systemd unit for Cryptoadvance Specter

[Unit]
Description=cryptoadvance-specter
Wants=${network}d.service
After=${network}d.service

[Service]
ExecStart=/home/bitcoin/.specter/.env/bin/python3 -m cryptoadvance.specter server --host 0.0.0.0 --cert=/home/bitcoin/.specter/cert.pem --key=/home/bitcoin/.specter/key.pem
User=bitcoin
Environment=PATH=/home/bitcoin/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/sbin:/bin
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /home/admin/cryptoadvance-specter.service /etc/systemd/system/cryptoadvance-specter.service 
    sudo systemctl enable cryptoadvance-specter
    sudo systemctl start cryptoadvance-specter
    echo "OK - the cryptoadvance-specter service is now enabled and started"

  else 
    echo "cryptoadvance-specter already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^specter=.*/specter=on/g" /mnt/hdd/raspiblitz.conf
  
  ## Enable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  # see /home/admin/config.scripts/bonus.electrsexplorer.sh
  # run every 10 min by _background.sh

  # Hidden Service for BTC-RPC-explorer if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # correct old Hidden Service with port
    sudo sed -i "s/^HiddenServicePort 25441 127.0.0.1:25441/HiddenServicePort 80 127.0.0.1:25441/g" /etc/tor/torrc
    /home/admin/config.scripts/internet.hiddenservice.sh cryptoadvance-specter 80 25441
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^specter=.*/specter=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/cryptoadvance-specter.service 2>/dev/null | grep -c 'cryptoadvance-specter.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING Cryptoadvance Specter ***"
    sudo systemctl stop cryptoadvance-specter
    sudo systemctl disable cryptoadvance-specter
    sudo rm /etc/systemd/system/cryptoadvance-specter.service

    echo "*** Removing wallets in core ***"
    bitcoin-cli listwallets | jq -r .[] | tail -n +2
    for i in $(bitcoin-cli listwallets | jq -r .[] | tail -n +2) 
    do  
	name=$(echo $i | cut -d"/" -f2)
       	bitcoin-cli unloadwallet specter/$name 
    done
    sudo rm -rf /home/bitcoin/.bitcoin/specter

    echo "*** Removing /home/bitcoin/.specter ***"
    sudo rm -rf /home/bitcoin/.specter

    echo "OK Cryptoadvance Specter removed."
  else 
    echo "Cryptoadvance Specter is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
