#!/bin/bash

# https://github.com/romanz/electrs/blob/master/doc/usage.md
ELECTRSVERSION=v0.8.11

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Electrum Rust Server on or off"
 echo "bonus.electrs.sh status [?showAddress]"
 echo "bonus.electrs.sh [on|off|menu]"
 echo "installs the version $ELECTRSVERSION"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# get local and global internet info
source <(/home/admin/config.scripts/internet.sh status global)

# give status
if [ "$1" = "status" ]; then

  echo "##### STATUS ELECTRS SERVICE"

  if [ "${ElectRS}" = "on" ]; then
    echo "configured=1"
  else
    echo "configured=0"
  fi

  serviceInstalled=$(sudo systemctl status electrs --no-page 2>/dev/null | grep -c "electrs.service - Electrs")
  echo "serviceInstalled=${serviceInstalled}"
  if [ ${serviceInstalled} -eq 0 ]; then
    echo "infoSync='Service not installed'"
  fi

  serviceRunning=$(sudo systemctl status electrs --no-page 2>/dev/null | grep -c "active (running)")
  echo "serviceRunning=${serviceRunning}"
  if [ ${serviceRunning} -eq 1 ]; then

    # Experimental try to get sync Info
    syncedToBlock=$(sudo journalctl -u electrs --no-pager -n2000 | grep "new headers from height" | tail -n 1 | cut -d " " -f 16 | sed 's/[^0-9]*//g')
    blockchainHeight=$(sudo -u bitcoin ${network}-cli getblockchaininfo 2>/dev/null | jq -r '.headers' | sed 's/[^0-9]*//g')
    lastBlockchainHeight=$(($blockchainHeight -1))
    syncProgress=0
    if [ "${syncedToBlock}" != "" ] && [ "${blockchainHeight}" != "" ] && [ "${blockchainHeight}" != "0" ]; then
      syncProgress="$(echo "$syncedToBlock" "$blockchainHeight" | awk '{printf "%.2f", $1 / $2 * 100}')"
    fi
    echo "syncProgress=${syncProgress}%"
    if [ "${syncedToBlock}" = "${blockchainHeight}" ] || [ "${syncedToBlock}" = "${lastBlockchainHeight}" ]; then
      echo "tipSynced=1"
    else
      echo "tipSynced=0"
    fi

    # check if initial sync was done, by setting a file as once electrs is the first time responding on port 50001
    electrumResponding=$(echo '{"jsonrpc":"2.0","method":"server.ping","params":[],"id":"electrs-check"}' | netcat -w 2 127.0.0.1 50001 | grep -c "result")
    if [ ${electrumResponding} -gt 1 ]; then
      electrumResponding=1
    fi
    echo "electrumResponding=${electrumResponding}"

    fileFlagExists=$(sudo ls /mnt/hdd/app-storage/electrs/initial-sync.done 2>/dev/null | grep -c 'initial-sync.done')
    if [ ${fileFlagExists} -eq 0 ] && [ ${electrumResponding} -gt 0 ]; then
      # set file flag for the future
      sudo touch /mnt/hdd/app-storage/electrs/initial-sync.done
      sudo chmod 544 /mnt/hdd/app-storage/electrs/initial-sync.done
      fileFlagExists=1
    fi
    if [ ${fileFlagExists} -eq 0 ]; then
      echo "initialSynced=0"
      echo "infoSync='Building Index (please wait)'"
    else
      echo "initialSynced=1"
    fi

    # check local IPv4 port
    echo "localIP='${localip}'"
    if [ "$2" = "showAddress" ]; then
      echo "publicIP='${cleanip}'"
    fi
    echo "portTCP='50001'"
    localPortRunning=$(sudo netstat -an | grep -c '0.0.0.0:50001')
    echo "localTCPPortActive=${localPortRunning}"

    publicPortRunning=$(nc -z -w6 ${publicip} 50001 2>/dev/null; echo $?)
    if [ "${publicPortRunning}" == "0" ]; then
      # OK looks good - but just means that something is answering on that port
      echo "publicTCPPortAnswering=1"
    else
      # no answer on that port
      echo "publicTCPPortAnswering=0"
    fi
    echo "portHTTP='50002'"
    localPortRunning=$(sudo netstat -an | grep -c '0.0.0.0:50002')
    echo "localHTTPPortActive=${localPortRunning}"
    publicPortRunning=$(nc -z -w6 ${publicip} 50002 2>/dev/null; echo $?)
    if [ "${publicPortRunning}" == "0" ]; then
      # OK looks good - but just means that something is answering on that port
      echo "publicHTTPPortAnswering=1"
    else
      # no answer on that port
      echo "publicHTTPPortAnswering=0"
    fi
    # add TOR info
    if [ "${runBehindTor}" == "on" ]; then
      echo "TORrunning=1"
      if [ "$2" = "showAddress" ]; then
        TORaddress=$(sudo cat /mnt/hdd/tor/electrs/hostname)
        echo "TORaddress='${TORaddress}'"
      fi
    else
      echo "TORrunning=0"
    fi
    # check Nginx
    nginxTest=$(sudo nginx -t 2>&1 | grep -c "test is successful")
    echo "nginxTest=$nginxTest"

  else
    echo "tipSynced=0"
    echo "initialSynced=0"
    echo "electrumResponding=0"
    echo "infoSync='Not running - check: sudo journalctl -u electrs'"
  fi

  exit 0
