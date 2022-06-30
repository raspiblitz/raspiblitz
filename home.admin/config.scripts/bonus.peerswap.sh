#!/bin/bash

# https://github.com/ElementsProject/peerswap/commits/master
pinnedVersion="baf6e4c38d16dcd922f94e777bcd892db5b0bc5f"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the PeerSwap Service on,off or update"
 echo "bonus.peerswap.sh [on|off|menu|update]"
 exit 1
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " PeerSwap Service Info" --msgbox "
Usage and examples:
https://github.com/ElementsProject/peerswap/blob/master/docs/usage.md

Use the command 'sudo su - peerswap' in the terminal to switch to the dedicated user.

Type 'pscli help' to see the available options.
" 14 73
  exit 0
fi

# releases are creatd on GitHub
PGPsigner="web-flow"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="4AEE18F83AFDEB23"


# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Install Lightning peerswap"

  isInstalled=$(sudo ls /etc/systemd/system/peerswapd.service 2>/dev/null | grep -c 'peerswapd.service')
  if [ ${isInstalled} -eq 0 ]; then

    # install Go
    /home/admin/config.scripts/bonus.go.sh on

    # get Go vars
    source /etc/profile

    # create dedicated user
    sudo adduser --disabled-password --gecos "" peerswap

    # set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/peerswap/go/bin/' >> /home/peerswap/.profile"


    echo "# persist settings in app-data"
    mkdir -p ~/.peerswap
    # move old data if present
    sudo mv /home/peerswap/.peerswap /mnt/hdd/app-data/ 2>/dev/null
    echo "# make sure the data directory exists"
    sudo mkdir -p /mnt/hdd/app-data/.peerswap
    echo "# symlink"
    sudo rm -rf /home/peerswap/.peerswap # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/.peerswap/ /home/peerswap/.peerswap
    sudo chown peerswap:peerswap -R /mnt/hdd/app-data/.peerswap


    cd /home/peerswap || exit 1
    sudo -u peerswap git clone https://github.com/ElementsProject/peerswap.git
    cd /home/peerswap/peerswap || exit 1
    sudo -u peerswap git reset --hard $pinnedversion

    sudo -u peerswap /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

    # build
    sudo -u peerswap bash -c 'PATH=/usr/local/go/bin/:$PATH; make lnd-release'|| exit 1
    # install
    sudo mv /home/peerswap/peerswap/peerswapd /usr/local/bin/
    sudo mv /home/peerswap/peerswap/pscli /usr/local/bin/
    sudo chown root:root /usr/local/bin/peerswapd
    sudo chown root:root /usr/local/bin/pscli

    # make sure symlink to central app-data directory exists
    sudo rm -rf /home/peerswap/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/peerswap/.lnd

    # sync all macaroons and unix groups for access
    /home/admin/config.scripts/lnd.credentials.sh sync
    # macaroons will be checked after install

    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin peerswap
    # add user to group with readonly access on lnd
    sudo /usr/sbin/usermod --append --groups lndreadonly peerswap
    # add user to group with invoice access on lnd
    sudo /usr/sbin/usermod --append --groups lndinvoice peerswap
    # add user to groups with all macaroons
    sudo /usr/sbin/usermod --append --groups lndinvoices peerswap
    sudo /usr/sbin/usermod --append --groups lndchainnotifier peerswap
    sudo /usr/sbin/usermod --append --groups lndsigner peerswap
    sudo /usr/sbin/usermod --append --groups lndwalletkit peerswap
    sudo /usr/sbin/usermod --append --groups lndrouter peerswap

    echo "\
lnd.tlscertpath=/home/peerswap/.lnd/tls.cert
lnd.macaroonpath=/home/peerswap/.lnd/data/chain/bitcoin/mainnet/admin.macaroon
" | sudo -u peerswap tee /home/peerswap/.peerswap/peerswap.conf

    # sudo nano /etc/systemd/system/peerswapd.service
    echo "
[Unit]
Description=peerswapd Service
After=lnd.service

[Service]
WorkingDirectory=/home/peerswap/.peerswap
ExecStart=/usr/local/bin/peerswapd
User=peerswap
Group=peerswap
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
" | sudo tee -a /etc/systemd/system/peerswapd.service
    sudo systemctl enable peerswapd
    echo "# OK - the peerswap service is now enabled"
    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      echo "# OK - peerswapd service is enabled, system is on ready so starting peerswapd.service"
      sudo systemctl start peerswapd
    else
      echo "# OK - peerswapd.service is enabled, but needs reboot or manual starting: sudo systemctl start peerswapd"
    fi
  else
    echo "# The peerswapd.service is already installed."
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set peerswap "on"


  if ! ls /usr/local/bin/peerswapd; then
    echo "# Failed to install PeerSwap"
    exit 1
  else
    echo "\
Usage and examples:
https://github.com/ElementsProject/peerswap/blob/master/docs/usage.md

Use the command 'sudo su - peerswap' in the terminal to switch to the dedicated user.

Type 'pscli help' to see the available options.

In order to check if your daemon is setup correctly run:
pscli reloadpolicy

The service name for monitoring:
peerswapd

On first startup of the plugin a policy file will be generated
(default path: ~/.peerswap/policy.conf) in which trusted nodes will be specified.
This cann be done manually by adding a line with:
allowlisted_peers=<REPLACE_WITH_PUBKEY_OF_PEER>
or with pscli addpeer <PUBKEY>.
If you feel especially reckless you can add the line:
accept_all_peers=true
this will allow anyone with a direct channel to you do do a swap with you.
WARNING: One could also set the
accept_all_peers=1
policy to ignore the allowlist and allow for all peers to send swap requests.
"
  fi
  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set peerswap "off"

  isInstalled=$(sudo ls /etc/systemd/system/peerswapd.service 2>/dev/null | grep -c 'peerswapd.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing the PeerSwap service"
    # remove the systemd service
    sudo systemctl stop peerswapd
    sudo systemctl disable peerswapd
    sudo rm /etc/systemd/system/peerswapd.service
    # delete user and it's home directory
    sudo userdel -rf peerswap
    echo "# OK, the PeerSwap Service is removed."
  else
    echo "# PeerSwap is not installed."
  fi

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  sudo systemctl start peerswapd

  echo "# Updating PeerSwap"
  # clean old code
  sudo rm -rf /home/peerswap/peerswap || exit 1
  cd /home/peerswap || exit 1
  sudo -u peerswap git clone https://github.com/ElementsProject/peerswap.git

  # build
  sudo -u peerswap bash -c 'PATH=/usr/local/go/bin/:$PATH; make lnd-release'|| exit 1
  # install
  sudo mv /home/peerswap/peerswap/peerswapd /usr/local/bin/
  sudo mv /home/peerswap/peerswap/pscli /usr/local/bin/
  sudo chown root:root /usr/local/bin/peerswapd
  sudo chown root:root /usr/local/bin/pscli

  echo "# Updated to the latest in https://github.com/ElementsProject/peerswap/commits/master"
  echo
  echo "# Starting the peerswapd.service ..."
  sudo systemctl start peerswapd
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
