#!/bin/bash

# https://github.com/lndk-org/lndk/releases/tag/v0.0.1
LNDKVERSION="v0.1.1"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the LNDK Service on or off"
  echo "installs the version $LNDKVERSION"
  echo "bonus.lndk.sh [on|off|menu]"
  exit 1
fi

# Switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# INSTALL LNDK"

  lndkServicePath="/etc/systemd/system/lndk.service"
  isInstalled=$(sudo ls $lndkServicePath 2>/dev/null | grep -c 'lndk.service')
  if [ ${isInstalled} -eq 0 ]; then

    # Install Rust for lndk, includes rustfmt
    sudo -u bitcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sudo -u bitcoin sh -s -- -y
    
    # Clone and compile lndk onto Raspiblitz.
    if [ ! -d "/home/bitcoin/lndk" ]; then
      cd /home/bitcoin || exit 1
      sudo -u bitcoin git clone https://github.com/lndk-org/lndk
      cd /home/bitcoin/lndk || exit 1
      sudo -u bitcoin git checkout tags/$LNDKVERSION -b $LNDKVERSION
      sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo build # Lndk bin will be built to /home/bitcoin/lndk/target/debug/lndk
    fi

    # LND needs the following configuration settings so lndk can run.
    protocol=protocol
    lnd_conf_file=/home/bitcoin/.lnd/lnd.conf
    if grep $protocol $lnd_conf_file; then
       echo "[protocol]
protocol.custom-message=513
protocol.custom-nodeann=39
protocol.custom-init=39
" | sudo tee -a $lnd_conf_file
    fi

    echo "[Unit]
Description=lndk Service
After=lnd.service
PartOf=lnd.service

[Service]
ExecStart=/home/bitcoin/lndk/target/debug/lndk --address=https://localhost:10009 --cert=/mnt/hdd/lnd/tls.cert --macaroon=/mnt/hdd/lnd/data/chain/bitcoin/mainnet/admin.macaroon
User=bitcoin
Group=bitcoin
Type=simple
TimeoutSec=60
Restart=on-failure
RestartSec=60
StandardOutput=journal
StandardError=journal
LogLevelMax=4

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee -a $lndkServicePath
    sudo systemctl enable lndk
    sudo systemctl start lndk
    echo "OK - we've now started the LNDK service" 

    # Set value in raspiblitz config
    /home/admin/config.scripts/blitz.conf.sh set lndk "on"
  fi

  exit 0
fi

# Show info menu
if [ "$1" = "menu" ]; then
  whiptail --title " LNDK " --msgbox "Your node is now forwarding onion messages!\n
Check 'sudo systemctl status lndk' to see if it's running properly.\n
See more information about LNDK v0.0.1 here: https://github.com/lndk-org/lndk" 14 63

  echo "please wait ..."
  exit 0
fi

# Switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=$(sudo ls /etc/systemd/system/lndk.service 2>/dev/null | grep -c 'lndk.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING LNDK ***"
    # remove the systemd service
    sudo systemctl stop lndk
    sudo systemctl disable lndk
    sudo rm /etc/systemd/system/lndk.service

    sudo rm /home/bitcoin/lndk/target/debug/lndk
  else
    echo "# LNDK is not installed."
  fi

  # Set value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lndk "off"

  exit 0 
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run normal again"
exit 1
