#!/bin/bash

# https://github.com/lnbits/lnbits-legend

# https://github.com/lnbits/lnbits-legend/releases
tag="0.9.1"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to switch LNbits on or off."
  echo "Installs the version ${tag} by default."
  echo "Usage:"
  echo "bonus.lnbits.sh on [lnd|tlnd|slnd|cl|tcl|scl] [?GITHUBUSER] [?BRANCH|?TAG]"
  echo "bonus.lnbits.sh switch [lnd|tlnd|slnd|cl|tcl|scl]"
  echo "bonus.lnbits.sh off"
  echo "bonus.lnbits.sh status"
  echo "bonus.lnbits.sh menu"
  echo "bonus.lnbits.sh prestart"
  echo "bonus.lnbits.sh repo [githubuser] [branch]"
  echo "bonus.lnbits.sh sync"
  exit 1
fi

echo "# Running: 'bonus.lnbits.sh $*'"
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

  # add info on funding source
  fundinginfo=""
  if [ "${LNBitsFunding}" == "lnd" ] || [ "${LNBitsFunding}" == "tlnd" ] || [ "${LNBitsFunding}" == "slnd" ]; then
    fundinginfo="on LND "
  elif [ "${LNBitsFunding}" == "cl" ] || [ "${LNBitsFunding}" == "tcl" ] || [ "${LNBitsFunding}" == "scl" ]; then
    fundinginfo="on c-lightning "
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
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    text="${text}\n
TOR Browser Hidden Service address (QR see LCD):
${toraddress}"
  fi

  if [ ${#ip2torDomain} -gt 0 ]; then
    text="${text}\n
IP2TOR+LetsEncrypt: https://${ip2torDomain}:${ip2torPort}
SHA1 ${sslFingerprintTOR}\n
https://${ip2torDomain}:${ip2torPort} ready for public use"
  elif [ ${#ip2torIP} -gt 0 ]; then
    text="${text}\n
IP2TOR: https://${ip2torIP}:${ip2torPort}
SHA1 ${sslFingerprintTOR}\n
Consider adding a LetsEncrypt HTTPS Domain under OPTIONS."
  elif [ ${#publicDomain} -eq 0 ]; then
    text="${text}\n
To enable easy reachability with normal browser from the outside
Consider adding a IP2TOR Bridge under OPTIONS."
  fi

  whiptail --title " LNbits ${fundinginfo}" --yes-button "OK" --no-button "OPTIONS" --yesno "${text}" 18 69
  result=$?
  sudo /home/admin/config.scripts/blitz.display.sh hide
  echo "option (${result}) - please wait ..."

  # exit when user presses OK to close menu
  if [ ${result} -eq 0 ]; then
    exit 0
  fi

  # LNbits OPTIONS menu
  OPTIONS=()

  # IP2TOR options
  if [ "${ip2torDomain}" != "" ]; then
    # IP2TOR+LetsEncrypt active - offer cancel
    OPTIONS+=(IP2TOR-OFF "Cancel IP2Tor Subscription for LNbits")
  elif [ "${ip2torIP}" != "" ]; then
    # just IP2TOR active - offer cancel or Lets Encrypt
    OPTIONS+=(HTTPS-ON "Add free HTTPS-Certificate for LNbits")
    OPTIONS+=(IP2TOR-OFF "Cancel IP2Tor Subscription for LNbits")
  else
    OPTIONS+=(IP2TOR-ON "Make Public with IP2Tor Subscription")
  fi

  # Change Funding Source options (only if available)
  if [ "${LNBitsFunding}" == "lnd" ] && [ "${cl}" == "on" ]; then
    OPTIONS+=(SWITCH-CL "Switch: Use c-lightning as funding source")
  elif [ "${LNBitsFunding}" == "cl" ] && [ "${lnd}" == "on" ]; then
    OPTIONS+=(SWITCH-LND "Switch: Use LND as funding source")
  fi

  WIDTH=66
  CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
  HEIGHT=$((CHOICE_HEIGHT+7))
  CHOICE=$(dialog --clear \
                --title " LNbits - Options" \
                --ok-label "Select" \
                --cancel-label "Back" \
                --menu "Choose one of the following options:" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

  case $CHOICE in
        IP2TOR-ON)
            python /home/admin/config.scripts/blitz.subscriptions.ip2tor.py create-ssh-dialog LNBITS ${toraddress} 443
            exit 0
            ;;
        IP2TOR-OFF)
            clear
            python /home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-cancel ${ip2torID}
            echo
            echo "OK - PRESS ENTER to continue"
            read key
            exit 0
            ;;
        HTTPS-ON)
            python /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py create-ssh-dialog
            exit 0
            ;;
        SWITCH-CL)
            clear
            /home/admin/config.scripts/bonus.lnbits.sh switch cl
            echo "Restarting LNbits ..."
            sudo systemctl restart lnbits
            echo
            echo "OK new funding source for LNbits active."
            echo "PRESS ENTER to continue"
            read key
            exit 0
            ;;
        SWITCH-LND)
            clear
            /home/admin/config.scripts/bonus.lnbits.sh switch lnd
            echo "Restarting LNbits ..."
            sudo systemctl restart lnbits
            echo
            echo "OK new funding source for LNbits active."
            echo "PRESS ENTER to continue"
            read key
            exit 0
            ;;
        *)
            clear
            exit 0
  esac

  exit 0
fi

# status
if [ "$1" = "status" ]; then

  if [ "${LNBits}" = "on" ]; then
    echo "installed=1"

    localIP=$(hostname -I | awk '{print $1}')
    echo "localIP='${localIP}'"
    echo "httpPort='5000'"
    echo "httpsPort='5001'"
    echo "httpsForced='1'"
    echo "httpsSelfsigned='1'" # TODO: change later if IP2Tor+LetsEncrypt is active
    echo "authMethod='none'"
    echo "publicIP='${publicIP}'"

    # check funding source
    if [ "${LNBitsFunding}" == "" ]; then
      LNBitsFunding="lnd"
    fi
    echo "LNBitsFunding='${LNBitsFunding}'"

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
      exit 0
    fi

  else
    echo "installed=0"
  fi
  exit 0
fi

##########################
# PRESTART
# - will be called as prestart by systemd service (as user lnbits)
#########################

if [ "$1" = "prestart" ]; then

  # users need to be `lnbits` so that it can be run by systemd as prestart (no SUDO available)
  if [ "$USER" != "lnbits" ]; then
    echo "# FAIL: run as user lnbits"
    exit 1
  fi

  # get if its for lnd or cl service
  echo "## lnbits.service PRESTART CONFIG"
  echo "# --> /home/lnbits/lnbits/.env"

  # set values based in funding source in raspiblitz config
  LNBitsNetwork="bitcoin"
  LNBitsChain=""
  LNBitsLightning=""
  if [ "${LNBitsFunding}" == "" ] || [ "${LNBitsFunding}" == "lnd" ]; then
    LNBitsFunding="lnd"
    LNBitsLightning="lnd"
    LNBitsChain="main"
  elif [ "${LNBitsFunding}" == "tlnd" ]; then
    LNBitsLightning="lnd"
    LNBitsChain="test"
  elif [ "${LNBitsFunding}" == "slnd" ]; then
    LNBitsLightning="lnd"
    LNBitsChain="sig"
  elif [ "${LNBitsFunding}" == "cl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="main"
  elif [ "${LNBitsFunding}" == "tcl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="test"
  elif [ "${LNBitsFunding}" == "scl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="sig"
  else
    echo "# FAIL: Unknown LNBitsFunding=${LNBitsFunding}"
    exit 1
  fi

  echo "# LNBitsFunding(${LNBitsFunding}) --> network(${LNBitsNetwork}) chain(${LNBitsChain}) lightning(${LNBitsLightning})"

  # set lnd config
  if [ "${LNBitsLightning}" == "lnd" ]; then

    echo "# setting lnd config fresh ..."

    # check if lnbits user has read access on lnd data files
    checkReadAccess=$(cat /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon | grep -c "lnd")
    if [ "${checkReadAccess}" != "1" ]; then
      echo "# FAIL: missing lnd data in '/mnt/hdd/app-data/lnd' or missing access rights for lnbits user"
      exit 1
    fi

    echo "# Updating LND TLS & macaroon data fresh for LNbits config ..."

    # set tls.cert path (use | as separator to avoid escaping file path slashes)
    sed -i "s|^LND_REST_CERT=.*|LND_REST_CERT=/mnt/hdd/app-data/lnd/tls.cert|g" /home/lnbits/lnbits/.env

    # set macaroon  path info in .env - USING HEX IMPORT
    chmod 600 /home/lnbits/lnbits/.env
    macaroonAdminHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon)
    macaroonInvoiceHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/invoice.macaroon)
    macaroonReadHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/readonly.macaroon)
    sed -i "s/^LND_REST_ADMIN_MACAROON=.*/LND_REST_ADMIN_MACAROON=${macaroonAdminHex}/g" /home/lnbits/lnbits/.env
    sed -i "s/^LND_REST_INVOICE_MACAROON=.*/LND_REST_INVOICE_MACAROON=${macaroonInvoiceHex}/g" /home/lnbits/lnbits/.env
    sed -i "s/^LND_REST_READ_MACAROON=.*/LND_REST_READ_MACAROON=${macaroonReadHex}/g" /home/lnbits/lnbits/.env

  elif [ "${LNBitsLightning}" == "cl" ]; then

    isUsingCL=$(cat /home/lnbits/lnbits/.env | grep -c "LNBITS_BACKEND_WALLET_CLASS=CLightningWallet")
    if [ "${isUsingCL}" != "1" ]; then
      echo "# FAIL: /home/lnbits/lnbits/.env not set to c-lightning"
      exit 1
    fi

    echo "# everything looks OK for lnbits config on c-lightning on ${LNBitsChain}net"

  else
    echo "# FAIL: missing or not supported LNBitsLightning=${LNBitsLightning}"
    exit 1
  fi

  echo "# OK: prestart finished"
  exit 0 # exit with clean code
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
  #githubRepo="https://github.com/${githubUser}/lnbits"
  githubRepo="https://github.com/${githubUser}/lnbits-legend"

  httpcode=$(curl -s -o /dev/null -w "%{http_code}" ${githubRepo})
  if [ "${httpcode}" != "200" ]; then
    echo "# tested github repo: ${githubRepo}"
    echo "error='repo for user does not exist'"
    exit 1
  fi

  # change origin repo of lnbits code
  echo "# changing LNbits github repo(${githubUser}) branch(${githubBranch})"
  cd /home/lnbits/lnbits
  sudo -u lnbits git remote remove origin
  sudo -u lnbits git remote add origin ${githubRepo}
  sudo -u lnbits git fetch
  sudo -u lnbits git checkout ${githubBranch}
  sudo -u lnbits git branch --set-upstream-to=origin/${githubBranch} ${githubBranch}

fi

if [ "$1" = "sync" ] || [ "$1" = "repo" ]; then
  echo "# pull all changes from github repo"
  # output basic info
  cd /home/lnbits/lnbits
  sudo -u lnbits git remote -v
  sudo -u lnbits git branch -v
  # pull latest code
  sudo -u lnbits git pull

  # install
  sudo -u lnbits python3 -m venv venv
  sudo -u lnbits ./venv/bin/pip install -r requirements.txt
  sudo -u lnbits ./venv/bin/pip install pylightning
  sudo -u lnbits ./venv/bin/pip install secp256k1
  sudo -u lnbits ./venv/bin/pip install pyln-client

  # build
  sudo -u lnbits ./venv/bin/python build.py
  # restart lnbits service
  sudo systemctl restart lnbits
  echo "# server is restarting ... maybe takes some seconds until available"
  exit 0
fi

# stop service
sudo systemctl stop lnbits 2>/dev/null

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if already installed
  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ "${isInstalled}" == "1" ]; then
    echo "# FAIL: already installed"
    exit 1
  fi

  # get funding source and check that its available
  fundingsource="$2"

  # run with default funding source if not given as parameter
  if [ "${fundingsource}" == "" ]; then
    echo "# running with default lightning as funing source: ${lightning}"
    fundingsource="${lightning}"
  fi

  if [ "${fundingsource}" == "lnd" ]; then
    if [ "${lnd}" != "on" ]; then
      echo "# FAIL: lnd mainnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "tlnd" ]; then
    if [ "${tlnd}" != "on" ]; then
      echo "# FAIL: lnd testnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "slnd" ]; then
    if [ "${slnd}" != "on" ]; then
      echo "# FAIL: lnd signet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "cl" ]; then
    if [ "${cl}" != "on" ]; then
      echo "# FAIL: c-lightning mainnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "tcl" ]; then
    if [ "${tcl}" != "on" ]; then
      echo "# FAIL: c-lightning testnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "scl" ]; then
    if [ "${scl}" != "on" ]; then
      echo "# FAIL: c-lightning signet needs to be activated"
      exit 1
    fi

  else
    echo "# FAIL: invalid funding source parameter"
    exit 1
  fi

  # add lnbits user
  echo "*** Add the 'lnbits' user ***"
  sudo adduser --disabled-password --gecos "" lnbits

  # get optional github parameter
  githubUser="lnbits"
  if [ "$3" != "" ]; then
    githubUser="$3"
  fi
  if [ "$4" != "" ]; then
    tag="$4"
  fi

  # install from GitHub
  echo "# get the github code user(${githubUser}) branch(${tag})"
  sudo rm -r /home/lnbits/lnbits 2>/dev/null
  cd /home/lnbits
  sudo -u lnbits git clone https://github.com/${githubUser}/lnbits-legend lnbits
  cd /home/lnbits/lnbits
  sudo -u lnbits git checkout ${tag} || exit 1

  # prepare .env file
  echo "# preparing env file"
  sudo rm /home/lnbits/lnbits/.env 2>/dev/null
  sudo -u lnbits touch /home/lnbits/lnbits/.env
  sudo bash -c "echo 'LNBITS_FORCE_HTTPS=0' >> /home/lnbits/lnbits/.env"

  # set database path to HDD data so that its survives updates and migrations
  sudo mkdir /mnt/hdd/app-data/LNBits 2>/dev/null
  sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits
  sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> /home/lnbits/lnbits/.env"

  # let switch command part do the detail config
  /home/admin/config.scripts/bonus.lnbits.sh switch ${fundingsource}

  # to the install
  echo "# installing application dependencies"
  cd /home/lnbits/lnbits

  # do install like this
  sudo -u lnbits python3 -m venv venv
  sudo -u lnbits ./venv/bin/pip install -r requirements.txt
  sudo -u lnbits ./venv/bin/pip install pylightning
  sudo -u lnbits ./venv/bin/pip install secp256k1
  sudo -u lnbits ./venv/bin/pip install pyln-client

  # build
  sudo -u lnbits ./venv/bin/python build.py

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
ExecStartPre=/home/admin/config.scripts/bonus.lnbits.sh prestart

