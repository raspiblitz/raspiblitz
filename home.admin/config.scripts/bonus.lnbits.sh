#!/bin/bash

# https://github.com/lnbits/lnbits

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "small config script to switch LNbits on or off"
  echo "bonus.lnbits.sh on [?GITHUBUSER] [?BRANCH]"
  echo "bonus.lnbits.sh [off|status|menu|write-macaroons]"
  echo "# DEVELOPMENT: TO SYNC WITH YOUR FORKED GITHUB-REPO"
  echo "bonus.lnbits.sh github repo [GITHUBUSER] [?BRANCH]"
  echo "bonus.lnbits.sh github sync"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get LNbits status info
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.lnbits.sh status)

  # display possible problems with IP2TOR setup
  if [ ${#ip2torWarn} -gt 0 ]; then
    whiptail --title " Warning " \
    --yes-button "Back" \
    --no-button "Continue Anyway" \
    --yesno "Your IP2TOR+LetsEncrypt may have problems:\n${ip2torWarn}\n\nCheck if locally responding: https://${localIP}:${httpsPort}\n\nCheck if service is reachable over Tor:\n${toraddress}" 14 72
    if [ "$?" != "1" ]; then
      exit 0
	  fi
  fi

  text="Local Web Browser: https://${localIP}:${httpsPort}"

  if [ ${#publicDomain} -gt 0 ]; then
     text="${text}
Public Domain: https://${publicDomain}:${httpsPort}
port forwarding on router needs to be active & may change port"
  fi

  text="${text}\n
You need to accept self-signed HTTPS cert with SHA1 Fingerprint:
${sslFingerprintIP}"

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    text="${text}\n
TOR Browser Hidden Service address (QR see LCD):
${toraddress}"
  fi

  if [ ${#ip2torDomain} -gt 0 ]; then
    text="${text}\n
IP2TOR+LetsEncrypt: https://${ip2torDomain}:${ip2torPort}
SHA1 ${sslFingerprintTOR}"
  elif [ ${#ip2torIP} -gt 0 ]; then
    text="${text}\n
IP2TOR: https://${ip2torIP}:${ip2torPort}
SHA1 ${sslFingerprintTOR}
go MAINMENU > SUBSCRIBE and add LetsEncrypt HTTPS Domain"
  elif [ ${#publicDomain} -eq 0 ]; then
    text="${text}\n
To enable easy reachability with normal browser from the outside
consider adding a IP2TOR Bridge (MAINMENU > SUBSCRIBE)."
  fi

  whiptail --title " LNbits " --msgbox "${text}" 16 69

  /home/admin/config.scripts/blitz.display.sh hide
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

    localIP=$(hostname -I | awk '{print $1}')
    echo "localIP='${localIP}'"
    echo "httpPort='5000'"
    echo "httpsPort='5001'"
    echo "publicIP='${publicIP}'"

    # check for LetsEnryptDomain for DynDns
    error=""
    source <(sudo /home/admin/config.scripts/blitz.subscriptions.ip2tor.py ip-by-tor $publicIP)
    if [ ${#error} -eq 0 ]; then
      echo "publicDomain='${domain}'"
    fi

    sslFingerprintIP=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
    echo "sslFingerprintIP='${sslFingerprintIP}'"

    toraddress=$(sudo cat /mnt/hdd/tor/lnbits/hostname 2>/dev/null)
    echo "toraddress='${toraddress}'"

    sslFingerprintTOR=$(openssl x509 -in /mnt/hdd/app-data/nginx/tor_tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
    echo "sslFingerprintTOR='${sslFingerprintTOR}'"

    # check for IP2TOR
    error=""
    source <(sudo /home/admin/config.scripts/blitz.subscriptions.ip2tor.py ip-by-tor $toraddress)
    if [ ${#error} -eq 0 ]; then
      echo "ip2torType='${ip2tor-v1}'"
      echo "ip2torID='${id}'"
      echo "ip2torIP='${ip}'"
      echo "ip2torPort='${port}'"
      # check for LetsEnryptDomain on IP2TOR
      error=""
      source <(sudo /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py domain-by-ip $ip)
      if [ ${#error} -eq 0 ]; then
        echo "ip2torDomain='${domain}'"
        domainWarning=$(sudo /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py subscription-detail ${domain} ${port} | jq -r ".warning")
        if [ ${#domainWarning} -gt 0 ]; then
          echo "ip2torWarn='${domainWarning}'"
        fi
      fi
    fi

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

  echo "make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/lnbits/.lnd" ]]; then
    sudo rm -rf "/home/lnbits/.lnd"                          # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/lnbits/.lnd"  # and create symlink
  fi

  # set tls.cert path (use | as separator to avoid escaping file path slashes)
  sudo -u lnbits sed -i "s|^LND_REST_CERT=.*|LND_REST_CERT=/home/lnbits/.lnd/tls.cert|g" /home/lnbits/lnbits/.env

  # set macaroon  path info in .env - USING HEX IMPORT
  sudo chmod 600 /home/lnbits/lnbits/.env
  macaroonAdminHex=$(sudo xxd -ps -u -c 1000 /home/lnbits/.lnd/data/chain/${network}/${chain}net/admin.macaroon)
  macaroonInvoiceHex=$(sudo xxd -ps -u -c 1000 /home/lnbits/.lnd/data/chain/${network}/${chain}net/invoice.macaroon)
  macaroonReadHex=$(sudo xxd -ps -u -c 1000 /home/lnbits/.lnd/data/chain/${network}/${chain}net/readonly.macaroon)
  sudo sed -i "s/^LND_REST_ADMIN_MACAROON=.*/LND_REST_ADMIN_MACAROON=${macaroonAdminHex}/g" /home/lnbits/lnbits/.env
  sudo sed -i "s/^LND_REST_INVOICE_MACAROON=.*/LND_REST_INVOICE_MACAROON=${macaroonInvoiceHex}/g" /home/lnbits/lnbits/.env
  sudo sed -i "s/^LND_REST_READ_MACAROON=.*/LND_REST_READ_MACAROON=${macaroonReadHex}/g" /home/lnbits/lnbits/.env

  #echo "make sure lnbits is member of lndreadonly, lndinvoice, lndadmin"
  #sudo /usr/sbin/usermod --append --groups lndinvoice lnbits
  #sudo /usr/sbin/usermod --append --groups lndreadonly lnbits
  #sudo /usr/sbin/usermod --append --groups lndadmin lnbits

  # set macaroon  path info in .env - USING PATH
  #sudo sed -i "s|^LND_REST_ADMIN_MACAROON=.*|LND_REST_ADMIN_MACAROON=/home/lnbits/.lnd/data/chain/${network}/${chain}net/admin.macaroon|g" /home/lnbits/lnbits/.env
  #sudo sed -i "s|^LND_REST_INVOICE_MACAROON=.*|LND_REST_INVOICE_MACAROON=/home/lnbits/.lnd/data/chain/${network}/${chain}net/invoice.macaroon|g" /home/lnbits/lnbits/.env
  #sudo sed -i "s|^LND_REST_READ_MACAROON=.*|LND_REST_READ_MACAROON=/home/lnbits/.lnd/data/chain/${network}/${chain}net/read.macaroon|g" /home/lnbits/lnbits/.env
  echo "# OK - macaroons written to /home/lnbits/lnbits/.env"

  exit 0
fi

if [ "$1" = "repo" ]; then

  # get github parameters
  githubUser="$2"
  if [ ${#githubUser} -eq 0 ]; then
    echo "echo='missing parameter'"
    exit 1
  fi
  githubBranch="$3"
  if [ ${#githubBranch} -eq 0 ]; then
    githubBranch="master"
  fi

  # check if repo exists
  githubRepo="https://github.com/${githubUser}/lnbits"
  httpcode=$(curl -s -o /dev/null -w "%{http_code}" ${githubRepo})
  if [ "${httpcode}" != "200" ]; then
    echo "# tested github repo: ${githubRepo}"
    echo "error='repo for user does not exist'"
    exit 1
  fi

  # change origin repo of lnbits code
  echo "# changing LNbits github repo(${githubUser}) branch(${githubBranch})"
  cd /home/lnbits/lnbits
  sudo git remote remove origin
  sudo git remote add origin ${githubRepo}
  sudo git fetch
  sudo git checkout ${githubBranch}
  sudo git branch --set-upstream-to=origin/${githubBranch} ${githubBranch}

fi

if [ "$1" = "sync" ] || [ "$1" = "repo" ]; then
  echo "# pull all changes from github repo"
  # output basic info
  cd /home/lnbits/lnbits
  sudo git remote -v
  sudo git branch -v
  # pull latest code
  sudo git pull
  # restart lnbits service
  sudo systemctl restart lnbits
  echo "# server is restarting ... maybe takes some seconds until available"
  exit 0
fi

# stop service
echo "making sure services are not running"
sudo systemctl stop lnbits 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL LNbits ***"

  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ ${isInstalled} -eq 0 ]; then

    echo "*** Add the 'lnbits' user ***"
    sudo adduser --disabled-password --gecos "" lnbits

    # make sure needed debian packages are installed
    echo "# installing needed packages"

    # get optional github parameter
    githubUser="lnbits"
    if [ "$2" != "" ]; then
      githubUser="$2"
    fi
    githubBranch="tags/raspiblitz"
    #githubBranch="f6bcff01f4b62ca26177f22bd2d479b01d371406"
    if [ "$3" != "" ]; then
      githubBranch="$3"
    fi

    # install from GitHub
    echo "# get the github code user(${githubUser}) branch(${githubBranch})"
    sudo rm -r /home/lnbits/lnbits 2>/dev/null
    cd /home/lnbits
    sudo -u lnbits git clone https://github.com/${githubUser}/lnbits.git
    cd /home/lnbits/lnbits
    sudo -u lnbits git checkout ${githubBranch}

    # prepare .env file
    echo "# preparing env file"
    sudo rm /home/lnbits/lnbits/.env 2>/dev/null
    sudo -u lnbits touch /home/lnbits/lnbits/.env
    sudo bash -c "echo 'QUART_APP=lnbits.app:create_app()' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LNBITS_FORCE_HTTPS=0' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LNBITS_BACKEND_WALLET_CLASS=LndRestWallet' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_ENDPOINT=https://127.0.0.1:8080' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_CERT=' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_ADMIN_MACAROON=' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_INVOICE_MACAROON=' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_READ_MACAROON=' >> /home/lnbits/lnbits/.env"
    /home/admin/config.scripts/bonus.lnbits.sh write-macaroons

    # set database path to HDD data so that its survives updates and migrations
    sudo mkdir /mnt/hdd/app-data/LNBits 2>/dev/null
    sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> /home/lnbits/lnbits/.env"

    # to the install
    echo "# installing application dependencies"
    cd /home/lnbits/lnbits
    # do install like this

    sudo -u lnbits python3 -m venv venv
    #sudo -u lnbits /home/lnbits/lnbits/venv/bin/pip install hypercorn
    sudo -u lnbits ./venv/bin/pip install -r requirements.txt

    # process assets
    echo "# processing assets"
    sudo -u lnbits ./venv/bin/quart assets

    # update databases (if needed)
    echo "# updating databases"
    sudo -u lnbits ./venv/bin/quart migrate

    # open firewall
    echo
    echo "*** Updating Firewall ***"
    sudo ufw allow 5000 comment 'lnbits HTTP'
    sudo ufw allow 5001 comment 'lnbits HTTPS'
    echo ""

    # install service
    echo "*** Install systemd ***"
    cat <<EOF | sudo tee /etc/systemd/system/lnbits.service >/dev/null
# systemd unit for lnbits

[Unit]
Description=lnbits
Wants=bitcoind.service
After=bitcoind.service

[Service]
WorkingDirectory=/home/lnbits/lnbits
ExecStart=/bin/sh -c 'cd /home/lnbits/lnbits && ./venv/bin/hypercorn -k trio --bind 0.0.0.0:5000 "lnbits.app:create_app()"'
User=lnbits
Restart=always
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
EOF

    sudo systemctl enable lnbits

    source /home/admin/raspiblitz.info
    if [ "${state}" == "ready" ]; then
      echo "# OK - lnbits service is enabled, system is on ready so starting lnbits service"
      sudo systemctl start lnbits
    else
      echo "# OK - lnbits service is enabled, but needs reboot or manual starting: sudo systemctl start lnbits"
    fi

  else
    echo "LNbits already installed."
  fi

  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/lnbits_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/lnbits_ssl.conf /etc/nginx/sites-available/lnbits_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnbits_tor.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/lnbits_tor.conf /etc/nginx/sites-available/lnbits_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnbits_tor_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/lnbits_tor_ssl.conf /etc/nginx/sites-available/lnbits_tor_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/lnbits_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnbits_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnbits_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # setting value in raspi blitz config
  sudo sed -i "s/^LNBits=.*/LNBits=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh lnbits 80 5002 443 5003
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check for second parameter: should data be deleted?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe LNbits Server Data?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  # setting value in raspi blitz config
  sudo sed -i "s/^LNBits=.*/LNBits=off/g" /mnt/hdd/raspiblitz.conf

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/lnbits_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/lnbits_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/lnbits_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_tor.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off lnbits
  fi

  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ ${isInstalled} -eq 1 ] || [ "${LNBits}" == "on" ]; then
    echo "*** REMOVING LNbits ***"
    sudo systemctl stop lnbits
    sudo systemctl disable lnbits
    sudo rm /etc/systemd/system/lnbits.service
    sudo userdel -rf lnbits

    if [ ${deleteData} -eq 1 ]; then
      echo "# deleting data"
      sudo rm -R /mnt/hdd/app-data/LNBits
    else
      echo "# keeping data"
    fi

    echo "OK LNbits removed."
  else
    echo "LNbits is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
