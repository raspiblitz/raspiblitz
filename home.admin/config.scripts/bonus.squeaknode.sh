#!/bin/bash

# https://github.com/yzernik/squeaknode

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "small config script to switch squeaknode on or off"
  echo "bonus.squeaknode.sh on [?GITHUBUSER] [?BRANCH]"
  echo "bonus.squeaknode.sh [off|status|menu|write-macaroons]"
  echo "# DEVELOPMENT: TO SYNC WITH YOUR FORKED GITHUB-REPO"
  echo "bonus.squeaknode.sh github repo [GITHUBUSER] [?BRANCH]"
  echo "bonus.squeaknode.sh github sync"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get squeaknode status info
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.squeaknode.sh status)

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

  whiptail --title " squeaknode " --msgbox "${text}" 16 69

  /home/admin/config.scripts/blitz.display.sh hide
  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^squeaknode=" /mnt/hdd/raspiblitz.conf; then
  echo "squeaknode=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${squeaknode}" = "on" ]; then
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

    toraddress=$(sudo cat /mnt/hdd/tor/squeaknode/hostname 2>/dev/null)
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
    isDead=$(sudo systemctl status squeaknode | grep -c 'inactive (dead)')
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
  if ! [[ -L "/home/squeaknode/.lnd" ]]; then
    sudo rm -rf "/home/squeaknode/.lnd"                          # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/squeaknode/.lnd"  # and create symlink
  fi

  # set tls.cert path (use | as separator to avoid escaping file path slashes)
  sudo -u squeaknode sed -i "s|^LND_REST_CERT=.*|LND_REST_CERT=/home/squeaknode/.lnd/tls.cert|g" /home/squeaknode/squeaknode/.env

  # set macaroon  path info in .env - USING HEX IMPORT
  sudo chmod 600 /home/squeaknode/squeaknode/.env
  macaroonAdminHex=$(sudo xxd -ps -u -c 1000 /home/squeaknode/.lnd/data/chain/${network}/${chain}net/admin.macaroon)
  macaroonInvoiceHex=$(sudo xxd -ps -u -c 1000 /home/squeaknode/.lnd/data/chain/${network}/${chain}net/invoice.macaroon)
  macaroonReadHex=$(sudo xxd -ps -u -c 1000 /home/squeaknode/.lnd/data/chain/${network}/${chain}net/readonly.macaroon)
  sudo sed -i "s/^LND_REST_ADMIN_MACAROON=.*/LND_REST_ADMIN_MACAROON=${macaroonAdminHex}/g" /home/squeaknode/squeaknode/.env
  sudo sed -i "s/^LND_REST_INVOICE_MACAROON=.*/LND_REST_INVOICE_MACAROON=${macaroonInvoiceHex}/g" /home/squeaknode/squeaknode/.env
  sudo sed -i "s/^LND_REST_READ_MACAROON=.*/LND_REST_READ_MACAROON=${macaroonReadHex}/g" /home/squeaknode/squeaknode/.env

  #echo "make sure squeaknode is member of lndreadonly, lndinvoice, lndadmin"
  #sudo /usr/sbin/usermod --append --groups lndinvoice squeaknode
  #sudo /usr/sbin/usermod --append --groups lndreadonly squeaknode
  #sudo /usr/sbin/usermod --append --groups lndadmin squeaknode

  # set macaroon  path info in .env - USING PATH
  #sudo sed -i "s|^LND_REST_ADMIN_MACAROON=.*|LND_REST_ADMIN_MACAROON=/home/squeaknode/.lnd/data/chain/${network}/${chain}net/admin.macaroon|g" /home/squeaknode/squeaknode/.env
  #sudo sed -i "s|^LND_REST_INVOICE_MACAROON=.*|LND_REST_INVOICE_MACAROON=/home/squeaknode/.lnd/data/chain/${network}/${chain}net/invoice.macaroon|g" /home/squeaknode/squeaknode/.env
  #sudo sed -i "s|^LND_REST_READ_MACAROON=.*|LND_REST_READ_MACAROON=/home/squeaknode/.lnd/data/chain/${network}/${chain}net/read.macaroon|g" /home/squeaknode/squeaknode/.env
  echo "# OK - macaroons written to /home/squeaknode/squeaknode/.env"

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
  githubRepo="https://github.com/${githubUser}/squeaknode"
  httpcode=$(curl -s -o /dev/null -w "%{http_code}" ${githubRepo})
  if [ "${httpcode}" != "200" ]; then
    echo "# tested github repo: ${githubRepo}"
    echo "error='repo for user does not exist'"
    exit 1
  fi

  # change origin repo of squeaknode code
  echo "# changing squeaknode github repo(${githubUser}) branch(${githubBranch})"
  cd /home/squeaknode/squeaknode
  sudo git remote remove origin
  sudo git remote add origin ${githubRepo}
  sudo git fetch
  sudo git checkout ${githubBranch}
  sudo git branch --set-upstream-to=origin/${githubBranch} ${githubBranch}

fi

if [ "$1" = "sync" ] || [ "$1" = "repo" ]; then
  echo "# pull all changes from github repo"
  # output basic info
  cd /home/squeaknode/squeaknode
  sudo git remote -v
  sudo git branch -v
  # pull latest code
  sudo git pull
  # restart squeaknode service
  sudo systemctl restart squeaknode
  echo "# server is restarting ... maybe takes some seconds until available"
  exit 0
fi

