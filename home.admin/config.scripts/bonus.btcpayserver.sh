#!/bin/bash

# Based on: https://gist.github.com/normandmickey/3f10fc077d15345fb469034e3697d0d0

# https://github.com/dgarage/NBXplorer/releases
NBXplorerVersion="v2.2.8"
# https://github.com/btcpayserver/btcpayserver/releases
BTCPayVersion="v1.2.3"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script to switch BTCPay Server on or off"
  echo "# bonus.btcpayserver.sh [on|off|menu|write-tls-macaroon]"
  echo "# installs BTCPayServer $BTCPayVersion with NBXplorer $NBXplorerVersion"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf
# get cpu architecture
source /home/admin/raspiblitz.info

if [ "$1" = "status" ]; then

  if [ "${BTCPayServer}" = "on" ]; then

    echo "switchedon=1"
    isInstalled=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
    echo "installed=${isInstalled}"

    localIP=$(hostname -I | awk '{print $1}')
    echo "localIP='${localIP}'"
    echo "httpsPort='23001'"
    echo "publicIP='${publicIP}'"

    # check for LetsEncryptDomain for DynDns
    error=""
    source <(sudo /home/admin/config.scripts/blitz.subscriptions.ip2tor.py ip-by-tor $publicIP)
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
    echo "installed=0"
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
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    text="${text}\n
TOR Browser Hidden Service address (see the QR onLCD):
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

  /home/admin/config.scripts/blitz.display.sh hide
  echo "# please wait ..."
  exit 0
fi

# add default values to raspi config if needed
if ! grep -Eq "^BTCPayServer=" /mnt/hdd/raspiblitz.conf; then
  echo "BTCPayServer=off" >> /mnt/hdd/raspiblitz.conf
fi
if ! grep -Eq "^BTCPayDomain=" /mnt/hdd/raspiblitz.conf; then
  echo "BTCPayDomain=off" >> /mnt/hdd/raspiblitz.conf
fi

# write-tls-macaroon
if [ "$1" = "write-tls-macaroon" ]; then

  echo "# make sure btcpay is member of lndadmin"
  sudo /usr/sbin/usermod --append --groups lndadmin btcpay

  echo "# make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/btcpay/.lnd" ]]; then
    sudo rm -rf "/home/btcpay/.lnd"                          # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/btcpay/.lnd"  # and create symlink
  fi

  # copy admin macaroon
  echo "# extra symlink to admin.macaroon for btcpay"
  if ! [[ -L "/home/btcpay/admin.macaroon" ]]; then
    sudo ln -s "/home/btcpay/.lnd/data/chain/${network}/${chain}net/admin.macaroon" "/home/btcpay/admin.macaroon"
  fi

  # set thumbprint
  FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -inform pem -in /home/btcpay/.lnd/tls.cert | cut -d"=" -f2)
  doesNetworkEntryAlreadyExists=$(sudo cat /home/btcpay/.btcpayserver/Main/settings.config | grep -c '^network=')
  if [ ${doesNetworkEntryAlreadyExists} -eq 0 ]; then
    echo "# setting the LND TLS thumbprint for BTCPay"
    echo "
### Global settings ###
network=mainnet

### Server settings ###
port=23000
bind=127.0.0.1
externalurl=https://$BTCPayDomain

