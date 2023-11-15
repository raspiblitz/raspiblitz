#!/bin/bash

# Based on: https://gist.github.com/normandmickey/3f10fc077d15345fb469034e3697d0d0

# https://github.com/dgarage/NBXplorer/tags
NBXplorerVersion="v2.3.67"
# https://github.com/btcpayserver/btcpayserver/releases
BTCPayVersion="v1.11.7"

# check who signed the release (person that published release)
PGPsigner="nicolasdorier"
PGPpubkeyLink="https://keybase.io/nicolasdorier/pgp_keys.asc"
PGPpubkeyFingerprint="AB4CFA9895ACA0DBE27F6B346618763EF09186FE"
# ---
#PGPsigner="Kukks"
#PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
#PGPpubkeyFingerprint="8E5530D9D1C93097"
# ---
#PGPsigner="web-flow"
#PGPpubkeyLink="https://github.com/web-flow.gpg"
#PGPpubkeyFingerprint="4AEE18F83AFDEB23"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to switch BTCPay Server on or off"
  echo "bonus.btcpayserver.sh menu"
  echo "bonus.btcpayserver.sh [install|uninstall]"
  echo "bonus.btcpayserver.sh [on|off|menu|write-tls-macaroon|cln-lightning-rpc-access]"
  echo "installs BTCPayServer $BTCPayVersion with NBXplorer $NBXplorerVersion"
  echo "To update to the latest release published on github run:"
  echo "bonus.btcpayserver.sh update"
  echo
  exit 1
fi

source /mnt/hdd/raspiblitz.conf
# get cpu architecture (checked with 'uname -m')
source /home/admin/raspiblitz.info
source <(/home/admin/_cache.sh get state)

function NBXplorerConfig() {
  # check the postgres database
  if sudo -u postgres psql -c '\l' | grep nbxplorermainnet; then
    echo "# nbxplorermainnet database already exists"
  else
    echo "# Generate the database for nbxplorer"
    sudo -u postgres psql -c "CREATE DATABASE nbxplorermainnet TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
    sudo -u postgres psql -c "CREATE USER nbxplorer WITH ENCRYPTED PASSWORD 'raspiblitz';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE nbxplorermainnet TO nbxplorer;"
    # for migrations
    sudo -u postgres psql -d nbxplorermainnet -c "GRANT ALL PRIVILEGES ON SCHEMA public TO nbxplorer;"
  fi

  # https://docs.btcpayserver.org/Deployment/ManualDeploymentExtended/#4-create-a-configuration-file
  echo
  echo "# Getting RPC credentials from the bitcoin.conf"
  RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  sudo -u btcpay mkdir -p /home/btcpay/.nbxplorer/Main
  echo "\
network=mainnet
btc.rpc.user=${RPC_USER}
btc.rpc.password=${PASSWORD_B}
postgres=User ID=nbxplorer;Host=localhost;Port=5432;Application Name=nbxplorer;MaxPoolSize=20;Database=nbxplorermainnet;Password='raspiblitz';
automigrate=1
nomigrateevts=1
" | sudo -u btcpay tee /home/btcpay/.nbxplorer/Main/settings.config
  sudo chmod 600 /home/btcpay/.nbxplorer/Main/settings.config
}

function BtcPayConfig() {
  # set thumbprint
  FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -inform pem -in /home/btcpay/.lnd/tls.cert | cut -d"=" -f2)
  # set up postgres
  if sudo -u postgres psql -c '\l' | grep btcpaymainnet; then
    echo "# btcpaymainnet database already exists"
  else
    echo "# Generate the database for btcpay"
    sudo -u postgres psql -c "CREATE DATABASE btcpaymainnet TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
    sudo -u postgres psql -c "CREATE USER btcpay WITH ENCRYPTED PASSWORD 'raspiblitz';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE btcpaymainnet TO btcpay;"
    # for migrations
    sudo -u postgres psql -d btcpaymainnet -c "GRANT ALL PRIVILEGES ON SCHEMA public TO btcpay;"
  fi

  echo "# Regenerate the btcpayserver settings (includes the LND TLS thumbprint)"
  # https://docs.btcpayserver.org/Deployment/ManualDeploymentExtended/#3-create-a-configuration-file
  sudo -u btcpay mkdir -p /home/btcpay/.btcpayserver/Main
  echo "
