#!/bin/bash

# https://github.com/cculianu/Fulcrum/releases
fulcrumVersion="1.11.1"

portTCP="50021"
portSSL="50022"
portAdmin="8021"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the Fulcrum electrum server on, off or update to the latest release"
  echo "bonus.fulcrum.sh [on|off|update]"
  echo "bonus.fulcrum.sh getinfo -> FulcrumAdmin getinfo output"
  echo "bonus.fulcrum.sh status -> don't call in loops"
  echo "bonus.fulcrum.sh status-sync"
  echo "installs the version $fulcrumVersion"
  exit 1
fi

if [ "$1" = "status-sync" ] || [ "$1" = "status" ] || [ "$1" = "getinfo" ]; then
  # Attempt to get info from FulcrumAdmin, redirecting stderr to stdout to capture any error messages
  getInfoOutput=$(/home/fulcrum/FulcrumAdmin -p $portAdmin getinfo 2>&1)
fi

if [ "$1" = "getinfo" ]; then
  echo "$getInfoOutput"
  exit 0
fi

if [ "$1" = "status-sync" ] || [ "$1" = "status" ]; then
  # Check if the command was successful or if it failed with "Connection refused"
  if ! echo "$getInfoOutput" | jq -r '.version' 2>/dev/null; then
    # Command failed, make getInfo empty
    getInfo=""
  else
    # Command succeeded, store the output in getInfo
    getInfo="$getInfoOutput"
  fi
  if systemctl is-active fulcrum >/dev/null; then
    serviceRunning=1
  else
    serviceRunning=0
  fi
fi

if [ "$1" = "status" ]; then
  echo "##### STATUS FULCRUM SERVICE"
  fulcrumVersion=$(/home/fulcrum/Fulcrum -v 2>/dev/null | grep -oP 'Fulcrum \K\d+\.\d+\.\d+')
  echo "version='${fulcrumVersion}'"

  source /mnt/hdd/raspiblitz.conf
  if [ "${fulcrum}" = "on" ]; then
    echo "configured=1"
  else
    echo "configured=0"
  fi

  serviceInstalled=$(sudo systemctl status fulcrum --no-page 2>/dev/null | grep -c "fulcrum.service - Fulcrum")
  echo "serviceInstalled=${serviceInstalled}"
  if [ ${serviceInstalled} -eq 0 ]; then
    echo "infoSync='Service not installed'"
  fi

  if [ ${serviceRunning} -eq 1 ]; then
    # get local and global internet info
    source <(/home/admin/config.scripts/internet.sh status global)
    # check local IPv4 port
    echo "localIP='${localip}'"
    echo "publicIP='${cleanip}'"
    echo "portTCP='50021'"
    localPortRunning=$(sudo netstat -an | grep -c '0.0.0.0:50021')
    echo "localTCPPortActive=${localPortRunning}"

    publicPortRunning=$(
      nc -z -w6 ${publicip} 50021 2>/dev/null
      echo $?
    )
    if [ "${publicPortRunning}" == "0" ]; then
      # OK looks good - but just means that something is answering on that port
      echo "publicTCPPortAnswering=1"
    else
      # no answer on that port
      echo "publicTCPPortAnswering=0"
    fi
    echo "portSSL='50022'"
    localPortRunning=$(sudo netstat -an | grep -c '0.0.0.0:50022')
    echo "localHTTPPortActive=${localPortRunning}"
    publicPortRunning=$(
      nc -z -w6 ${publicip} 50022 2>/dev/null
      echo $?
    )
    if [ "${publicPortRunning}" == "0" ]; then
      # OK looks good - but just means that something is answering on that port
      echo "publicHTTPPortAnswering=1"
    else
      # no answer on that port
      echo "publicHTTPPortAnswering=0"
    fi

    # add Tor info
    if [ "${runBehindTor}" == "on" ]; then
      echo "TorRunning=1"
      if [ "$2" = "showAddress" ]; then
        TORaddress=$(sudo cat /mnt/hdd/tor/fulcrum/hostname)
        echo "TORaddress='${TORaddress}'"
      fi
    else
      echo "TorRunning=0"
    fi
    # check Nginx
    nginxTest=$(sudo nginx -t 2>&1 | grep -c "test is successful")
    echo "nginxTest=$nginxTest"
  fi
fi

