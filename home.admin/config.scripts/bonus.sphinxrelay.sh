#!/bin/bash

# https://github.com/stakwork/sphinx-relay

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch Sphinx-Relay on,off or update"
  echo "bonus.sphinxrelay.sh on [?GITHUBUSER] [?BRANCH]"
  echo "bonus.sphinxrelay.sh [off|status|menu|write-environment|update]"
  echo "# DEVELOPMENT: TO SYNC WITH YOUR FORKED GITHUB-REPO"
  echo "bonus.sphinxrelay.sh github sync"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get status info
  echo "# collecting status info ... (please wait - can take a while)"
  source <(sudo /home/admin/config.scripts/bonus.sphinxrelay.sh status)

  # display possible problems with IP2TOR setup
  if [ "${connectionTest}" != "OK" ]; then
    whiptail --title " Warning " \
    --yes-button "Back" \
    --no-button "Continue Anyway" \
    --yesno "Your SPHINX SERVER may have problems (retry if just restarted).\n\nCheck if locally responding: http://${localIP}:${httpPort}/app\n(You should see 'INDEX' in your browser)\n\nCheck if service is reachable over Tor:\n${toraddress}/app\n\nAlso check logs with 'debug' on terminal." 16 72
    if [ "$?" != "1" ]; then
      exit 0
	  fi
  elif [ ${#ip2torWarn} -gt 0 ]; then
    whiptail --title " Warning " \
    --yes-button "Back" \
    --no-button "Continue Anyway" \
    --yesno "Your HTTPS connection over IP2TOR as has problems:\n${ip2torWarn}\n\nCheck if service is reachable over Tor:\n${toraddress}/app\n\nMaybe cancel the IP2Tor & LetsEncrypt subscription & setup fresh." 14 72
    if [ "$?" != "1" ]; then
      exit 0
	  fi
  fi

  extraPairInfo=""
  text="Go to https://sphinx.chat and download the Sphinx Chat app."

  # When IP2TOR AND LETS ENCRYPT
  if [ ${connection} = "ip2tor&letsencrypt" ]; then
    text="${text}\n
IP2TOR+LetsEncrypt: ${publicURL}
SHA1 ${sslFingerprintTOR}\n
If you connect your app with this setup you should be able to
use it securely from everywhere.
"

  # When DynDNS & LETSENCRYPT
  elif [ ${connection} = "dns&letsencrypt" ]; then
     text="${text}\n
Public Domain: ${publicURL}
port forwarding on router needs to be active & may change port" 

  # When just IP2TOR
  elif [ ${connection} = "ip2tor&selfsigned" ]; then
    text="${text}\n
IP2TOR+self-signed-HTTPS: ${publicURL}\n
IMPORTANT: For this connection to work & be secure it needs a
additional Domain with LetsEncrypt certificate for HTTPS:
MAINMENU > SUBSCRIBE & add LetsEncrypt HTTPS Domain"

  # When DynDNS
  elif [ ${connection} = "dns&selfsigned" ]; then
     text="${text}\n
Public Domain: ${publicURL}
port forwarding on router needs to be active & may change port"

  # When nothing advise 
  elif [ ${connection} = "localnetwork" ]; then
    text="${text}\n
At the moment your Sphinx Relay Server is just available
within the local network - without transport encryption.
Local server for test & debug: ${publicURL}/app\n
To enable easy reachability from the outside consider
adding a IP2TOR Bridge and reconnect:
MAINMENU > SUBSCRIBE > IP2TOR > SPHINX"
   extraPairInfo="You need to be on the same local network to make this work."

  else
    text="${text}\nUnknown Connection!"
  fi

  text="${text}\n\nUse 'Connect App' to pair Sphinx App with RaspiBlitz."

  whiptail --title " SPHINX RELAY " --yes-button "Connect App" --no-button "Back" --yesno "${text}" 15 69
  response=$?
  if [ "${response}" == "1" ]; then
      echo "please wait ..."
      exit 0
  fi

  if [ "${connection}" = "ip2tor&selfsigned" ]; then
    text="OK you now have an IP2Tor connection running - thats great!\n
BUT TO MAKE THIS WORK:\n
It needs an additional Domain with LetsEncrypt certificate for HTTPS: Go MAINMENU > SUBSCRIBE and add LetsEncrypt HTTPS Domain\n
(or cancel the IP2Tor & just use sphinx within local network)"
    whiptail --title " Warning " \
    --msgbox "${text}" 15 72
    exit 0
  fi

  if [ "${connectionApp}" != "0" ]; then
    text="There is already one app connected to the Sphinx-Relay.
There CANNOT BE MORE THAN ONE APP connected at the same time.\n
To switch devices within the Sphnix app: see PROFILE & export keys or
you have to deinstall the Sphinx-Relay with DELETE DATA & reinstall.\n
If you just upgraded from local network to IP2Tor + HTTPS --> 
open the app > PROFILE & under ADVANCED change the SERVER URL to:
${publicURL}"
    whiptail --title " Warning " \
    --msgbox "${text}" 15 76
    exit 0
  fi

  if [ ${#extraPairInfo} -eq 0 ]; then
    extraPairInfo="The base64 decoded connection string (for debug):\n${connectionCodeClear}"
  fi

  # show qr code on LCD & console
  /home/admin/config.scripts/blitz.lcd.sh qr "${connectionCode}"
	whiptail --title " Connect App with Sphinx Relay " \
	  --yes-button "Done" \
		--no-button "Show QR Code" \
		--yesno "Open the Sphinx Chat app & scan the QR code displayed on the LCD. If you dont have a RaspiBlitz with LCD choose 'Show QR Code'.\n
The connection string can also be copied if needed: ${connectionCode}\n
${extraPairInfo}" 16 70
	  if [ $? -eq 1 ]; then
      clear
      qrencode -t ANSI256 "${connectionCode}"
      echo "--> Scan this code with your Sphinx Chat App"
      echo "To shrink QR code: macOS press CMD- / LINUX press CTRL-"
      echo "Press ENTER when finished."
      read key
	  fi

  /home/admin/config.scripts/blitz.lcd.sh hide
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^sphinxrelay=" /mnt/hdd/raspiblitz.conf; then
  echo "sphinxrelay=off" >> /mnt/hdd/raspiblitz.conf
fi

# write environment configs fresh before every start
# IMPORTANT: all this needs to work without sudo because will run from systemd as sphinxrelay user
if [ "$1" = "write-environment" ]; then

  # !! all this needs to run (be called as) user: sphinxrelay

  # get basic data from status
  source <(/home/admin/config.scripts/bonus.sphinxrelay.sh status)

  # database config
  cat /home/sphinxrelay/sphinx-relay/config/config.json | \
  jq ".production.storage = \"/mnt/hdd/app-data/sphinxrelay/sphinx.db\"" > /home/sphinxrelay/sphinx-relay/config/config.json.tmp
  mv /home/sphinxrelay/sphinx-relay/config/config.json.tmp /home/sphinxrelay/sphinx-relay/config/config.json

  # update node ip in config
  cat /home/sphinxrelay/sphinx-relay/config/app.json | \
  jq ".production.tls_location = \"/mnt/hdd/app-data/lnd/tls.cert\"" | \
  jq ".production.macaroon_location = \"/mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon\"" | \
  jq ".production.lnd_log_location = \"/mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log\"" | \
  jq ".production.node_http_port = \"3300\"" | \
  jq ".production.public_url = \"${publicURL}\"" > /home/sphinxrelay/sphinx-relay/config/app.json.tmp
  mv /home/sphinxrelay/sphinx-relay/config/app.json.tmp /home/sphinxrelay/sphinx-relay/config/app.json

  # prepare production configs (loaded by nodejs app)
  cp /home/sphinxrelay/sphinx-relay/config/app.json /home/sphinxrelay/sphinx-relay/dist/config/app.json
  cp /home/sphinxrelay/sphinx-relay/config/config.json /home/sphinxrelay/sphinx-relay/dist/config/config.json
  echo "# ok - copied fresh config.json & app.json into dist directory"

  exit 0
fi

# status
# IMPORTANT: make sure it can run as sphinxrelay user without sudo
if [ "$1" = "status" ]; then

  if [ "${sphinxrelay}" = "on" ]; then
    echo "installed=1"
  else
    echo "installed=0"
  fi

  localIP=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  echo "localIP='${localIP}'"
  echo "httpsPort='3301'"
  echo "httpPort='3300'"
  echo "publicIP='${publicIP}'"

  # get connection string from file
  connectionCode=$(cat /home/sphinxrelay/sphinx-relay/connection_string.txt 2>/dev/null)
  if [ -f "/home/sphinxrelay/sphinx-relay/connection_string.txt" ] && [ "${connectionCode}" = "" ]; then
    # try again with sodu
    connectionCode=$(sudo cat /home/sphinxrelay/sphinx-relay/connection_string.txt)
  fi
  echo "connectionCode='${connectionCode}'"
  
  # decode with base64 for debug
  connectionCodeClear=$(echo -n "${connectionCode}" | base64 --decode)
  echo "connectionCodeClear='${connectionCodeClear}'"
  
  # check for LetsEnryptDomain for DynDns
  error=""
  source <(/home/admin/config.scripts/blitz.subscriptions.ip2tor.py ip-by-tor $publicIP)
  publicDomain="${domain}"
  if [ ${#error} -eq 0 ]; then
    echo "publicDomain='${publicDomain}'"
  else
    echo "publicDomain=''"
  fi

  sslFingerprintIP=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
  echo "sslFingerprintIP='${sslFingerprintIP}'"

  toraddress=$(cat /home/sphinxrelay/sphinx-relay/dist/toraddress.txt 2>/dev/null)
  echo "toraddress='${toraddress}'"

  sslFingerprintTOR=$(openssl x509 -in /mnt/hdd/app-data/nginx/tor_tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
  echo "sslFingerprintTOR='${sslFingerprintTOR}'"

  # check for IP2TOR
  error=""
  ip2torIP=""
  ip2torPort=""
  source <(/home/admin/config.scripts/blitz.subscriptions.ip2tor.py ip-by-tor $toraddress)
  if [ ${#error} -eq 0 ]; then
    ip2torIP="${ip}"
    ip2torPort="${port}"
    echo "ip2torType='${ip2tor-v1}'"
    echo "ip2torID='${id}'"
    echo "ip2torIP='${ip}'"
    echo "ip2torPort='${port}'"
    # check for LetsEnryptDomain on IP2TOR
    ip2torDomain=""
    error=""
    source <(/home/admin/config.scripts/blitz.subscriptions.letsencrypt.py domain-by-ip $ip)
    if [ ${#error} -eq 0 ]; then
      ip2torDomain="${domain}"
      echo "ip2torDomain='${ip2torDomain}'"
      # by default the relay gives a 404 .. so just test of no HTTP code at all comes back
      httpcode=$(/home/admin/config.scripts/blitz.subscriptions.letsencrypt.py subscription-detail ${domain} ${port} | jq -r ".https_response")
      if [ "${httpcode}" = "0" ]; then
        echo "ip2torWarn='Not able to get HTTPS response.'"
      fi
    fi
  fi

  # determnine the public url for the pairing code based on best setup
  connection=""
  publicURL=""

  # 1) IP2TOR & LETS ENCRYPT HTTPS
  if [ "${ip2torDomain}" != "" ]; then
    connection="ip2tor&letsencrypt"
    publicURL="https://${ip2torDomain}:${ip2torPort}"

  # 2) DYNDNS & LETS ENCRYPT HTTPS (forwarding same port)
  elif [ "${publicDomain}" != "" ]; then
    connection="dns&letsencrypt"
    publicURL="https://${publicDomain}:3301"

  # 3) IP2TOR & SELFSIGNED HTTPS
  elif [ "${ip2torIP}" != "" ]; then
    connection="ip2tor&selfsigned"
    publicURL="https://${ip2torIP}:${ip2torPort}"

  # 4) DYNDOMAIN & SELFSIGNED HTTPS (forwarding same port)
  elif [ "${dynDomain}" != "" ]; then
    connection="dns&selfsigned"
    publicURL="https://${dynDomain}:3301"

  # 5) LOCAL NETWORK (just HTTP)
  else
    connection="localnetwork"
    publicURL="http://${localIP}:3300"

  fi
  echo "connection='${connection}'"
  echo "publicURL='${publicURL}'"

  connectionCodeContainsPublicUrl=$( echo "${connectionCodeClear}" | grep -c "${publicURL}" )
  if [ ${connectionCodeContainsPublicUrl} -eq 0 ]; then
    echo "ip2torWarn='Connection String not updated yet. Try again a bit later or check for errors.'"
  fi

  # test connection (accept self-signed certs here) ... calling the url /app should return INDEX
  connectionTest="n/a"
  connectionResponse=$(curl --insecure ${publicURL}/app 2>/dev/null)
  if [ "${connectionResponse}" == "INDEX" ]; then
    connectionTest="OK"
  else
    connectionTest="fail"
  fi
  echo "connectionTest='${connectionTest}'"

  # check if already an app was connected to relay (after that a second connection will not work)
  connectionApp=$(sudo sqlite3 /mnt/hdd/app-data/sphinxrelay/sphinx.db "SELECT * FROM sphinx_contacts WHERE auth_token IS NOT NULL;" 2>/dev/null | grep -c "1||")
  echo "connectionApp=${connectionApp}"

  exit 0
fi

if [ "$1" = "sync" ]; then
  echo "# pull all changes from github repo"
  # output basic info
  cd /home/sphinxrelay/sphinx-relay
  sudo git remote -v
  sudo git branch -v
  # pull latest code
  sudo git pull
  # update npm installs
  npm install
  # write environment
  sudo -u sphinxrelay /home/admin/config.scripts/bonus.sphinxrelay.sh write-environment
  # restart service
  sudo systemctl restart sphinxrelay
  echo "# server is restarting ... maybe takes some seconds until available"
  exit 0
fi

# stop service
echo "# making sure services are not running"
sudo systemctl stop sphinxrelay 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL SPHINX-RELAY ***"

  isInstalled=$(sudo ls /etc/systemd/system/sphinxrelay.service 2>/dev/null | grep -c 'sphinxrelay.service')
  if [ ${isInstalled} -eq 0 ]; then

    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # make sure keysend is on
    /home/admin/config.scripts/lnd.keysend.sh on

    echo "*** Add the 'sphinxrelay' user ***"
    sudo adduser --disabled-password --gecos "" sphinxrelay
    sudo /usr/sbin/usermod --append --groups lndadmin sphinxrelay
    sudo /usr/sbin/usermod --append --groups lndsigner sphinxrelay
    sudo /usr/sbin/usermod --append --groups lndrouter sphinxrelay

    # install needed install packages
    sudo apt install -y sqlite3

    # get optional github parameter
    githubUser="stakwork"
    if [ "$2" != "" ]; then
      githubUser="$2"
    fi
    githubBranch="master"
    if [ "$3" != "" ]; then
      githubBranch="$3"
    fi
    TAG=""
    if [ "$4" != "" ]; then
      TAG="$3"
    fi

    # install from GitHub
    echo "# get the github code user(${githubUser}) branch(${githubBranch})"
    sudo rm -r /home/sphinxrelay/sphinx-relay 2>/dev/null
    cd /home/sphinxrelay
    sudo -u sphinxrelay git clone https://github.com/${githubUser}/sphinx-relay.git
    cd /home/sphinxrelay/sphinx-relay

    # set to latest release tag
    sudo -u sphinxrelay git checkout ${githubBranch} || exit 1
    sudo -u sphinxrelay git pull  || exit 1
    if [ "${TAG}" == "" ]; then
      TAG=$(git tag | sort -V | tail -1)
    fi
    if [ "${TAG}" != "ignore" ]; then
      echo "# Reset to the latest release tag --> ${TAG}"
      sudo -u sphinxrelay git reset --hard $TAG || exit 1
    else
      echo "# IGNORING release tag .. running latest code of branch ${githubBranch}"
    fi

    echo "# NPM install dependencies ..."
    sudo -u sphinxrelay npm install

    # open firewall
    echo
    echo "*** Updating Firewall ***"
    sudo ufw allow 3300 comment 'sphinxrelay HTTP'
    sudo ufw allow 3301 comment 'sphinxrelay HTTPS'
    echo ""

    # Hidden Service if Tor is active
    source /mnt/hdd/raspiblitz.conf
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with internet.tor.sh script
      /home/admin/config.scripts/internet.hiddenservice.sh sphinxrelay 80 3302 443 3303
      # get TOR address and store it readable for sphixrelay user
      toraddress=$(sudo cat /mnt/hdd/tor/sphinxrelay/hostname 2>/dev/null)
      sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"
    fi

    # set database path to HDD data so that its survives updates and migrations
    sudo mkdir /mnt/hdd/app-data/sphinxrelay 2>/dev/null
    sudo chown sphinxrelay:sphinxrelay -R /mnt/hdd/app-data/sphinxrelay

    # write environment (do after possible tor activation)
    sudo -u sphinxrelay /home/admin/config.scripts/bonus.sphinxrelay.sh write-environment

    # install service
    echo "*** Install systemd ***"
    cat > /home/admin/sphinxrelay.service <<EOF
[Unit]
Description=SphinxRelay
Wants=lnd.service
After=lnd.service

[Service]
WorkingDirectory=/home/sphinxrelay/sphinx-relay
ExecStartPre=/home/admin/config.scripts/bonus.sphinxrelay.sh write-environment
ExecStart=env NODE_ENV=production /usr/bin/node dist/app.js
User=sphinxrelay
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo mv /home/admin/sphinxrelay.service /etc/systemd/system/sphinxrelay.service
    sudo chown root:root /etc/systemd/system/sphinxrelay.service

    sudo systemctl enable sphinxrelay

    source /home/admin/raspiblitz.info
    if [ "${state}" == "ready" ]; then
      echo "# OK - sphinxrelay service is enabled, system is on ready so starting service"
      sudo systemctl start sphinxrelay
    else
      echo "# OK - sphinxrelay service is enabled, but needs reboot or manual starting: sudo systemctl start sphinxrelay"
    fi

  else
    echo "# sphinxrelay already installed."
  fi

  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/sphinxrelay_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/sphinxrelay_ssl.conf /etc/nginx/sites-available/sphinxrelay_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/sphinxrelay_tor.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/sphinxrelay_tor.conf /etc/nginx/sites-available/sphinxrelay_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/sphinxrelay_tor_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/sphinxrelay_tor_ssl.conf /etc/nginx/sites-available/sphinxrelay_tor_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/sphinxrelay_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/sphinxrelay_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/sphinxrelay_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # setting value in raspi blitz config
  sudo sed -i "s/^sphinxrelay=.*/sphinxrelay=on/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# Updating Sphinx-Relay"

  # deinstall without deleting data
  /home/admin/config.scripts/bonus.sphinxrelay.sh off --keep-data

  # reinstall to work with same data
  /home/admin/config.scripts/bonus.sphinxrelay.sh on

  #cd /home/sphinxrelay/sphinx-relay/
  ## https://github.com/stakwork/sphinx-relay/blob/master/docs/raspiblitz_deployment.md#fast-method
  #echo "# Stashing the config"
  #if [ $(sudo -u sphinxrelay git stash 2>&1 | grep -c "Please tell me who you are") -gt 0 ]; then
  #  sudo -u sphinxrelay git config user.email "you@example.com"
  #  sudo -u sphinxrelay git config user.name "Your Name"
  #fi
  #sudo -u sphinxrelay git stash
  #echo "# Pulling latest changes..."
  #sudo -u sphinxrelay git checkout master || exit 1
  #sudo -u sphinxrelay git pull  || exit 1
  #echo "# Reset to the latest release tag"
  #TAG=$(git tag | sort -V | tail -1)
  #sudo -u sphinxrelay git reset --hard $TAG || exit 1
  #echo "# Reapplying the config"
  #sudo -u sphinxrelay git stash pop
  #echo "# Installing NPM dependencies"
  #sudo -u sphinxrelay npm install
  #echo "# Updated to version" $TAG
  #echo
  #echo "# Starting the sphinxrelay.service ... "
  #sudo systemctl start sphinxrelay
  
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
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe SphinxRelay Data?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  # setting value in raspi blitz config
  sudo sed -i "s/^sphinxrelay=.*/sphinxrelay=off/g" /mnt/hdd/raspiblitz.conf

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/sphinxrelay_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/sphinxrelay_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/sphinxrelay_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/sphinxrelay_ssl.conf
  sudo rm -f /etc/nginx/sites-available/sphinxrelay_tor.conf
  sudo rm -f /etc/nginx/sites-available/sphinxrelay_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh off sphinxrelay
  fi

  isInstalled=$(sudo ls /etc/systemd/system/sphinxrelay.service 2>/dev/null | grep -c 'sphinxrelay.service')
  if [ ${isInstalled} -eq 1 ] || [ "${sphinxrelay}" == "on" ]; then
    echo "*** REMOVING SPHINXRELAY ***"
    sudo systemctl stop sphinxrelay
    sudo systemctl disable sphinxrelay
    sudo rm /etc/systemd/system/sphinxrelay.service
    sudo userdel -rf sphinxrelay

    if [ ${deleteData} -eq 1 ]; then
      echo "# deleting data"
      sudo rm -R /mnt/hdd/app-data/sphinxrelay
    else
      echo "# keeping data"
    fi

    echo "OK sphinxrelay removed."
  else
    echo "sphinxrelay is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