### Global settings ###
network=mainnet

### Server settings ###
port=23000
bind=127.0.0.1
externalurl=https://$BTCPayDomain
socksendpoint=127.0.0.1:9050

### NBXplorer settings ###
BTC.explorer.url=http://127.0.0.1:24444/
BTC.lightning=type=lnd-rest;server=https://127.0.0.1:8080/;macaroonfilepath=/home/btcpay/admin.macaroon;certthumbprint=$FINGERPRINT

### Database ###
postgres=User ID=btcpay;Host=localhost;Port=5432;Application Name=btcpay;MaxPoolSize=20;Database=btcpaymainnet;Password='raspiblitz';
explorer.postgres=User ID=nbxplorer;Host=localhost;Port=5432;Application Name=nbxplorer;MaxPoolSize=20;Database=nbxplorermainnet;Password='raspiblitz';
" | sudo -u btcpay tee /home/btcpay/.btcpayserver/Main/settings.config
}

function BtcPayService() {
  if sudo ls /mnt/hdd/app-data/.btcpayserver/Main/sqllite.db 1>/dev/null 2>&1; then
    echo "# sqlite database exists - will be ignored after the migration to postgresql"
    databaseOption=" -- --sqlitefile=sqllite.db"
  else
    echo "# sqlite database does not exist, using postgresql"
    databaseOption=""
  fi
  # see the configuration options with:
  # sudo -u btcpay /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release --project "/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj" -- -h
  # run manually to debug:
  # sudo -u btcpay /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release --project "/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj" -- --sqlitefile=sqllite.db
  echo "# create the btcpayserver.service"
  echo "
[Unit]
Description=BtcPayServer daemon
Requires=nbxplorer.service
After=nbxplorer.service

[Service]
ExecStart=/home/btcpay/dotnet/dotnet run --no-launch-profile --no-build \
 -c Release --project \"/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj\" ${databaseOption}
User=btcpay
Group=btcpay
Type=simple
PIDFile=/run/btcpayserver/btcpayserver.pid
Restart=always
RestartSec=10

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/btcpayserver.service
  sudo systemctl daemon-reload
}

