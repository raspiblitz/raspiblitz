#!/bin/bash

# https://github.com/arcbtc/lnbits

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch LNBits on or off"
 echo "bonus.lnbits.sh [on|off|status|menu|write-macaroons]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.lnbits.sh status)

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/lnbits/hostname 2>/dev/null)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " LNBits " --msgbox "Open the following URL in your local web browser:
http://${localip}:5000\n
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}
" 11 67
    /home/admin/config.scripts/blitz.lcd.sh hide
  else

    # IP + Domain
    whiptail --title " LNBits " --msgbox "Open the following URL in your local web browser:
http://${localip}:5000\n
Activate TOR to access from outside your local network.
" 12 54
  fi

  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^LNBits=" /mnt/hdd/raspiblitz.conf; then
  echo "LNBits=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${LNBits}" = "on" ]; then
    echo "installed=1"

    # check for error
    isDead=$(sudo systemctl status lnbits | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "installed=0"
  fi
  exit 0
fi

# status
if [ "$1" = "write-macaroons" ]; then
    
  # make sure its run as user admin
  adminUserId=$(id -u admin)
  if [ "${EUID}" != "${adminUserId}" ]; then
    echo "error='please run as admin user'"
    exit 1
  fi

  # rewrite macaroons for lnbits environment
  macaroonAdminHex=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon)
  macaroonInvoiceHex=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/invoice.macaroon)
  macaroonReadHex=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/${network}/${chain}net/readonly.macaroon)
  sudo sed -i "s/^LND_API_ENDPOINT=.*/LND_API_ENDPOINT=http:\/\/127.0.0.1:10009\/rest\//g" /home/admin/lnbits/.env
  sudo sed -i "s/^LND_ADMIN_MACAROON=.*/LND_ADMIN_MACAROON=${macaroonAdminHex}/g" /home/admin/lnbits/.env
  sudo sed -i "s/^LND_INVOICE_MACAROON=.*/LND_INVOICE_MACAROON=${macaroonInvoiceHex}/g" /home/admin/lnbits/.env
  sudo sed -i "s/^LND_READ_MACAROON=.*/LND_READ_MACAROON=${macaroonReadHex}/g" /home/admin/lnbits/.env
  echo "# OK - macaroons written to /home/admin/lnbits/.env"
  exit 0
fi

# stop service
echo "making sure services are not running"
sudo systemctl stop lnbits 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL LNBits ***"

  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ ${isInstalled} -eq 0 ]; then

    # make sure needed debian packages are installed
    echo "# installing needed packages"
    sudo apt-get install -y pipenv  2>/dev/null

    # prepare .env file
    echo "# get the github code"
    cd /home/admin
    sudo -u admin git clone https://github.com/arcbtc/lnbits.git
    #sudo -u admin git reset --hard e3fd6b4ff1f19b750b852a0bb0814cd259db948c
    
    # write macarroons to .env file
    echo "# preparing env file"
    sudo rm /home/admin/lnbits/.env 2>/dev/null 
    sudo -u admin mv /home/admin/lnbits/.example.env /home/admin/lnbits/.env 
    sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh write-macaroons
 
    # make sure in settings file LND is set as funding source
    cat > /home/admin/lnbits/lnbits/settings.py <<EOF
import os
from .wallets import LndWallet
WALLET = LndWallet(endpoint=os.getenv("LND_API_ENDPOINT"),admin_macaroon=os.getenv("LND_ADMIN_MACAROON"),invoice_macaroon=os.getenv("LND_INVOICE_MACAROON"),read_macaroon=os.getenv("LND_READ_MACAROON"))
LNBITS_PATH = os.path.dirname(os.path.realpath(__file__))
DATABASE_PATH = os.getenv("DATABASE_PATH", os.path.join(LNBITS_PATH, "data", "database.sqlite3"))
DEFAULT_USER_WALLET_NAME = os.getenv("DEFAULT_USER_WALLET_NAME", "Bitcoin LN Wallet")
FEE_RESERVE = float(os.getenv("FEE_RESERVE", 0))
EOF

    # open firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow 5000 comment 'lnbits'
    sudo ufw --force enable
    echo ""

    # install service
    echo "*** Install btc-rpc-explorer systemd ***"
    cat > /home/admin/lnd.service <<EOF
# systemd unit for BTC RPC Explorer

[Unit]
Description=lnbits
Wants=lnd.service
After=lnd.service

[Service]
WorkingDirectory=/home/admin/lnbits
ExecStartPre="cd /home/admin/lnbits && pipenv shell"
ExecStart="flask run --host=0.0.0.0"
User=admin
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal
EOF

    sudo mv /home/admin/lnbits.service /etc/systemd/system/lnbits.service 
    sudo systemctl enable lnbits
    echo "OK"

  else 
    echo "LNBits already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^LNBits=.*/LNBits=on/g" /mnt/hdd/raspiblitz.conf
  
  # Hidden Service for BTC-RPC-explorer if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh lnbits 80 5000
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^LNBits=.*/LNBits=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING LNBits ***"
    sudo systemctl stop lnbits
    sudo systemctl disable lnbits
    sudo rm /etc/systemd/system/lnbits.service
    sudo rm -r /home/admin/lnbits
    echo "OK LNBits removed."
  else 
    echo "LNBits is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