# stop service
echo "making sure services are not running"
sudo systemctl stop squeaknode 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL squeaknode ***"

  isInstalled=$(sudo ls /etc/systemd/system/squeaknode.service 2>/dev/null | grep -c 'squeaknode.service')
  if [ ${isInstalled} -eq 0 ]; then

    echo "*** Add the 'squeaknode' user ***"
    sudo adduser --disabled-password --gecos "" squeaknode

    # make sure needed debian packages are installed
    echo "# installing needed packages"

    # get optional github parameter
    githubUser="yzernik"
    if [ "$2" != "" ]; then
      githubUser="$2"
    fi
    githubBranch="master"
    #githubBranch="f6bcff01f4b62ca26177f22bd2d479b01d371406"
    if [ "$3" != "" ]; then
      githubBranch="$3"
    fi


    # install from GitHub
    echo "# get the github code user(${githubUser}) branch(${githubBranch})"
    sudo rm -r /home/squeaknode/squeaknode 2>/dev/null
    cd /home/squeaknode
    sudo -u squeaknode git clone https://github.com/${githubUser}/squeaknode.git
    cd /home/squeaknode/squeaknode
    sudo -u squeaknode git checkout ${githubBranch}

    # prepare .env file
    echo "# preparing env file"
    sudo rm /home/squeaknode/squeaknode/.env 2>/dev/null
    sudo -u squeaknode touch /home/squeaknode/squeaknode/.env
    sudo bash -c "echo 'QUART_APP=squeaknode.app:create_app()' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_FORCE_HTTPS=0' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_BACKEND_WALLET_CLASS=LndRestWallet' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'LND_REST_ENDPOINT=https://127.0.0.1:8080' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'LND_REST_CERT=' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'LND_REST_ADMIN_MACAROON=' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'LND_REST_INVOICE_MACAROON=' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'LND_REST_READ_MACAROON=' >> /home/squeaknode/squeaknode/.env"
    /home/admin/config.scripts/bonus.squeaknode.sh write-macaroons

    # set database path to HDD data so that its survives updates and migrations
    sudo mkdir /mnt/hdd/app-data/squeaknode 2>/dev/null
    sudo chown squeaknode:squeaknode -R /mnt/hdd/app-data/squeaknode
    sudo bash -c "echo 'SQUEAKNODE_DATA_FOLDER=/mnt/hdd/app-data/squeaknode' >> /home/squeaknode/squeaknode/.env"

    # to the install
    echo "# installing application dependencies"
    cd /home/squeaknode/squeaknode
    # do install like this

    sudo -u squeaknode python3 -m venv venv
    sudo -u squeaknode ./venv/bin/pip install -r requirements.txt

    # process assets
    echo "# processing assets"
    sudo -u squeaknode ./venv/bin/quart assets

    # update databases (if needed)
    echo "# updating databases"
    sudo -u squeaknode ./venv/bin/quart migrate

    # open firewall
    echo
    echo "*** Updating Firewall ***"
    sudo ufw allow 5000 comment 'squeaknode HTTP'
    sudo ufw allow 5001 comment 'squeaknode HTTPS'
    echo ""

    # install service
    echo "*** Install systemd ***"
    cat <<EOF | sudo tee /etc/systemd/system/squeaknode.service >/dev/null
# systemd unit for squeaknode

[Unit]
Description=squeaknode
Wants=bitcoind.service
After=bitcoind.service

[Service]
WorkingDirectory=/home/squeaknode/squeaknode
ExecStart=/bin/sh -c 'cd /home/squeaknode/squeaknode && ./venv/bin/hypercorn -k trio --bind 0.0.0.0:5000 "squeaknode.app:create_app()"'
User=squeaknode
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

    sudo systemctl enable squeaknode

    source /home/admin/raspiblitz.info
    if [ "${state}" == "ready" ]; then
      echo "# OK - squeaknode service is enabled, system is on ready so starting squeaknode service"
      sudo systemctl start squeaknode
    else
      echo "# OK - squeaknode service is enabled, but needs reboot or manual starting: sudo systemctl start squeaknode"
    fi

  else
    echo "squeaknode already installed."
  fi

  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/squeaknode_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/squeaknode_ssl.conf /etc/nginx/sites-available/squeaknode_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/squeaknode_tor.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/squeaknode_tor.conf /etc/nginx/sites-available/squeaknode_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/squeaknode_tor_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/squeaknode_tor_ssl.conf /etc/nginx/sites-available/squeaknode_tor_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/squeaknode_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/squeaknode_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/squeaknode_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # setting value in raspi blitz config
  sudo sed -i "s/^squeaknode=.*/squeaknode=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh squeaknode 80 5002 443 5003
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
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe squeaknode Server Data?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  # setting value in raspi blitz config
  sudo sed -i "s/^squeaknode=.*/squeaknode=off/g" /mnt/hdd/raspiblitz.conf

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/squeaknode_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/squeaknode_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/squeaknode_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/squeaknode_ssl.conf
  sudo rm -f /etc/nginx/sites-available/squeaknode_tor.conf
  sudo rm -f /etc/nginx/sites-available/squeaknode_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh off squeaknode
  fi

  isInstalled=$(sudo ls /etc/systemd/system/squeaknode.service 2>/dev/null | grep -c 'squeaknode.service')
  if [ ${isInstalled} -eq 1 ] || [ "${squeaknode}" == "on" ]; then
    echo "*** REMOVING squeaknode ***"
    sudo systemctl stop squeaknode
    sudo systemctl disable squeaknode
    sudo rm /etc/systemd/system/squeaknode.service
    sudo userdel -rf squeaknode

    if [ ${deleteData} -eq 1 ]; then
      echo "# deleting data"
      sudo rm -R /mnt/hdd/app-data/squeaknode
    else
      echo "# keeping data"
    fi

    echo "OK squeaknode removed."
  else
    echo "squeaknode is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