# give sync-status (can be called regularly)
if [ "$1" = "status-sync" ] || [ "$1" = "status" ]; then
  echo "serviceRunning=${serviceRunning}"
  if [ ${serviceRunning} -eq 1 ]; then

    if [ "$getInfo" = "" ]; then
      electrumResponding=0
    else
      electrumResponding=1
    fi
    echo "electrumResponding=${electrumResponding}"

    # sync info
    source <(/home/admin/_cache.sh get btc_mainnet_blocks_headers)
    blockchainHeight="${btc_mainnet_blocks_headers}"
    lastBlockchainHeight=$(($blockchainHeight - 1))
    if [ $electrumResponding -eq 0 ]; then
      syncedToBlock=$(sudo journalctl -u fulcrum -n 100 | grep Processed | tail -n1 | grep -oP '(?<=Processed height: )\d+')
    else
      syncedToBlock=$(echo "${getInfo}" | jq -r '.height')
    fi

    syncProgress=0
    if [ "${syncedToBlock}" != "" ] && [ "${blockchainHeight}" != "" ] && [ "${blockchainHeight}" != "0" ]; then
      syncProgress="$(echo "$syncedToBlock" "$blockchainHeight" | awk '{printf "%.2f", $1 / $2 * 100}')"
    fi
    echo "syncProgress=${syncProgress}%"
    if [ "${syncedToBlock}" = "${blockchainHeight}" ] || [ "${syncedToBlock}" = "${lastBlockchainHeight}" ]; then
      tipSynced=1
    else
      tipSynced=0
    fi
    echo "tipSynced=$tipSynced"

    fileFlagExists=$(sudo ls /mnt/hdd/app-storage/fulcrum/initial-sync.done 2>/dev/null | grep -c 'initial-sync.done')
    if [ ${fileFlagExists} -eq 0 ] && [ ${tipSynced} -gt 0 ]; then
      # set file flag for the future
      sudo touch /mnt/hdd/app-storage/fulcrum/initial-sync.done
      sudo chmod 544 /mnt/hdd/app-storage/fulcrum/initial-sync.done
      fileFlagExists=1
    fi
    if [ ${fileFlagExists} -eq 0 ]; then
      echo "initialSynced=0"
      echo "infoSync='Building Fulcrum database ($syncProgress)'"
    else
      echo "initialSynced=1"
    fi

  else
    echo "tipSynced=0"
    echo "initialSynced=0"
    echo "electrumResponding=0"
    echo "infoSync='Not running - check: sudo journalctl -u fulcrum'"
  fi
  exit 0
fi

if [ "$1" = "menu" ]; then
  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.fulcrum.sh status showAddress)

  if [ ${serviceInstalled} -eq 0 ]; then
    echo "# FAIL not installed"
    exit 1
  fi

  if [ ${serviceRunning} -eq 0 ]; then
    dialog --title " Fulcrum Service Not Running" --msgbox "
The fulcrum.service is not running.
Please check the following debug info.
      " 8 48
    sudo journalctl -u fulcrum -n 100
    echo "Press ENTER to get back to main menu."
    read -r
    exit 0
  fi

  if [ ${initialSynced} -eq 0 ]; then
    dialog --title "Fulcrum Index Not Ready" --msgbox "
Fulcrum is still building its index.
Currently is at $syncProgress
This can take multiple days.
Monitor the progress with the command:
'sudo journalctl -fu fulcrum'
" 11 48
    exit 0
  fi

  if [ ${nginxTest} -eq 0 ]; then
    dialog --title "Testing nginx.conf has failed" --msgbox "
