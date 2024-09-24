#!/bin/bash

# https://github.com/lndk-org/lndk/releases
LNDKVERSION="v0.2.0"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the LNDK Service on or off"
  echo "installs the version $LNDKVERSION"
  echo "bonus.lndk.sh [on|menu]"
  echo "bonus.lndk.sh off <--delete-data|--keep-data>"
  exit 1
fi

source /home/admin/raspiblitz.info
source <(/home/admin/_cache.sh get state)

# Switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  lndkServicePath="/etc/systemd/system/lndk.service"
  isInstalled=$(sudo ls $lndkServicePath 2>/dev/null | grep -c 'lndk.service')
  if [ ${isInstalled} -eq 0 ]; then
    echo "# INSTALL LNDK"

    USERNAME=lndk
    echo "# add the user: ${USERNAME}"
    sudo adduser --system --group --shell /bin/bash --home /home/${USERNAME} ${USERNAME}
    echo "Copy the skeleton files for login"
    sudo -u ${USERNAME} cp -r /etc/skel/. /home/${USERNAME}/

    sudo apt-get install -y protobuf-compiler

    # Install Rust for lndk, includes rustfmt
    sudo -u lndk curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
      sudo -u lndk sh -s -- -y

    # Clone and compile lndk onto Raspiblitz.
    if [ ! -f "/usr/local/bin/lndk" ] || [ ! -f "/usr/local/bin/lndk-cli" ]; then
      cd /home/lndk || exit 1
      sudo -u lndk git clone https://github.com/lndk-org/lndk
      cd /home/lndk/lndk || exit 1
      sudo -u lndk git reset --hard $LNDKVERSION
      sudo -u lndk /home/lndk/.cargo/bin/cargo build # Lndk bin will be built to /home/lndk/lndk/target/debug/lndk
      sudo install -m 0755 -o root -g root -t /usr/local/bin /home/lndk/lndk/target/debug/lndk
      sudo install -m 0755 -o root -g root -t /usr/local/bin /home/lndk/lndk/target/debug/lndk-cli
    fi

    # LND needs the following configuration settings so lndk can run.
    lnd_conf_file="/home/bitcoin/.lnd/lnd.conf"
    lines=(
      "protocol.custom-message=513"
      "protocol.custom-nodeann=39"
      "protocol.custom-init=39"
    )

    # Check if the [protocol] section exists
    needsLNDrestart=0
    if grep -q "\[protocol\]" "$lnd_conf_file"; then
      # Loop through each line to append after the [protocol] section
      for line in "${lines[@]}"; do
        # Check if the line already exists in the configuration file
        if ! grep -q "$line" "$lnd_conf_file"; then
          # Append the line after the [protocol] section
          echo $line
          sudo sed -i "/^\[protocol\]$/a $line" "$lnd_conf_file"
          needsLNDrestart=1
        fi
      done
    else
      # If the [protocol] section does not exist, create it and append the lines
      {
        echo "[protocol]"
        for line in "${lines[@]}"; do
          echo "$line"
        done
      } | sudo tee -a "$lnd_conf_file" >/dev/null
      needsLNDrestart=1
    fi

    if [ ${needsLNDrestart} -eq 1 ]; then
      if [ "${state}" == "ready" ]; then
        sudo systemctl restart lnd
      fi
    fi

    #config
    sudo mkdir -p /mnt/hdd/app-data/.lndk
    sudo chown -R lndk:lndk /mnt/hdd/app-data/.lndk
    sudo chmod 755 /mnt/hdd/app-data/.lndk

    cat <<EOF | sudo tee /mnt/hdd/app-data/.lndk/lndk.conf
address="https://localhost:10009"
cert_path="/mnt/hdd/lnd/tls.cert"
macaroon_path="/home/lndk/.lnd/data/chain/bitcoin/mainnet/admin.macaroon"
grpc_port=5635
log_level="debug"
response_invoice_timeout=15
EOF

    # symlink data dir for lndk and admin users
    sudo rm -rf /home/lndk/.lndk
    sudo ln -s /mnt/hdd/app-data/.lndk /home/lndk/
    sudo rm -rf /home/admin/.lndk
    sudo ln -s /mnt/hdd/app-data/.lndk /home/admin/

    # create symlink
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/lndk/.lnd"

    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin lndk

    echo "[Unit]
Description=lndk Service
After=lnd.service
BindsTo=lnd.service

[Service]
ExecStart=/usr/local/bin/lndk --conf=/mnt/hdd/app-data/.lndk/lndk.conf
User=lndk
Group=lndk
Type=simple
TimeoutSec=60
Restart=on-failure
RestartSec=60
StandardOutput=journal
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee $lndkServicePath
    sudo systemctl enable lndk
    echo "# Enabled the lndk.service"
    if [ "${state}" == "ready" ]; then
      sudo systemctl start lndk
      echo "# Started the lndk.service"
    fi

    echo "# Add alias for lndk-cli"
    sudo -u admin touch /home/admin/_aliases
    if [ $(grep -c "alias lndk-cli" </home/admin/_aliases) -eq 0 ]; then
      echo 'alias lndk-cli="lndk-cli -n mainnet --grpc-port=5635"' | sudo tee -a /home/admin/_aliases
    fi

    # Set value in raspiblitz config
    /home/admin/config.scripts/blitz.conf.sh set lndk "on"
  else
    echo "# LNDK is already installed."
    sudo systemctl status lndk
  fi

  exit 0
fi

# Show info menu
if [ "$1" = "menu" ]; then
  whiptail --title " LNDK " --msgbox "Your node is now able to pay BOLT12 offers and is forwarding onion messages!

Use the 'lndk-cli' command to get started.

Check 'sudo systemctl status lndk' to see if it's running properly.

Find more information about LNDK here: https://github.com/lndk-org/lndk" 16 63

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

  else
    echo "# LNDK is not installed."
  fi

  # remove the binaries
  sudo rm -f /usr/local/bin/lndk
  sudo rm -f /usr/local/bin/lndk-cli
  sudo rm -f /home/lndk/lndk/target/debug/lndk

  # remove the user and home dirlndl
  sudo userdel -rf lndk
  sudo rm -rf /home/admin/.lndk

  # get delete data status - either by parameter or if not set by user dialog
  deleteData=""
  if [ "$2" == "--delete-data" ]; then
    deleteData="1"
  fi
  if [ "$2" == "--keep-data" ]; then
    deleteData="0"
  fi
  if [ "${deleteData}" == "" ]; then
    if (whiptail --title "Delete Data?" --yes-button "Keep Data" --no-button "Delete Data" --yesno "Do you want to delete all data related to LNDK?" 0 0); then
      deleteData="0"
    else
      deleteData="1"
    fi
  fi

  if [ "${deleteData}" == "1" ]; then
    echo "# Deleting LNDK data ..."
    sudo rm -rf /mnt/hdd/app-data/.lndk
  else
    echo "# LNDK data is kept on the disk"
  fi

  # Set value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lndk "off"

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run normal again"
exit 1