if [ "$1" = "status" ]; then

  echo "version='${BTCPayVersion}'"

  isInstalled=$(compgen -u | grep -c btcpay)
  echo "prepared=${isInstalled}"
  isActive=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  echo "installed=${isActive}"

  if [ "${BTCPayServer}" = "on" ]; then
    echo "switchedon=1"
    localIP=$(hostname -I | awk '{print $1}')
    echo "localIP='${localIP}'"
    echo "httpPort='23000'"
    echo "httpsPort='23001'"
    echo "httpsForced='1'"
    echo "httpsSelfsigned='1'" # TODO: change later if IP2Tor+LetsEncrypt is active
    echo "authMethod='userdefined'"
    echo "publicIP='${publicIP}'"

    # check for LetsEncryptDomain for DynDns
    error=""
    source <(sudo /home/admin/config.scripts/blitz.subscriptions.ip2tor.py ip-by-tor $publicIP 2>/dev/null)
    if [ ${#error} -eq 0 ]; then
      echo "publicDomain='${domain}'"
    fi

    sslFingerprintIP=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
    echo "sslFingerprintIP='${sslFingerprintIP}'"

    toraddress=$(sudo cat /mnt/hdd/tor/btcpay/hostname 2>/dev/null)
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
    isDead=$(sudo systemctl status btcpayserver | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
    fi

  else
    echo "switchedon=0"
  fi
  exit 0
fi

# show info menu
if [ "$1" = "menu" ]; then

  # get status info
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.btcpayserver.sh status)

  if [ ${switchedon} -eq 0 ]; then
    whiptail --title " BTCPay Server " --msgbox "BTCPay Server is not activated." 7 36
    exit 0
  fi

  if [ ${installed} -eq 0 ]; then
    whiptail --title " BTCPay Server " --msgbox "BTCPay Server needs to be re-installed.\nPress OK to start process." 8 45
    /home/admin/config.scripts/bonus.btcpayserver.sh on
    exit 0
  fi

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

  text="${text}
SHA1 ${sslFingerprintIP}"

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    text="${text}\n
Tor Browser Hidden Service address (see the QR onLCD):
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
consider adding a IP2TOR Bridge: MAINMENU > SUBSCRIBE > IP2TOR"
  fi

  text="${text}\n
To get the 'Connection String' to activate Lightning Payments:
MAINMENU > CONNECT > BTCPay Server"

  whiptail --title " BTCPay Server " --msgbox "${text}" 17 69

  sudo /home/admin/config.scripts/blitz.display.sh hide
  echo "# please wait ..."
  exit 0
fi

# write-tls-macaroon
if [ "$1" = "write-tls-macaroon" ]; then

  echo "# make sure btcpay is member of lndadmin"
  sudo /usr/sbin/usermod --append --groups lndadmin btcpay

  echo "# make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/btcpay/.lnd" ]]; then
    sudo rm -rf "/home/btcpay/.lnd"                         # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/btcpay/.lnd" # and create symlink
  fi

  # copy admin macaroon
  echo "# extra symlink to admin.macaroon for btcpay"
  if ! [[ -L "/home/btcpay/admin.macaroon" ]]; then
    sudo ln -s "/home/btcpay/.lnd/data/chain/${network}/${chain}net/admin.macaroon" "/home/btcpay/admin.macaroon"
  fi

  BtcPayConfig

  if [ "${state}" == "ready" ]; then
    sudo systemctl restart btcpayserver
  fi
  exit 0
fi

# cln-lightning-rpc-access
if [ "$1" = "cln-lightning-rpc-access" ]; then
  if [ "${cl}" = "on" ]; then
    source <(/home/admin/config.scripts/network.aliases.sh getvars cl mainnet)

    if [ $(grep -c "^rpc-file-mode=0660" <${CLCONF}) -eq 0 ]; then
      echo "rpc-file-mode=0660" | tee -a ${CLCONF}
      if [ "${state}" == "ready" ]; then
        sudo systemctl restart lightningd
      fi
    fi

    echo "# make sure btcpay is member of the bitcoin group"
    sudo /usr/sbin/usermod --append --groups bitcoin btcpay

    if [ "${state}" == "ready" ]; then
      sudo systemctl restart btcpayserver
    fi
  else
    echo "# Install CLN first"
    exit 1
  fi

  echo "
In the BTCPayServer Lightning Wallet settings 'Connect to a Lightning node' page
fill in the 'Connection configuration for your custom Lightning node:' box on with:

type=clightning;server=unix:///home/bitcoin/.lightning/bitcoin/lightning-rpc
"
  exit 0
fi

########################################
# INSTALL (just user, code & compile)
########################################