ExecStart=/bin/sh -c 'cd /home/lnbits/lnbits && ./venv/bin/uvicorn lnbits.__main__:app --port 5000'
User=lnbits
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
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

    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      echo "# OK - lnbits service is enabled, system is on ready so starting lnbits service"
      sudo systemctl start lnbits
    else
      echo "# OK - lnbits service is enabled, but needs reboot or manual starting: sudo systemctl start lnbits"
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
  /home/admin/config.scripts/blitz.conf.sh set LNBits "on"

  # Hidden Service if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh lnbits 80 5002 443 5003
  fi

  echo "# OK install done ... might need to restart or call: sudo systemctl start lnbits"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# config for a special funding source (e.g lnd or c-lightning as backend)
if [ "$1" = "switch" ]; then

  echo "## bonus.lnbits.sh switch $2"

  # get funding source and check that its available
  fundingsource="$2"
  clrpcsubdir=""
  if [ "${fundingsource}" == "lnd" ]; then
    if [ "${lnd}" != "on" ]; then
      echo "#FAIL: lnd mainnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "tlnd" ]; then
    if [ "${tlnd}" != "on" ]; then
      echo "# FAIL: lnd testnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "slnd" ]; then
    if [ "${slnd}" != "on" ]; then
      echo "# FAIL: lnd signet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "cl" ]; then
    if [ "${cl}" != "on" ]; then
      echo "# FAIL: c-lightning mainnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "tcl" ]; then
    clrpcsubdir="/testnet"
    if [ "${tcl}" != "on" ]; then
      echo "# FAIL: c-lightning testnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "scl" ]; then
    clrpcsubdir="/signet"
    if [ "${scl}" != "on" ]; then
      echo "# FAIL: c-lightning signet not installed or running"
      exit 1
    fi

  else
    echo "# FAIL: unvalid fundig source parameter"
    exit 1
  fi

  echo "##############"
  echo "# NOTE: If you switch the funding source of a running LNbits instance all sub account will keep balance."
  echo "# Make sure that the new funding source has enough sats to cover the LNbits bookeeping of sub accounts."
  echo "##############"

  # remove all old possible settings for former funding source (clean state)
  sudo sed -i "/^LNBITS_BACKEND_WALLET_CLASS=/d" /home/lnbits/lnbits/.env 2>/dev/null
  sudo sed -i "/^LND_REST_ENDPOINT=/d" /home/lnbits/lnbits/.env 2>/dev/null
  sudo sed -i "/^LND_REST_CERT=/d" /home/lnbits/lnbits/.env 2>/dev/null
  sudo sed -i "/^LND_REST_ADMIN_MACAROON=/d" /home/lnbits/lnbits/.env 2>/dev/null
  sudo sed -i "/^LND_REST_INVOICE_MACAROON=/d" /home/lnbits/lnbits/.env 2>/dev/null
  sudo sed -i "/^LND_REST_READ_MACAROON=/d" /home/lnbits/lnbits/.env 2>/dev/null
  sudo /usr/sbin/usermod -G lnbits lnbits
  sudo sed -i "/^CLIGHTNING_RPC=/d" /home/lnbits/lnbits/.env 2>/dev/null

  # LND CONFIG
  if [ "${fundingsource}" == "lnd" ] || [ "${fundingsource}" == "tlnd" ] || [ "${fundingsource}" == "slnd" ]; then

    # make sure lnbits user can access LND credentials
    echo "# adding lnbits user is member of lndreadonly, lndinvoice, lndadmin"
    sudo /usr/sbin/usermod --append --groups lndinvoice lnbits
    sudo /usr/sbin/usermod --append --groups lndreadonly lnbits
    sudo /usr/sbin/usermod --append --groups lndadmin lnbits

    # prepare config entries in lnbits config for lnd
    echo "# preparing lnbits config for lnd"
    sudo bash -c "echo 'LNBITS_BACKEND_WALLET_CLASS=LndRestWallet' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_ENDPOINT=https://127.0.0.1:8080' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_CERT=' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_ADMIN_MACAROON=' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_INVOICE_MACAROON=' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'LND_REST_READ_MACAROON=' >> /home/lnbits/lnbits/.env"

  fi

  if [ "${fundingsource}" == "cl" ] || [ "${fundingsource}" == "tcl" ] || [ "${fundingsource}" == "scl" ]; then

    echo "# add the 'lnbits' user to the 'bitcoin' group"
    sudo /usr/sbin/usermod --append --groups bitcoin lnbits
    echo "# check user"
    id lnbits

    echo "# allowing lnbits user as part of the bitcoin group to RW RPC hook"
    sudo chmod 770 /home/bitcoin/.lightning/bitcoin${clrpcsubdir}
    sudo chmod 660 /home/bitcoin/.lightning/bitcoin${clrpcsubdir}/lightning-rpc
    if [ "${fundingsource}" == "cl" ]; then
      CLCONF="/home/bitcoin/.lightning/config"
    else
      CLCONF="/home/bitcoin/.lightning${clrpcsubdir}/config"
    fi
    # https://github.com/rootzoll/raspiblitz/issues/3007
    if [ "$(sudo cat ${CLCONF} | grep -c "^rpc-file-mode=0660")" -eq 0 ]; then
      echo "rpc-file-mode=0660" | sudo tee -a ${CLCONF}
    fi

    echo "# preparing lnbits config for c-lightning"
    sudo bash -c "echo 'LNBITS_BACKEND_WALLET_CLASS=CLightningWallet' >> /home/lnbits/lnbits/.env"
    sudo bash -c "echo 'CLIGHTNING_RPC=/home/bitcoin/.lightning/bitcoin${clrpcsubdir}/lightning-rpc' >> /home/lnbits/lnbits/.env"
  fi

  # set raspiblitz config value for funding
  /home/admin/config.scripts/blitz.conf.sh set LNBitsFunding "${fundingsource}"

  echo "##############"
  echo "# OK new funding source set - does need restart or call: sudo systemctl restart lnbits"
  echo "##############"

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
  echo "*** REMOVING LNbits ***"

  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ ${isInstalled} -eq 1 ] || [ "${LNBits}" == "on" ]; then
    sudo systemctl stop lnbits
    sudo systemctl disable lnbits
    sudo rm /etc/systemd/system/lnbits.service
    echo "OK lnbits.service removed."
  else
    echo "lnbits.service is not installed."
  fi

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

  # always clean
  sudo userdel -rf lnbits

  if [ ${deleteData} -eq 1 ]; then
    echo "# deleting data"
    sudo rm -R /mnt/hdd/app-data/LNBits
  else
    echo "# keeping data"
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set LNBits "off"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