fi

if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.electrs.sh status showAddress)

  if [ ${serviceInstalled} -eq 0 ]; then
    echo "# FAIL not installed"
    exit 1
  fi

  if [ ${serviceRunning} -eq 0 ]; then
    dialog --title "Electrum Service Not Running" --msgbox "
The electrum system service is not running.
Please check the following debug info.
      " 8 48
    /home/admin/config.scripts/blitz.debug.sh
    echo "Press ENTER to get back to main menu."
    read key
    exit 0
  fi

  if [ ${initialSynced} -eq 0 ]; then
    dialog --title "Electrum Index Not Ready" --msgbox "
Electrum server is still building its index.
Please wait and try again later.
This can take multiple hours.
      " 9 48
    exit 0
  fi
  
  if [ ${nginxTest} -eq 0 ]; then
     dialog --title "Testing nginx.conf has failed" --msgbox "
Nginx is in a failed state. Will attempt to fix.
Try connecting via port 50002 or Tor again once finished.
Check 'sudo nginx -t' for a detailed error message.
      " 9 61
    logFileMissing=$(sudo nginx -t 2>&1 | grep -c "/var/log/nginx/access.log")
    if [ ${logFileMissing} -eq 1 ]; then
      sudo mkdir /var/log/nginx
      sudo systemctl restart nginx
    fi
    /home/admin/config.scripts/blitz.web.sh
    echo "Press ENTER to get back to main menu."
    read key
    exit 0
  fi

  # Options (available without TOR)
  OPTIONS=( \
        CONNECT "How to Connect" \
        INDEX "Delete&Rebuild Index" \
        STATUS "ElectRS Status Info"
	)

  CHOICE=$(whiptail --clear --title "Electrum Rust Server" --menu "menu" 10 50 4 "${OPTIONS[@]}" 2>&1 >/dev/tty)
  clear

  case $CHOICE in
    CONNECT)
    echo "######## How to Connect to Electrum Rust Server #######"
    echo
    echo "Install the Electrum Wallet App on your laptop from:"
    echo "https://electrum.org"
    echo
    echo "On Network Settings > Server menu:"
    echo "- deactivate automatic server selection"
    echo "- as manual server set '${localip}' & '${portHTTP}'"
    echo "- laptop and RaspiBlitz need to be within same local network"
    echo 
    echo "To start directly from laptop terminal use:"
    echo "electrum --oneserver --server ${localip}:${portHTTP}:s"
    if [ ${TORrunning} -eq 1 ]; then
      echo
      echo "The Tor Hidden Service address for electrs is (see LCD for QR code):"
      echo "${TORaddress}"
      echo
      echo "To connect through TOR open the Tor Browser and start with the options:" 
      echo "electrum --oneserver --server ${TORaddress}:50002:s --proxy socks5:127.0.0.1:9150"
      /home/admin/config.scripts/blitz.display.sh qr "${TORaddress}"
    fi
    echo
    echo "For more details check the RaspiBlitz README on ElectRS:"
    echo "https://github.com/rootzoll/raspiblitz"
    echo 
    echo "Press ENTER to get back to main menu."
    read key
    /home/admin/config.scripts/blitz.display.sh hide
    ;;
    STATUS)
    sudo /home/admin/config.scripts/bonus.electrs.sh status
    echo 
    echo "Press ENTER to get back to main menu."
    read key
    ;;
    INDEX)
    echo "######## Delete/Rebuild Index ########"
    echo "# stopping service"
    sudo systemctl stop electrs
    echo "# deleting index"
    sudo rm -r /mnt/hdd/app-storage/electrs/db
    sudo rm /mnt/hdd/app-storage/electrs/initial-sync.done 2>/dev/null
    echo "# starting service"
    sudo systemctl start electrs
    echo "# ok"
    echo 
    echo "Press ENTER to get back to main menu."
    read key
    ;;
  esac

  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^ElectRS=" /mnt/hdd/raspiblitz.conf; then
  echo "ElectRS=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop service
