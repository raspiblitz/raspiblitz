#!/bin/bash
# https://github.com/pxsocs/specter_warden

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch specter warden on or off"
 echo "bonus.specter-warden.sh [status|on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf
echo "# bonus.specter-warden.sh $1"

# get status key/values
if [ "$1" = "status" ]; then

  if [ "${warden}" = "on" ]; then

    echo "configured=1"

    # get network info
    localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
    toraddress=$(sudo cat /mnt/hdd/tor/specter-warden/hostname 2>/dev/null)
    fingerprint=$(openssl x509 -in /home/bitcoin/.specter/cert.pem -fingerprint -noout | cut -d"=" -f2)
    echo "localip='${localip}'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"

    # check for error
    serviceFailed=$(sudo systemctl status specter-warden | grep -c 'inactive (dead)')
    if [ "${serviceFailed}" = "1" ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "configured=0"
  fi
  
  exit 0
fi

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.specter-warden.sh status)
  echo "# toraddress: ${toraddress}"

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " Specter warden " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:25442

SHA1 Thumb/Fingerprint:
${fingerprint}

Hidden Service address for TOR Browser (QR see LCD):
https://${toraddress}
" 18 74
    /home/admin/config.scripts/blitz.lcd.sh hide
  else

    # IP + Domain
    whiptail --title " Specter warden " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:25442

SHA1 Thumb/Fingerprint:
${fingerprint}

Activate TOR to access the web block explorer from outside your local network.
" 15 74
  fi

  echo "# please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^warden=" /mnt/hdd/raspiblitz.conf; then
  echo "warden=off" >> /mnt/hdd/raspiblitz.conf
fi


# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  isInstalled=$(sudo ls /etc/systemd/system/cryptoadvance-specter.service 2>/dev/null | grep -c 'cryptoadvance-specter.service' || /bin/true)
  if [ ${isInstalled} -eq 0 ]; then
	/home/admin/config.scripts/bonus.cryptoadvance-specter.sh on
  fi

  echo "#    --> INSTALL Specter warden ***"

  isInstalled=$(sudo ls /etc/systemd/system/specter-warden.service 2>/dev/null | grep -c 'specter-warden.service' || /bin/true)
  if [ ${isInstalled} -eq 0 ]; then

	sudo -u bitcoin /home/bitcoin/.specter/.env/bin/python3 -m pip install --upgrade gunicorn

	cd /home/bitcoin/.specter
    sudo -u bitcoin git clone https://github.com/pxsocs/specter_warden.git
	cd specter_warden
    sudo -u bitcoin git reset --hard 0.5a

	sudo -u bitcoin /home/bitcoin/.specter/.env/bin/python3 -m pip install -r requirements.txt --upgrade

    # activating Authentication here ...
    echo "#    --> creating App-config"
    cat > /home/admin/wsgi.py <<EOF
from warden import create_app

app = create_app()
EOF

	sudo mv /home/admin/wsgi.py /home/bitcoin/.specter/specter_warden/
    sudo chown bitcoin:bitcoin /home/bitcoin/.specter/specter_warden/wsgi.py

    # open firewall
    echo "#    --> Updating Firewall"
    sudo ufw allow 25442 comment 'specter-warden'
    sudo ufw --force enable
    echo ""

    # install service
    echo "#    --> Install specter-warden systemd service"
    cat > /home/admin/specter-warden.service <<EOF
[Unit]
Description = specter warden
After = network.target

[Service]
PermissionsStartOnly = true
PIDFile = /run/warden/warden.pid
User = bitcoin
Group = bitcoin
WorkingDirectory = /home/bitcoin/.specter/specter_warden
ExecStartPre = /bin/mkdir /run/warden
ExecStartPre = /bin/chown -R bitcoin:bitcoin /run/warden
ExecStart = /home/bitcoin/.specter/.env/bin/gunicorn --certfile /home/bitcoin/.specter/cert.pem --keyfile /home/bitcoin/.specter/key.pem --workers=1 wsgi:app -b 0.0.0.0:25442 --pid /run/warden/warden.pid
ExecReload = /bin/kill -s HUP $MAINPID
ExecStop = /bin/kill -s TERM $MAINPID
ExecStopPost = /bin/rm -rf /run/warden
PrivateTmp = true

[Install]
WantedBy = multi-user.target

EOF

    sudo mv /home/admin/specter-warden.service /etc/systemd/system/specter-warden.service
    sudo systemctl enable specter-warden

    echo "#    --> OK - the specter-warden service is now enabled and started"
  else 
    echo "#    --> specter-warden already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^warden=.*/warden=on/g" /mnt/hdd/raspiblitz.conf
  
  # Hidden Service for SERVICE if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    # port 25442 is HTTPS with self-signed cert - warden only makes sense to be served over HTTPS
    /home/admin/config.scripts/internet.hiddenservice.sh specter-warden 443 25442
  fi


  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^warden=.*/warden=off/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh off specter-warden
  fi

  isInstalled=$(sudo ls /etc/systemd/system/specter-warden.service 2>/dev/null | grep -c 'specter-warden.service')
  if [ ${isInstalled} -eq 1 ]; then

    echo "#    --> REMOVING Specter warden"
    sudo systemctl stop specter-warden
    sudo systemctl disable specter-warden
    sudo rm /etc/systemd/system/specter-warden.service
    sudo -u bitcoin /home/bitcoin/.specter/.env/bin/python3 -m pip uninstall --yes gunicorn
	sudo rm -rf /home/bitcoin/.bitcoin/specter-warden
	sudo ufw deny 25442

    echo "#    --> OK Specter warden removed."
  else 
    echo "#    --> Specter warden is not installed."
  fi
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "#    --> UPDATING Specter warden"
  cd /home/bitcoin/.specter/specter_warden
  sudo -u bitcoin git pull
  sudo -u bitcoin /home/bitcoin/.specter/.env/bin/python3 -m pip install -r requirements.txt
  echo "#    --> Updated to the latest in https://github.com/pxsocs/specter_warden ***"
  echo "#    --> Starting the specter-warden.service"
  sudo systemctl restart specter-warden
  exit 0
fi

echo "error='unknown parameter'"
exit 1