Nginx is in a failed state. Will attempt to fix.
Try connecting via port 50022 or Tor again once finished.
Check 'sudo nginx -t' for a detailed error message.
      " 9 61
    logFileMissing=$(sudo nginx -t 2>&1 | grep -c "/var/log/nginx/access.log")
    if [ ${logFileMissing} -eq 1 ]; then
      sudo mkdir /var/log/nginx
      sudo systemctl restart nginx
    fi
    /home/admin/config.scripts/blitz.web.sh
    echo "Press ENTER to get back to main menu."
    read -r
    exit 0
  fi

  OPTIONS=(
    CONNECT "How to connect"
    REINDEX "Delete and rebuild the Fulcrum database"
    STATUS "Fulcrum status info"
  )

  CHOICE=$(whiptail --clear --title "Fulcrum Electrum Server" --menu "menu" 10 50 3 "${OPTIONS[@]}" 2>&1 >/dev/tty)
  clear

  case $CHOICE in
  CONNECT)
    echo "######## How to Connect to the Fulcrum Electrum Server #######"
    echo
    echo "Install the Electrum Wallet App on your laptop from:"
    echo "https://electrum.org"
    echo
    echo "On Network Settings > Server menu:"
    echo "- deactivate automatic server selection"
    echo "- as manual server set '${localIP}' & '${portSSL}'"
    echo "- laptop and RaspiBlitz need to be within same local network"
    echo
    echo "To start directly from laptop terminal use"
    echo "PC: electrum --oneserver --server ${localIP}:${portSSL}:s"
    echo "MAC: open -a /Applications/Electrum.app --args --oneserver --server ${localIP}:${portSSL}:s"
    if [ ${TorRunning} -eq 1 ]; then
      echo
      echo "The Tor Hidden Service address for Fulcrum is (see LCD for QR code):"
      echo "${TORaddress}"
      echo
      echo "To connect through Tor open the Tor Browser and start with the options:"
      echo "electrum --oneserver --server ${TORaddress}:50022:s --proxy socks5:127.0.0.1:9150"
      sudo /home/admin/config.scripts/blitz.display.sh qr "${TORaddress}"
    fi
    echo
    echo "For more details check the RaspiBlitz README on Fulcrum:"
    echo "https://github.com/raspiblitz/raspiblitz"
    echo
    echo "Press ENTER to get back to main menu."
    read key
    sudo /home/admin/config.scripts/blitz.display.sh hide
    ;;
  STATUS)
    sudo /home/admin/config.scripts/bonus.fulcrum.sh status
    echo
    echo "Press ENTER to get back to main menu."
    read key
    ;;
  REINDEX)
    echo "######## Delete and rebuild the Fulcrum database ########"
    echo "# Last chance to cancel here: press CTRL+C to exit and keep the database"
    echo "# Press any key to proceed with the deletion"
    read -r
    echo "# stopping service"
    sudo systemctl stop fulcrum
    echo "# deleting index"
    sudo rm -r /mnt/hdd/app-storage/fulcrum/db
    sudo rm /mnt/hdd/app-storage/fulcrum/initial-sync.done 2>/dev/null
    echo "# starting service"
    sudo systemctl start fulcrum
    echo "# ok"
    echo
    echo "Press ENTER to get back to main menu."
    read -r
    ;;
  esac

  exit 0
fi

function downloadAndVerifyBinary() {
  cd /home/fulcrum || exit 1

  # download the prebuilt binary
  sudo -u fulcrum wget https://github.com/cculianu/Fulcrum/releases/download/v${fulcrumVersion}/Fulcrum-${fulcrumVersion}-${build}.tar.gz || exit 1
  sudo -u fulcrum wget https://github.com/cculianu/Fulcrum/releases/download/v${fulcrumVersion}/Fulcrum-${fulcrumVersion}-shasums.txt || exit 1
  sudo -u fulcrum wget https://github.com/cculianu/Fulcrum/releases/download/v${fulcrumVersion}/Fulcrum-${fulcrumVersion}-shasums.txt.asc || exit 1

  # Verify
  # get the PGP key
  curl https://raw.githubusercontent.com/Electron-Cash/keys-n-hashes/master/pubkeys/calinkey.txt | sudo -u fulcrum gpg --import

  echo "# Look for 'Good signature'"
  sudo -u fulcrum gpg --verify Fulcrum-${fulcrumVersion}-shasums.txt.asc || exit 1

  echo "# Look for 'OK'"
  sudo -u fulcrum sha256sum -c Fulcrum-${fulcrumVersion}-shasums.txt --ignore-missing || exit 1

  echo "# Unpack"
  sudo -u fulcrum tar -xvf Fulcrum-${fulcrumVersion}-${build}.tar.gz

  # symlink to fulcrum home
  # remove first to start clean
  sudo rm -f /home/fulcrum/Fulcrum
  sudo rm -f /home/fulcrum/FulcrumAdmin
  # symlink
  sudo ln -s /home/fulcrum/Fulcrum-${fulcrumVersion}-${build}/Fulcrum /home/fulcrum/
  sudo ln -s /home/fulcrum/Fulcrum-${fulcrumVersion}-${build}/FulcrumAdmin /home/fulcrum/
}

function createSystemdService() {
  echo "# Create a systemd service"
  echo "\
[Unit]
Description=Fulcrum
After=network.target bitcoind.service
StartLimitBurst=2
StartLimitIntervalSec=20

[Service]
ExecStart=/home/fulcrum/Fulcrum /home/fulcrum/.fulcrum/fulcrum.conf
KillSignal=SIGINT
User=fulcrum
LimitNOFILE=8192
TimeoutStopSec=300
RestartSec=5
Restart=on-failure

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/fulcrum.service
}

# set the platform
if [ "$(uname -m)" = "aarch64" ]; then
  build="arm64-linux"
elif [ "$(uname -m)" = "x86_64" ]; then
  build="x86_64-linux"
fi

