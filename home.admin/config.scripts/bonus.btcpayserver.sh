#!/bin/bash

# Based on: https://gist.github.com/normandmickey/3f10fc077d15345fb469034e3697d0d0 

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch BTCPay Server on or off"
  echo "bonus.btcpayserver.sh [on|off]"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/btcpay/hostname 2>/dev/null)

  if [ "${BTCPayDomain}" == "localhost" ]; then

    # TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " BTCPay Server (TOR) " --msgbox "Open the following URL in your local web browser:
https://${localip}
You will need to accept the selfsigned certificate in the browser.\n
Hidden Service address for Tor Browser (see the LCD for a QRcode):
${toraddress}
" 12 70
    /home/admin/config.scripts/blitz.lcd.sh hide
  else

    # IP + Domain
    whiptail --title " BTCPay Server (Domain) " --msgbox "Open the following URL in your local web browser:
https://${BTCPayDomain}\n
For details or troubleshoot check for 'BTCPay'
in README of https://github.com/rootzoll/raspiblitz
" 11 67
  fi

  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^BTCPayServer=" /mnt/hdd/raspiblitz.conf; then
  echo "BTCPayServer=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop nbxplorer 2>/dev/null
sudo systemctl stop btcpayserver 2>/dev/null
  
# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL BTCPAYSERVER ***"

  # setting up nginx and the SSL certificate    
  /home/admin/config.scripts/bonus.btcpaysetdomain.sh
  errorOnInstall=$?
  if [ ${errorOnInstall} -eq 1 ]; then
   echo "exiting as user cancelled BTCPayServer installation"  
   exit 1
  fi 
  # check for $BTCPayDomain
  source /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ ${isInstalled} -eq 0 ]; then
    # create btcpay user
    sudo adduser --disabled-password --gecos "" btcpay 2>/dev/null
    cd /home/btcpay

    # store BTCpay data on HDD
    sudo mkdir /mnt/hdd/app-data/.btcpayserver 2>/dev/null

    # move old btcpay data to app-data
    sudo mv -f /mnt/hdd/.btcpayserver/* /mnt/hdd/app-data/.btcpayserver/ 2>/dev/null
    sudo rm -rf /mnt/hdd/.btcpayserver 2>/dev/null

    sudo chown -R btcpay:btcpay /mnt/hdd/app-data/.btcpayserver
    sudo ln -s /mnt/hdd/app-data/.btcpayserver /home/btcpay/ 2>/dev/null
    sudo chown -R btcpay:btcpay /home/btcpay/.btcpayserver

    echo ""
    echo "***"
    echo "Installing .NET"
    echo "***"
    echo ""
    
    # download dotnet-sdk
    # https://dotnet.microsoft.com/download/dotnet-core/3.1
    sudo apt-get -y install libunwind8 gettext libssl1.0
    dotnetName="dotnet-sdk-3.1.101-linux-arm.tar.gz"
    sudo rm /home/btcpay/${dotnetName} 2>/dev/null
    sudo -u btcpay wget "https://download.visualstudio.microsoft.com/download/pr/d52fa156-1555-41d5-a5eb-234305fbd470/173cddb039d613c8f007c9f74371f8bb/${dotnetName}"
    # check binary is was not manipulated (checksum test)
    binaryChecksum="bd68786e16d59b18096658ccab2a662f35cd047065a6c87a9c6790a893a580a6aa81b1338360087e58d5b5e5fdca08269936281e41a7a7e7051667efb738a613"
    actualChecksum=$(sha512sum /home/btcpay/${dotnetName} | cut -d " " -f1)
    if [ "${actualChecksum}" != "${binaryChecksum}" ]; then
      echo "!!! FAIL !!! Downloaded ${dotnetName} not matching SHA512 checksum: ${binaryChecksum}"
      exit 1
    fi
  
    # download aspnetcore-runtime
    aspnetcoreName="aspnetcore-runtime-3.1.1-linux-arm.tar.gz"
    sudo rm /home/btcpay/${aspnetcoreName} 2>/dev/null
    sudo -u btcpay wget "https://download.visualstudio.microsoft.com/download/pr/da60c9fc-c329-42d6-afaf-b8ef2bbadcf3/14655b5928319349e78da3327874592a/${aspnetcoreName}"
    # check binary is was not manipulated (checksum test)
    binaryChecksum="5171cdd232f02fbd41abee893ebe3722fe442436bef9792fec9c687a746357d22b4499aa6f0a9e35285bc04783c54e400810acb365c5a1c3401f23a65e6b062f"
    actualChecksum=$(sha512sum /home/btcpay/${aspnetcoreName} | cut -d " " -f1)
    if [ "${actualChecksum}" != "${binaryChecksum}" ]; then
      echo "!!! FAIL !!! Downloaded ${aspnetcoreName} not matching SHA512 checksum: ${binaryChecksum}"
      exit 1
    fi
  
    sudo -u btcpay mkdir /home/btcpay/dotnet
    sudo -u btcpay tar -xvf ${dotnetName} -C /home/btcpay/dotnet
    sudo -u btcpay tar -xvf ${aspnetcoreName} -C /home/btcpay/dotnet
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
    echo ""
    echo "***"
    echo "Install NBXplorer"
    echo "***"
    echo ""
        
    cd /home/btcpay
    echo "Downloading NBXplorer source code.."
    sudo -u btcpay git clone https://github.com/dgarage/NBXplorer.git 2>/dev/null
    cd NBXplorer
    # check https://github.com/dgarage/NBXplorer/releases
    sudo -u btcpay git reset --hard v2.1.7
    # from the build.sh with path
    sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release NBXplorer/NBXplorer.csproj

    
    # create nbxplorer service
    echo "
[Unit]
Description=NBXplorer daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
ExecStart=/home/btcpay/dotnet/dotnet \"/home/btcpay/NBXplorer/NBXplorer/bin/Release/netcoreapp3.1/NBXplorer.dll\" -c /home/btcpay/.nbxplorer/Main/settings.config
User=btcpay
Group=btcpay
Type=simple
PIDFile=/run/nbxplorer/nbxplorer.pid
Restart=on-failure

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
    sudo systemctl start nbxplorer
    
    echo "Checking for nbxplorer config"
    while [ ! -f "/home/btcpay/.nbxplorer/Main/settings.config" ]
      do
        echo "Waiting for nbxplorer to start - CTRL+C to abort"
        sleep 10
        hasFailed=$(sudo systemctl status nbxplorer | grep -c "Active: failed")
        if [ ${hasFailed} -eq 1 ]; then
          echo "seems like starting nbxplorer service has failed - see: systemctl status nbxplorer"
          echo "maybe report here: https://github.com/rootzoll/raspiblitz/issues/214"
        fi
    done
    
    echo ""
    echo "***"
    echo "getting RPC credentials from the bitcoin.conf"
    RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    sudo mv /home/btcpay/.nbxplorer/Main/settings.config /home/btcpay/.nbxplorer/Main/settings.config.backup
    touch /home/admin/settings.config
    sudo chmod 600 /home/admin/settings.config || exit 1
    cat >> /home/admin/settings.config <<EOF
btc.rpc.user=raspibolt
btc.rpc.password=$PASSWORD_B
EOF

    sudo mv /home/admin/settings.config /home/btcpay/.nbxplorer/Main/settings.config
    sudo chown btcpay:btcpay /home/btcpay/.nbxplorer/Main/settings.config
    sudo systemctl restart nbxplorer
    
    # BTCPayServer
    echo ""
    echo "***"
    echo "Install BTCPayServer"
    echo "***"
    echo ""
    
    cd /home/btcpay
    echo "Downloading BTCPayServer source code.."
    sudo -u btcpay git clone https://github.com/btcpayserver/btcpayserver.git 2>/dev/null
    cd btcpayserver
    # check https://github.com/btcpayserver/btcpayserver/releases 
    sudo -u btcpay git reset --hard v1.0.3.153 
    # from the build.sh with path
    sudo -u btcpay /home/btcpay/dotnet/dotnet build -c Release /home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj   
    
    # create btcpayserver service
    echo "
[Unit]
Description=BtcPayServer daemon
Requires=btcpayserver.service
After=nbxplorer.service

[Service]
ExecStart=/home/btcpay/dotnet/dotnet run --no-launch-profile --no-build -c Release -p \"/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj\" -- \$@
User=btcpay
Group=btcpay
Type=simple
PIDFile=/run/btcpayserver/btcpayserver.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/btcpayserver.service
  
    sudo systemctl daemon-reload
    sudo systemctl enable btcpayserver
    sudo systemctl start btcpayserver
    
    echo "Checking for btcpayserver config"
    while [ ! -f "/home/btcpay/.btcpayserver/Main/settings.config" ]
      do
        echo "Waiting for btcpayserver to start - CTRL+C to abort"
        sleep 10
        hasFailed=$(sudo systemctl status btcpayserver  | grep -c "Active: failed")
        if [ ${hasFailed} -eq 1 ]; then
          echo "seems like starting btcpayserver  service has failed - see: systemctl status btcpayserver"
          echo "maybe report here: https://github.com/rootzoll/raspiblitz/issues/214"
        fi
    done

    # set thumbprint
    FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -inform pem -in /home/admin/.lnd/tls.cert | cut -c 20-)
    sudo cp /mnt/hdd/lnd/data/chain/bitcoin/mainnet/admin.macaroon /home/btcpay/admin.macaroon
    sudo chown btcpay:btcpay /home/btcpay/admin.macaroon
    sudo chmod 600 /home/btcpay/admin.macaroon
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

    sudo systemctl restart btcpayserver
  else 
    echo "BTCPay Server is already installed."
    # start service
    echo "start service"
    sudo systemctl start nbxplorer 2>/dev/null
    sudo systemctl start btcpayserver 2>/dev/null
  fi 

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCPayServer=.*/BTCPayServer=on/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCPayServer=.*/BTCPayServer=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING BTCPAYSERVER, NBXPLORER and .NET ***"
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
    sudo -u btcpay dotnet nuget locals all --clear
    sudo rm -rf /tmp/NuGetScratch
    # remove dotnet
    sudo rm -f /home/btcpay/dotnet-sdk*
    sudo rm -f /home/btcpay/aspnetcore*
    sudo rm -rf /home/btcpay/dotnet
    sudo rm -rf /usr/share/dotnet
    # clear app config (not user data)
    sudo rm -f /home/btcpay/.nbxplorer/Main/settings.config
    sudo rm -f /home/btcpay/.btcpayserver/Main/settings.config
    # clear nginx config
    sudo rm -f /etc/nginx/sites-enabled/btcpayserver
    sudo rm -f /etc/nginx/sites-available/btcpayserver
    echo "OK BTCPayServer removed."
  else 
    echo "BTCPayServer is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