if [ "$1" = "install" ]; then

  # check if code is already installed
  isInstalled=$(compgen -u | grep -c btcpay)
  if [ "${isInstalled}" != "0" ]; then
    echo "# already installed"
    exit 0
  fi

  echo "# create btcpay user"
  sudo adduser --system --group --home /home/btcpay btcpay
  cd /home/btcpay || exit 1

  echo "# install .NET"
  # https://dotnet.microsoft.com/en-us/download/dotnet/6.0
  sudo apt-get -y install libunwind8 gettext libssl1.0
  cpu=$(uname -m)
  if [ "${cpu}" = "aarch64" ]; then
    binaryVersion="arm64"
    dotNetdirectLink="https://download.visualstudio.microsoft.com/download/pr/d43345e2-f0d7-4866-b56e-419071f30ebe/68debcece0276e9b25a65ec5798cf07b/dotnet-sdk-6.0.101-linux-arm64.tar.gz"
    dotNetChecksum="04cd89279f412ae6b11170d1724c6ac42bb5d4fae8352020a1f28511086dd6d6af2106dd48ebe3b39d312a21ee8925115de51979687a9161819a3a29e270a954"
  elif [ "${cpu}" = "x86_64" ]; then
    binaryVersion="x64"
    dotNetdirectLink="https://download.visualstudio.microsoft.com/download/pr/ede8a287-3d61-4988-a356-32ff9129079e/bdb47b6b510ed0c4f0b132f7f4ad9d5a/dotnet-sdk-6.0.101-linux-x64.tar.gz"
    dotNetChecksum="ca21345400bcaceadad6327345f5364e858059cfcbc1759f05d7df7701fec26f1ead297b6928afa01e46db6f84e50770c673146a10b9ff71e4c7f7bc76fbf709"
  else
    echo "# FAIL! CPU (${cpu}) not supported."
    echo "result='dotnet cpu not supported'"
    exit 1
  fi
  dotNetName="dotnet-sdk-6.0.101-linux-${binaryVersion}.tar.gz"
  sudo rm /home/btcpay/${dotnetName} 2>/dev/null
  sudo -u btcpay wget "${dotNetdirectLink}" -O "${dotNetName}"
  # check binary is was not manipulated (checksum test)
  actualChecksum=$(sha512sum /home/btcpay/${dotNetName} | cut -d " " -f1)
  if [ "${actualChecksum}" != "${dotNetChecksum}" ]; then
    echo "# FAIL # Downloaded ${dotNetName} not matching SHA512 checksum: ${dotNetChecksum}"
    echo "result='dotnet wrong checksum'"
    exit 1
  fi
  sudo -u btcpay mkdir /home/btcpay/dotnet
  sudo -u btcpay tar -xvf ${dotNetName} -C /home/btcpay/dotnet
  sudo rm -f *.tar.gz*
  echo "DOTNET_CLI_TELEMETRY_OPTOUT=1" | sudo tee -a /etc/environment

  # NBXplorer
  echo "# Install NBXplorer $NBXplorerVersion"
  cd /home/btcpay || exit 1
  echo "# Download the NBXplorer source code $NBXplorerVersion"
  sudo -u btcpay git clone https://github.com/dgarage/NBXplorer.git 2>/dev/null
  cd NBXplorer || exit 1
  sudo -u btcpay git reset --hard $NBXplorerVersion
  # PGP verify
  NBXPGPsigner="nicolasdorier"
  NBXPGPpubkeyLink="https://keybase.io/nicolasdorier/pgp_keys.asc"
  NBXPGPpubkeyFingerprint="AB4CFA9895ACA0DBE27F6B346618763EF09186FE"
  sudo -u btcpay /home/admin/config.scripts/blitz.git-verify.sh "${NBXPGPsigner}" "${NBXPGPpubkeyLink}" "${NBXPGPpubkeyFingerprint}" || exit 1
  echo "# Build NBXplorer $NBXplorerVersion"
  # from the build.sh with path
  sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release NBXplorer/NBXplorer.csproj || exit 1

  # BTCPayServer
  echo "# Install BTCPayServer"
  cd /home/btcpay || exit 1
  echo "# Download the BTCPayServer source code $BTCPayVersion"
  sudo -u btcpay git clone https://github.com/btcpayserver/btcpayserver.git 2>/dev/null
  cd btcpayserver || exit 1
  sudo -u btcpay git reset --hard $BTCPayVersion
  #sudo -u btcpay /home/admin/config.scripts/blitz.git-verify.sh "web-flow" "https://github.com/web-flow.gpg" "4AEE18F83AFDEB23" || exit 1

  echo "# verify signature of ${PGPsigner}"
  sudo -u btcpay /home/admin/config.scripts/blitz.git-verify.sh "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

  echo "# Build BTCPayServer $BTCPayVersion"
  # from the build.sh with path
  sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release \
    /home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj || exit 1

  exit 0
fi

########################################
# UNINSTALL (remove from system)
########################################