if [ "$1" = on ]; then
  # ?wait until txindex finishes?
  /home/admin/config.scripts/network.txindex.sh on

  # activate zram
  /home/admin/config.scripts/blitz.zram.sh on

  /home/admin/config.scripts/blitz.conf.sh set rpcworkqueue 512 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set rpcthreads 128 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set 'main.zmqpubhashblock' 'tcp://0.0.0.0:8433' /mnt/hdd/bitcoin/bitcoin.conf noquotes

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Restarting bitcoind"
    sudo systemctl restart bitcoind
  fi

  # create a dedicated user
  sudo adduser --system --group --home /home/fulcrum fulcrum

  sudo apt install -y libssl-dev # was needed on Debian Bullseye

  downloadAndVerifyBinary

  echo "# Create the database directory in /mnt/hdd/app-storage (on the disk)"
  sudo mkdir -p /mnt/hdd/app-storage/fulcrum/db
  sudo chown -R fulcrum:fulcrum /mnt/hdd/app-storage/fulcrum

  echo "# Create a symlink to /home/fulcrum/.fulcrum"
  sudo ln -s /mnt/hdd/app-storage/fulcrum /home/fulcrum/.fulcrum
  sudo chown -R fulcrum:fulcrum /home/fulcrum/.fulcrum

  echo "# Create a config file"
  echo "# Get the RPC credentials from the bitcoin.conf"
  RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  echo "\
datadir = /home/fulcrum/.fulcrum/db
bitcoind = 127.0.0.1:8332
rpcuser = ${RPC_USER}
rpcpassword = ${PASSWORD_B}
# RPi optimizations
# avoid 'bitcoind request timed out'
bitcoind_timeout = 600
# reduce load (4 cores only)
bitcoind_clients = 1
worker_threads = 1
db_mem=1024
# for 4GB RAM
db_max_open_files=200
fast-sync = 1024
# server connections
# disable peer discovery and public server options
peering = false
announce = false
tcp = 0.0.0.0:${portTCP}
admin = ${portAdmin}
# ssl via nginx
" | sudo -u fulcrum tee /home/fulcrum/.fulcrum/fulcrum.conf

  createSystemdService

  sudo systemctl enable fulcrum
  if [ "${state}" == "ready" ]; then
    echo "# Starting the fulcrum.service"
    sudo systemctl start fulcrum
  fi

  sudo ufw allow ${portTCP} comment 'Fulcrum TCP'
  sudo ufw allow ${portSSL} comment 'Fulcrum SSL'

  # Setting up the nginx.conf with the existing SSL cert
  isConfigured=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'upstream fulcrum')
  if [ ${isConfigured} -gt 0 ]; then
    echo "fulcrum is already configured with Nginx. To edit manually run 'sudo nano /etc/nginx/nginx.conf'"
  elif [ ${isConfigured} -eq 0 ]; then
    isStream=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'stream {')
    if [ ${isStream} -eq 0 ]; then
      echo "
stream {
        upstream fulcrum {
                server 127.0.0.1:${portTCP};
        }
        server {
                listen ${portSSL} ssl;
                proxy_pass fulcrum;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-fulcrum:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

    elif [ ${isStream} -eq 1 ]; then
      sudo truncate -s-2 /etc/nginx/nginx.conf
      echo "
        upstream fulcrum {
                server 127.0.0.1:${portTCP};
        }
        server {
                listen ${portSSL} ssl;
                proxy_pass fulcrum;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-fulcrum:1m;
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

  # test and reload nginx
  sudo nginx -t && sudo systemctl reload nginx

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh fulcrum ${portTCP} ${portTCP} ${portSSL} ${portSSL}

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set fulcrum "on"

  echo "# Follow the logs with the command:"
  echo "sudo journalctl -fu fulcrum"

  exit 0
fi

if [ "$1" = update ]; then
  # get the latest release from github without the leading 'v'
  fulcrumVersion=$(curl --silent https://api.github.com/repos/cculianu/Fulcrum/releases/latest | jq -r '.tag_name | ltrimstr("v")')
  echo "# The latest release is: $fulcrumVersion"

  # check if the binary is already installed
  if [ -f /home/fulcrum/Fulcrum-${fulcrumVersion}-${build}/Fulcrum ]; then
    echo "# Fulcrum-${fulcrumVersion}-${build} is already installed"
    exit 0
  else
    echo "# Installing Fulcrum-${fulcrumVersion}-${build}"
  fi

  downloadAndVerifyBinary

  sudo systemctl disable --now fulcrum

  createSystemdService

  sudo systemctl enable --now fulcrum
  exit 0
fi

if [ "$1" = off ]; then
  sudo systemctl disable --now fulcrum
  sudo userdel -rf fulcrum
  # remove Tor service
  /home/admin/config.scripts/tor.onion-service.sh off fulcrum
  # close ports on firewall
  sudo ufw delete allow ${portTCP}
  sudo ufw delete allow ${portSSL}
  # to remove the database directory:
  # sudo rm -rf /mnt/hdd/app-storage/fulcrum
  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set fulcrum "off"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