echo "# Making sure services are not running"
sudo systemctl stop electrs 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# INSTALL ELECTRS"

  isInstalled=$(sudo ls /etc/systemd/system/electrs.service 2>/dev/null | grep -c 'electrs.service')
  if [ ${isInstalled} -eq 0 ]; then

    #cleanup
    sudo rm -f /home/electrs/.electrs/config.toml 

    echo
    echo "# Creating the electrs user"
    echo
    sudo adduser --disabled-password --gecos "" electrs
    cd /home/electrs

    echo
    echo "# Installing Rust"
    echo
    # https://github.com/romanz/electrs/blob/master/doc/usage.md#build-dependencies
    #sudo -u electrs curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u electrs sh -s -- --default-toolchain 1.39.0 -y
    sudo apt update
    sudo apt install -y cargo
    sudo apt install -y clang cmake build-essential  # for building 'rust-rocksdb'

    echo
    echo "# Downloading and building electrs $ELECTRSVERSION. This will take ~30 minutes" # ~22 min on an Odroid XU4
    echo
    sudo -u electrs git clone https://github.com/romanz/electrs
    cd /home/electrs/electrs || exit 1 
    sudo -u electrs git reset --hard $ELECTRSVERSION
    sudo -u electrs cargo build --release || exit 1 

    echo
    echo "# The electrs database will be built in /mnt/hdd/app-storage/electrs/db. Takes ~18 hours and ~50Gb diskspace"
    echo
    # move old-database if present
    if [ -d "/mnt/hdd/electrs/db" ]; then
      echo "Moving existing ElectRS index to /mnt/hdd/app-storage/electrs..."
      sudo mv -f /mnt/hdd/electrs /mnt/hdd/app-storage/
    fi

    sudo mkdir /mnt/hdd/app-storage/electrs 2>/dev/null
    sudo chown -R electrs:electrs /mnt/hdd/app-storage/electrs

    echo
    echo "# Getting RPC credentials from the bitcoin.conf"
    #read PASSWORD_B
    RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    echo "# Done"

    echo
    echo "# Generating electrs.toml setting file with the RPC passwords"
    echo
    # generate setting file: https://github.com/romanz/electrs/issues/170#issuecomment-530080134
    # https://github.com/romanz/electrs/blob/master/doc/usage.md#configuration-files-and-environment-variables
    sudo -u electrs mkdir /home/electrs/.electrs 2>/dev/null
    echo "