### NBXplorer settings ###
BTC.explorer.url=http://127.0.0.1:24444/
BTC.lightning=type=lnd-rest;server=https://127.0.0.1:8080/;macaroonfilepath=/home/btcpay/admin.macaroon;certthumbprint=$FINGERPRINT
" | sudo -u btcpay tee -a /home/btcpay/.btcpayserver/Main/settings.config
  else
    echo "# setting new LND TLS thumbprint for BTCPay"
    s="BTC.lightning=type=lnd-rest\;server=https\://127.0.0.1:8080/\;macaroonfilepath=/home/btcpay/admin.macaroon\;"
    sudo -u btcpay sed -i "s|^${s}certthumbprint=.*|${s}certthumbprint=$FINGERPRINT|g" /home/btcpay/.btcpayserver/Main/settings.config
  fi

  if [ "${state}" == "ready" ]; then
    sudo systemctl restart btcpayserver
  fi
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# INSTALL BTCPAYSERVER"

  ##################
  # NGINX
  ##################
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

  # stop services
  echo "# making sure services are not running"
  sudo systemctl stop nbxplorer 2>/dev/null
  sudo systemctl stop btcpayserver 2>/dev/null

  isInstalled=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ ${isInstalled} -eq 0 ]; then
    # create btcpay user
    sudo adduser --disabled-password --gecos "" btcpay  || exit 1
    cd /home/btcpay || exit 1

    # store BTCpay data on HDD
    sudo mkdir /mnt/hdd/app-data/.btcpayserver 2>/dev/null

    # move old btcpay data to app-data
    sudo mv -f /mnt/hdd/.btcpayserver/* /mnt/hdd/app-data/.btcpayserver/ 2>/dev/null
    sudo rm -rf /mnt/hdd/.btcpayserver 2>/dev/null

    sudo chown -R btcpay:btcpay /mnt/hdd/app-data/.btcpayserver
    sudo ln -s /mnt/hdd/app-data/.btcpayserver /home/btcpay/ 2>/dev/null
    sudo chown -R btcpay:btcpay /home/btcpay/.btcpayserver

    echo
    echo "# Installing .NET"
    echo
    # https://dotnet.microsoft.com/download/dotnet-core/3.1
    # dependencies
    sudo apt-get -y install libunwind8 gettext libssl1.0

    if [ "${cpu}" = "arm" ]; then
      binaryVersion="arm"
      dotNetdirectLink="https://download.visualstudio.microsoft.com/download/pr/40edd52f-b1ca-4f0c-8d50-34433202ce9d/2b8f5b881c239a706f271f010e56159c/dotnet-sdk-3.1.413-linux-arm.tar.gz"
      dotNetChecksum="31f395b1e48e9ba53d4dc63db7ff1ea38bdcb612a1d54b483cde22a009c48fbae0303779f42cee32db0e51bd953c8abfdaa1620a43a7fd84e1f8e937b6675d59"
    elif [ "${cpu}" = "aarch64" ]; then
      binaryVersion="arm64"
      dotNetdirectLink="https://download.visualstudio.microsoft.com/download/pr/dfd0ad22-3e47-432f-9aa1-f65b11a2ced2/d096c5d1561732c1658543fa8fb7a31f/dotnet-sdk-3.1.413-linux-arm64.tar.gz"
      dotNetChecksum="39f198f07577faf81f09ca621fb749d5aac38fc05e7e6bd6226009679abc7d001454068430ddb34b320901955f42de3951e2707e01bce825b5216df2bc0c8eca"
    elif [ "${cpu}" = "x86_64" ]; then
      binaryVersion="x64"
      dotNetdirectLink="https://download.visualstudio.microsoft.com/download/pr/70d12135-d65f-4f4c-9d96-a6ac0251fb1b/57856b7654e338027cfb53552b2c4d46/dotnet-sdk-3.1.413-linux-x64.tar.gz"
      dotNetChecksum="2a0824f11aba0b79d3f9a36af0395649bc9b4137e61b240a48dccb671df0a5b8c2086054f8e495430b7ed6c344bb3f27ac3dfda5967d863718a6dadeca951a83"
    fi

    dotNetName="dotnet-sdk-3.1.413-linux-${binaryVersion}.tar.gz"
    sudo rm /home/btcpay/${dotnetName} 2>/dev/null
    sudo -u btcpay wget "${dotNetdirectLink}"
    # check binary is was not manipulated (checksum test)
    actualChecksum=$(sha512sum /home/btcpay/${dotNetName} | cut -d " " -f1)
    if [ "${actualChecksum}" != "${dotNetChecksum}" ]; then
      echo "# !!! FAIL !!! Downloaded ${dotNetName} not matching SHA512 checksum: ${dotNetChecksum}"
      exit 1
    fi

    sudo -u btcpay mkdir /home/btcpay/dotnet
    sudo -u btcpay tar -xvf ${dotNetName} -C /home/btcpay/dotnet
    sudo rm -f *.tar.gz*

    # opt out of telemetry
    echo "DOTNET_CLI_TELEMETRY_OPTOUT=1" | sudo tee -a /etc/environment

    # make .NET accessible and add to PATH
    sudo ln -s /home/btcpay/dotnet /usr/share
    export PATH=$PATH:/usr/share
    if [ $(cat /etc/profile | grep -c "/usr/share") -eq 0 ]; then
      sudo bash -c "echo 'PATH=\$PATH:/usr/share' >> /etc/profile"
    fi
    export DOTNET_ROOT=/home/btcpay/dotnet
    export PATH=$PATH:/home/btcpay/dotnet
    if [ $(cat /etc/profile | grep -c "DOTNET_ROOT") -eq 0 ]; then
      sudo bash -c "echo 'DOTNET_ROOT=/home/btcpay/dotnet' >> /etc/profile"
      sudo bash -c "echo 'PATH=\$PATH:/home/btcpay/dotnet' >> /etc/profile"
    fi
    sudo -u btcpay /home/btcpay/dotnet/dotnet --info

    # NBXplorer
    echo
    echo "# Install NBXplorer"
    echo
    cd /home/btcpay || exit 1
    echo "# Download the NBXplorer source code ..."
    sudo -u btcpay git clone https://github.com/dgarage/NBXplorer.git 2>/dev/null
    cd NBXplorer || exit 1
    sudo -u btcpay git reset --hard $NBXplorerVersion
    echo "# Build NBXplorer ..."
    # from the build.sh with path
    sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release NBXplorer/NBXplorer.csproj
    # see the configuration options with:
    # sudo -u btcpay /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release -p "NBXplorer/NBXplorer.csproj" -c /home/btcpay/.nbxplorer/Main/settings.config -h
    # run manually to debug:
    # sudo -u btcpay /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release -p "NBXplorer/NBXplorer.csproj" -c /home/btcpay/.nbxplorer/Main/settings.config --network=mainnet -- $@
    echo "# create the nbxplorer.service"
    echo "
[Unit]
Description=NBXplorer daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
WorkingDirectory=/home/btcpay/NBXplorer
ExecStart=/home/btcpay/dotnet/dotnet run --no-launch-profile --no-build \
 -c Release -p \"NBXplorer/NBXplorer.csproj\" -- \$@
User=btcpay
Group=btcpay
Type=simple
PIDFile=/run/nbxplorer/nbxplorer.pid
Restart=on-failure

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
      while [ ! -f "/home/btcpay/.nbxplorer/Main/settings.config" ]
       do
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

    echo
    echo "# getting RPC credentials from the bitcoin.conf"
    RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    sudo -u btcpay mkdir -p /home/btcpay/.nbxplorer/Main
    echo "\
btc.rpc.user=$RPC_USER
btc.rpc.password=$PASSWORD_B
" | sudo tee /home/btcpay/.nbxplorer/Main/settings.config
    sudo chmod 600 /home/btcpay/.nbxplorer/Main/settings.config
    sudo chown btcpay:btcpay /home/btcpay/.nbxplorer/Main/settings.config

    if [ "${state}" == "ready" ]; then
      sudo systemctl restart nbxplorer
    fi

    # BTCPayServer
    echo
    echo "# Install BTCPayServer"
    echo
    cd /home/btcpay || exit 1
    echo "# Download the BTCPayServer source code ..."
    sudo -u btcpay git clone https://github.com/btcpayserver/btcpayserver.git 2>/dev/null
    cd btcpayserver
    sudo -u btcpay git reset --hard $BTCPayVersion
    echo "# Build BTCPayServer ..."
    # from the build.sh with path
    sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release /home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj

    # see the configuration options with:
    # sudo -u btcpay /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release -p "/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj" -- -h
    # run manually to debug:
    # sudo -u btcpay /home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release -p "/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj" -- --sqlitefile=sqllite.db --network=mainnet
    echo "# create the btcpayserver.service"
    echo "
[Unit]
Description=BtcPayServer daemon
Requires=nbxplorer.service
After=nbxplorer.service

[Service]
ExecStart=/home/btcpay/dotnet/dotnet run --no-launch-profile --no-build \
 -c Release -p \"/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj\" \
 -- --sqlitefile=sqllite.db
User=btcpay
Group=btcpay
Type=simple
PIDFile=/run/btcpayserver/btcpayserver.pid
Restart=on-failure

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/btcpayserver.service
  sudo systemctl enable btcpayserver

    if [ "${state}" == "ready" ]; then
      echo "# Starting btcpayserver"
      sudo systemctl start btcpayserver
      echo "# Checking for btcpayserver config"
      while [ ! -f "/home/btcpay/.btcpayserver/Main/settings.config" ]; do
        echo "# Waiting for btcpayserver to start - CTRL+C to abort"
        sleep 10
        hasFailed=$(sudo systemctl status btcpayserver  | grep -c "Active: failed")
        if [ ${hasFailed} -eq 1 ]; then
          echo "# seems like starting btcpayserver  service has failed - see: systemctl status btcpayserver"
          echo "# maybe report here: https://github.com/rootzoll/raspiblitz/issues/214"
        fi
      done
    else
      echo "# Because the system is not 'ready' the service 'btcpayserver' will not be started at this point .. its enabled and will start on next reboot"
    fi

    sudo -u btcpay mkdir -p /home/btcpay/.btcpayserver/Main/
    /home/admin/config.scripts/bonus.btcpayserver.sh write-tls-macaroon

  else
    echo "# BTCPay Server is already installed."
    if [ "${state}" == "ready" ]; then
      # start service
      echo "# start service"
      sudo systemctl start nbxplorer 2>/dev/null
      sudo systemctl start btcpayserver 2>/dev/null
    fi
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCPayServer=.*/BTCPayServer=on/g" /mnt/hdd/raspiblitz.conf
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
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe BTCPay Server Data?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCPayServer=.*/BTCPayServer=off/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off btcpay
  fi

  isInstalled=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING BTCPAYSERVER, NBXPLORER and .NET ***"
    # removing services
    # btcpay
    sudo systemctl stop btcpayserver
    sudo systemctl disable btcpayserver
    sudo rm /etc/systemd/system/btcpayserver.service
    # nbxplorer
    sudo systemctl stop nbxplorer
    sudo systemctl disable nbxplorer
    sudo rm /etc/systemd/system/nbxplorer.service
    # clear dotnet cache
    /home/btcpay/dotnet/dotnet nuget locals all --clear
    sudo rm -rf /tmp/NuGetScratch
    # remove dotnet
    sudo rm -rf /usr/share/dotnet
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
    # nuke user
    sudo userdel -rf btcpay 2>/dev/null
    if [ ${deleteData} -eq 1 ]; then
      echo "# deleting data"
      sudo rm -R /mnt/hdd/app-data/.btcpayserver/
    else
      echo "# keeping data"
    fi
    echo "# OK BTCPayServer removed."
  else
    echo "# BTCPayServer is not installed."
  fi
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