if [ "$1" = "uninstall" ]; then

  isActive=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ "${isActive}" != "0" ]; then
    echo "# cannot uninstall if still 'on'"
    exit 1
  fi

  # clear dotnet cache
  /home/btcpay/dotnet/dotnet nuget locals all --clear 2>/dev/null

  # remove dotnet
  sudo rm -rf /usr/share/dotnet 2>/dev/null

  # nuke user
  sudo userdel -rf btcpay 2>/dev/null

  echo "# uninstall done"

  exit 0
fi

########################################
# ON (activate & config)
########################################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if already active
  isActive=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ "${isActive}" != "0" ]; then
    echo "result='already active'"
    exit 1
  fi

  # check if code is already installed
  isInstalled=$(compgen -u | grep -c btcpay)
  if [ "${isInstalled}" == "0" ]; then
    echo "# Installing code base & dependencies first .."
    /home/admin/config.scripts/bonus.btcpayserver.sh install || exit 1
  fi

  echo "# ACTIVATE BTCPAYSERVER"

  echo "# install postreSQL"
  sudo /home/admin/config.scripts/bonus.postgresql.sh on || exit 1

  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/btcpay_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/btcpay_ssl.conf /etc/nginx/sites-available/btcpay_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/btcpay_tor.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/btcpay_tor.conf /etc/nginx/sites-available/btcpay_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/btcpay_tor_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/btcpay_tor_ssl.conf /etc/nginx/sites-available/btcpay_tor_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/btcpay_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/btcpay_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/btcpay_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # open the firewall
  echo "# Updating the firewall"
  sudo ufw allow 23000 comment 'allow BTCPay HTTP'
  sudo ufw allow 23001 comment 'allow BTCPay HTTPS'
  echo

  # Hidden Service for BTCPay if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh btcpay 80 23002 443 23003
  fi

  # check for $BTCPayDomain
  source /mnt/hdd/raspiblitz.conf
  if [ "${BTCPayDomain}" == "off" ]; then
    BTCPayDomain=""
  fi

  # stop services
  echo "# making sure services are not running"
  sudo systemctl stop nbxplorer 2>/dev/null
  sudo systemctl stop btcpayserver 2>/dev/null

  cd /home/btcpay || exit 1

  # store BTCpay data on HDD
  sudo mkdir /mnt/hdd/app-data/.btcpayserver 2>/dev/null

  # move old btcpay data to app-data
  sudo mv -f /mnt/hdd/.btcpayserver/* /mnt/hdd/app-data/.btcpayserver/ 2>/dev/null
  sudo rm -rf /mnt/hdd/.btcpayserver 2>/dev/null

  sudo chown -R btcpay:btcpay /mnt/hdd/app-data/.btcpayserver
  sudo ln -s /mnt/hdd/app-data/.btcpayserver /home/btcpay/ 2>/dev/null
  sudo chown -R btcpay:btcpay /home/btcpay/.btcpayserver

  ## see the configuration options with:
  # sudo -u btcpay /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release --project "NBXplorer/NBXplorer.csproj" -c /home/btcpay/.nbxplorer/Main/settings.config -h
  ##sudo systenmct run manually to debug:
  # sudo su - btcpay
  # cd NBXplorer
  # /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release --project "NBXplorer/NBXplorer.csproj" -- $@
  echo "# create the nbxplorer.service"
  echo "
[Unit]
Description=NBXplorer daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
WorkingDirectory=/home/btcpay/NBXplorer
ExecStart=/home/btcpay/dotnet/dotnet run --no-launch-profile --no-build \
 -c Release --project \"NBXplorer/NBXplorer.csproj\" -- \$@
User=btcpay
Group=btcpay
Type=simple
PIDFile=/run/nbxplorer/nbxplorer.pid
Restart=on-failure
RestartSec=20

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/nbxplorer.service

  sudo systemctl daemon-reload
  # start to create settings.config
  sudo systemctl enable nbxplorer

  if [ "${state}" == "ready" ]; then
    echo "# Starting nbxplorer"
    sudo systemctl start nbxplorer
    echo "# Checking for nbxplorer config"
    while [ ! -f "/home/btcpay/.nbxplorer/Main/settings.config" ]; do
      echo "# Waiting for nbxplorer to start - CTRL+C to abort"
      sleep 10
      hasFailed=$(sudo systemctl status nbxplorer | grep -c "Active: failed")
      if [ ${hasFailed} -eq 1 ]; then
        echo "# seems like starting nbxplorer service has failed - see: systemctl status nbxplorer"
        echo "# maybe report here: https://github.com/rootzoll/raspiblitz/issues/214"
      fi
    done
  else
    echo "# Because the system is not 'ready' the service 'nbxplorer' will not be started at this point .. its enabled and will start on next reboot"
  fi

  NBXplorerConfig

  # whitelist localhost in bitcoind
  if ! sudo grep -Eq "^whitelist=127.0.0.1" /mnt/hdd/bitcoin/bitcoin.conf; then
    echo "whitelist=127.0.0.1" | sudo tee -a /mnt/hdd/bitcoin/bitcoin.conf
    bitcoindRestart=yes
  fi

  if [ "${state}" == "ready" ]; then
    if [ "${bitcoindRestart}" == "yes" ]; then
      echo "# Restarting bitcoind"
      sudo systemctl restart bitcoind
    fi
    sudo systemctl restart nbxplorer
  fi

  BtcPayConfig

  BtcPayService

  sudo systemctl enable btcpayserver
  if [ "${state}" == "ready" ]; then
    echo "# Starting btcpayserver"
    sudo systemctl start btcpayserver
    echo "# Checking for btcpayserver config"
    while [ ! -f "/home/btcpay/.btcpayserver/Main/settings.config" ]; do
      echo "# Waiting for btcpayserver to start - CTRL+C to abort .."
      sleep 30
      hasFailed=$(sudo systemctl status btcpayserver | grep -c "Active: failed")
      if [ ${hasFailed} -eq 1 ]; then
        echo "# seems like starting btcpayserver service has failed - see: systemctl status btcpayserver"
        echo "# maybe report here: https://github.com/rootzoll/raspiblitz/issues/214"
      fi
    done
  else
    echo "# Because the system is not 'ready' the service 'btcpayserver' will not be started at this point .. it is enabled and will start on next reboot"
  fi

  if [ "${lnd}" = on ]; then
    /home/admin/config.scripts/bonus.btcpayserver.sh write-tls-macaroon
  fi
  if [ "${cl}" = on ]; then
    /home/admin/config.scripts/bonus.btcpayserver.sh cln-lightning-rpc-access
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set BTCPayServer "on"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

########################################
# OFF (deactivate)
########################################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check for second parameter: should data be deleted?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe BTCPay Server Data?" 8 30); then
      deleteData=1
    else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set BTCPayServer "off"

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off btcpay
  fi

  # removing service: btcpay
  sudo systemctl stop btcpayserver
  sudo systemctl disable btcpayserver
  sudo rm /etc/systemd/system/btcpayserver.service

  # removing service: nbxplorer
  sudo systemctl stop nbxplorer
  sudo systemctl disable nbxplorer
  sudo rm /etc/systemd/system/nbxplorer.service

  # clear app config (not user data)
  sudo rm -f /home/btcpay/.nbxplorer/Main/settings.config
  sudo rm -f /home/btcpay/.btcpayserver/Main/settings.config

  # clear nginx config (from btcpaysetdomain)
  sudo rm -f /etc/nginx/sites-enabled/btcpayserver
  sudo rm -f /etc/nginx/sites-available/btcpayserver

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/btcpay_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/btcpay_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/btcpay_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/btcpay_ssl.conf
  sudo rm -f /etc/nginx/sites-available/btcpay_tor.conf
  sudo rm -f /etc/nginx/sites-available/btcpay_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  if [ ${deleteData} -eq 1 ]; then
    echo "# deleting data"
    sudo -u postgres psql -c "drop database nbxplorermainnet;"
    sudo -u postgres psql -c "drop user nbxplorer;"
    sudo -u postgres psql -c "drop database btcpaymainnet;"
    sudo -u postgres psql -c "drop user btcpay;"
    sudo rm -R /mnt/hdd/app-data/.btcpayserver/
  else
    echo "# keeping data"
  fi
  echo "# OK BTCPayServer deactivated."

  echo "# delete the btcpay user home directory"
  sudo userdel -rf btcpay 2>/dev/null

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"

  exit 0
fi

if [ "$1" = "update" ]; then

  # prevent the git error 'detected dubious ownership in repository'
  git config --global --add safe.directory /home/btcpay/NBXplorer
  git config --global --add safe.directory /home/btcpay/btcpayserver

  echo "# Update NBXplorer"
  cd /home/btcpay || exit 1
  cd NBXplorer || exit 1
  # fetch latest master
  if [ "$(sudo -u btcpay git fetch 2>&1 | grep -c "Please tell me who you are")" -gt 0 ]; then
    sudo -u btcpay git config user.email "you@example.com"
    sudo -u btcpay git config user.name "Your Name"
  fi
  sudo -u btcpay git fetch
  # unset $1
  set --
  UPSTREAM=${1:-'@{u}'}
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "$UPSTREAM")

  if [ $LOCAL = $REMOTE ]; then
    TAG=$(git tag | sort -V | tail -1)
    echo "# Up-to-date on version $TAG"
  else
    echo "# Pulling the latest changes..."
    sudo -u btcpay git pull -p
    TAG=$(git tag | sort -V | tail -1)
    echo "# Reset to the latest release tag: $TAG"
    sudo -u btcpay git reset --hard $TAG
    PGPsigner="nicolasdorier"
    PGPpubkeyLink="https://keybase.io/nicolasdorier/pgp_keys.asc"
    PGPpubkeyFingerprint="AB4CFA9895ACA0DBE27F6B346618763EF09186FE"

    sudo -u btcpay /home/admin/config.scripts/blitz.git-verify.sh \
      "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

    echo "# Build NBXplorer $TAG"
    # from the build.sh with path
    sudo systemctl stop nbxplorer
    sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release NBXplorer/NBXplorer.csproj || exit 1

    # whitelist localhost in bitcoind
    if ! sudo grep -Eq "^whitelist=127.0.0.1" /mnt/hdd/bitcoin/bitcoin.conf; then
      echo "whitelist=127.0.0.1" | sudo tee -a /mnt/hdd/bitcoin/bitcoin.conf
      echo "# Restarting bitcoind"
      sudo systemctl restart bitcoind
    fi

    NBXplorerConfig

    sudo systemctl start nbxplorer
    echo "# Updated NBXplorer to $TAG"
  fi

  # always stop to BtcPayConfig
  sudo systemctl stop btcpayserver

  BtcPayConfig

  # always update the btcpayserver.service
  BtcPayService

  echo "# Update BTCPayServer"
  cd /home/btcpay || exit 1
  cd btcpayserver || exit 1
  # fetch latest master
  if [ "$(sudo -u btcpay git fetch 2>&1 | grep -c "Please tell me who you are")" -gt 0 ]; then
    sudo -u btcpay git config user.email "you@example.com"
    sudo -u btcpay git config user.name "Your Name"
  fi
  sudo -u btcpay git fetch
  # unset $1
  set --
  UPSTREAM=${1:-'@{u}'}
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "$UPSTREAM")

  if [ $LOCAL = $REMOTE ]; then
    TAG=$(git tag | grep v1 | sort -V | tail -1)
    echo "# Up-to-date on version $TAG"
  else
    echo "# Pulling latest changes..."
    sudo -u btcpay git pull -p
    TAG=$(git tag | grep v1 | sort -V | tail -1)
    echo "# Reset to the latest release tag: $TAG"
    sudo -u btcpay git reset --hard $TAG
    # PGP verify - disabled for the update
    # https://github.com/rootzoll/raspiblitz/issues/3025
    # sudo -u btcpay /home/admin/config.scripts/blitz.git-verify.sh \
    #  "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
    echo "# Build BTCPayServer $TAG"
    # from the build.sh with path
    sudo systemctl stop btcpayserver
    sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release /home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj || exit 1
    sudo systemctl start btcpayserver
    echo "# Updated BTCPayServer to $TAG"
  fi
  # always start after BtcPayConfig
  sudo systemctl start btcpayserver
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