verbose = 4
timestamp = true
jsonrpc_import = true
db_dir = \"/mnt/hdd/app-storage/electrs/db\"
auth = \"$RPC_USER:$PASSWORD_B\"
# allow BTC-RPC-explorer show tx-s for addresses with a history of more than 100
txid_limit = 1000
# https://github.com/Stadicus/RaspiBolt/issues/646
wait_duration_secs = 20
server_banner = \"Welcome to electrs $ELECTRSVERSION - the Electrum Rust Server on your RaspiBlitz\"
" | sudo tee /home/electrs/.electrs/config.toml
    sudo chmod 600 /home/electrs/.electrs/config.toml
    sudo chown electrs:electrs /home/electrs/.electrs/config.toml

    echo
    echo "# Checking for config.toml"
    echo
    if [ ! -f "/home/electrs/.electrs/config.toml" ]
        then
            echo "Failed to create config.toml"
            exit 1
        else
            echo "OK"
    fi

    echo
    echo "# Setting up the nginx.conf"
    echo
    isElectrs=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'upstream electrs')
    if [ ${isElectrs} -gt 0 ]; then
            echo "electrs is already configured with Nginx. To edit manually run \`sudo nano /etc/nginx/nginx.conf\`"

    elif [ ${isElectrs} -eq 0 ]; then

            isStream=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'stream {')
            if [ ${isStream} -eq 0 ]; then

            echo "
stream {
        upstream electrs {
                server 127.0.0.1:50001;
        }
        server {
                listen 50002 ssl;
                proxy_pass electrs;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-electrs:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

            elif [ ${isStream} -eq 1 ]; then
                    sudo truncate -s-2 /etc/nginx/nginx.conf
                    echo "
        upstream electrs {
                server 127.0.0.1:50001;
        }
        server {
                listen 50002 ssl;
                proxy_pass electrs;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-electrs:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

            elif [ ${isStream} -gt 1 ]; then
                    echo " Too many \`stream\` commands in nginx.conf. Please edit manually: \`sudo nano /etc/nginx/nginx.conf\` and retry"
                    exit 1
            fi
    fi

    sudo systemctl restart nginx

    echo
    echo "# Open ports 50001 and 5002 on UFW "
    echo
    sudo ufw allow 50001 comment 'electrs TCP'
    sudo ufw allow 50002 comment 'electrs SSL'

    echo
    echo "# Installing the systemd service"
    echo
    # sudo nano /etc/systemd/system/electrs.service 
    echo "
[Unit]
Description=Electrs
After=lnd.service

[Service]
WorkingDirectory=/home/electrs/electrs
ExecStart=/home/electrs/electrs/target/release/electrs --index-batch-size=10 --electrum-rpc-addr=\"0.0.0.0:50001\"
User=electrs
Group=electrs
Type=simple
TimeoutSec=60
Restart=always
RestartSec=60

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
    " | sudo tee -a /etc/systemd/system/electrs.service
    sudo systemctl enable electrs
    # manual start:
    # sudo -u electrs /home/electrs/.cargo/bin/cargo run --release -- --index-batch-size=10 --electrum-rpc-addr="0.0.0.0:50001"
  else 
    echo "# ElectRS is already installed."
  fi

  # setting value in raspiblitz config
  sudo sed -i "s/^ElectRS=.*/ElectRS=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service for electrs if Tor active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh electrs 50002 50002 50001 50001
  fi

  ## Enable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  # see /home/admin/config.scripts/bonus.electrsexplorer.sh
  # run every 10 min by _background.sh
  
  echo
  echo "# To connect through SSL from outside of the local network make sure the port 50002 is forwarded on the router"
  echo
  
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspiblitz config
  sudo sed -i "s/^ElectRS=.*/ElectRS=off/g" /mnt/hdd/raspiblitz.conf

  # if second parameter is "deleteindex"
  if [ "$2" == "deleteindex" ]; then
    echo "# deleting electrum index"
    sudo rm -rf /mnt/hdd/app-storage/electrs/
  fi

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh off electrs
  fi

  isInstalled=$(sudo ls /etc/systemd/system/electrs.service 2>/dev/null | grep -c 'electrs.service')
  if [ ${isInstalled} -eq 1 ]; then

    echo "# REMOVING ELECTRS"
    sudo systemctl disable electrs
    sudo rm /etc/systemd/system/electrs.service
    # delete user and home directory
    sudo userdel -rf electrs 
    # close ports on firewall
    sudo ufw deny 50001
    sudo ufw deny 50002 
    echo "# OK ElectRS removed."
    
    ## Disable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
    /home/admin/config.scripts/bonus.electrsexplorer.sh
  else 
    echo "# ElectRS is not installed."
  fi
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
