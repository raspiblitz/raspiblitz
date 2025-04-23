#!/bin/bash

# https://github.com/lightningequipment/circuitbreaker/releases
# https://github.com/lightningequipment/circuitbreaker/commits/master
pinnedVersion="60b70d91710efe7227b253e74f0d39ccfc9702c1"


# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Config script to switch the circuitbreaker on, off or update to the latest release tag or commit"
  echo "bonus.circuitbreaker.sh [on|off|update|update commit|menu]"
  echo
  echo "Version to be installed by default: $pinnedVersion"
  echo "Source: https://github.com/lightningequipment/circuitbreaker"
  echo
  exit 1
fi

PGPsigner="web-flow"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="(4AEE18F83AFDEB23|B5690EEEBB952194)"

# PGPsigner="joostjager"
# PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
# PGPpubkeyFingerprint="B9A26449A5528325"

source /mnt/hdd/app-data/raspiblitz.conf

isInstalled=$(sudo ls /etc/systemd/system/circuitbreaker.service 2>/dev/null | grep -c 'circuitbreaker.service')

# show info menu
if [ "$1" = "menu" ]; then
  # get network info
  localip=$(hostname -I | awk '{print $1}')
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  # info without Tor
  whiptail --title " Circuit Breaker" --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:9236\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
To follow the logs use the command:
sudo journalctl -fu circuitbreaker
" 14 63

  echo "please wait ..."
  exit 0
fi

# switch on
if [ "$1" = "menu" ]; then
  if [ ${isInstalled} -eq 1 ]; then
    whiptail --title " circuitbreaker " --msgbox "Circuitbreaker is to Lightning what firewalls are to the internet.\n
Its a service running in the background - use to monitor:
sudo journalctl -fu circuitbreaker\n
For more details and further information see:
https://github.com/lightningequipment/circuitbreaker/blob/master/README.md
" 13 78
    clear
  else
    echo "# Circuit Breaker is not installed."
  fi
  exit 0
fi

# stop services
echo "# Making sure the service is not running"
sudo systemctl stop circuitbreaker 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Installing circuitbreaker $pinnedVersion"
  if [ ${isInstalled} -eq 0 ]; then
    # install Go
    /home/admin/config.scripts/bonus.go.sh on

    # get Go vars
    source /etc/profile
    # create dedicated user
    sudo adduser --system --group --home /home/circuitbreaker circuitbreaker
    # set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/circuitbreaker/go/bin/' >> /home/circuitbreaker/.profile"

    # make sure symlink to central app-data directory exists"
    sudo rm -rf /home/circuitbreaker/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/circuitbreaker/.lnd

    # sync all macaroons and unix groups for access
    /home/admin/config.scripts/lnd.credentials.sh sync "${chain:-main}net"
    # macaroons will be checked after install

    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin circuitbreaker

    # install from source
    cd /home/circuitbreaker || exit 1
    sudo -u circuitbreaker git clone https://github.com/lightningequipment/circuitbreaker.git
    cd circuitbreaker || exit 1
    sudo -u circuitbreaker git reset --hard $pinnedVersion

    sudo -u circuitbreaker /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

    sudo -u circuitbreaker /usr/local/go/bin/go install ./... || exit 1

    # make systemd service
    # sudo nano /etc/systemd/system/circuitbreaker.service
    echo "
[Unit]
Description=circuitbreaker Service
After=lnd.service

[Service]
WorkingDirectory=/home/circuitbreaker/circuitbreaker
ExecStart=/home/circuitbreaker/go/bin/circuitbreaker --network=${chain}net
User=circuitbreaker
Group=circuitbreaker
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
" | sudo tee -a /etc/systemd/system/circuitbreaker.service
    sudo systemctl enable circuitbreaker
    echo "# OK - the circuitbreaker.service is now enabled"

  else
    echo "# The circuitbreaker.service is already installed."
  fi

  ##################
  # NGINX
  ##################
  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/circuitbreaker_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/circuitbreaker_ssl.conf /etc/nginx/sites-available/circuitbreaker_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/circuitbreaker_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  isInstalled=$(sudo -u circuitbreaker /home/circuitbreaker/go/bin/circuitbreaker --version | grep -c "circuitbreakerd version")
  if [ ${isInstalled} -eq 1 ]; then
    echo

    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      echo "# OK - the circuitbreaker.service is enabled, system is on ready so starting service"
      sudo systemctl start circuitbreaker
    else
      echo "# OK - the circuitbreaker.service is enabled, to start manually use: sudo systemctl start circuitbreaker"
    fi
    echo "# Find more info at https://github.com/lightningequipment/circuitbreaker"
    echo "# Monitor with: 'sudo journalctl -fu circuitbreaker'"
  else
    echo "# Failed to install circuitbreaker "
    exit 1
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set circuitbreaker "on"

  sudo ufw allow 9236 comment circuitbreaker_https

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# Removing the user and it's home directory"
  sudo userdel -rf circuitbreaker 2>/dev/null

  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing the circuitbreaker.service"
    sudo systemctl stop circuitbreaker
    sudo systemctl disable circuitbreaker
    sudo rm /etc/systemd/system/circuitbreaker.service
    echo "# OK, circuitbreaker.service is removed."
  else
    echo "# circuitbreaker.service is not installed."
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set circuitbreaker "off"

  sudo ufw delete allow 9236

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# Updating Circuit Breaker"
  cd /home/circuitbreaker/circuitbreaker || exit 1
  # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
  # fetch latest master
  sudo -u circuitbreaker git fetch
  if [ "$2" = "commit" ]; then
    echo "# Updating to the latest commit in the default branch"
    TAG=$(git describe --tags)
  else
    TAG=$(git tag | sort -V | tail -1)
    # unset $1
    set --
    UPSTREAM=${1:-'@{u}'}
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse "$UPSTREAM")
    if [ $LOCAL = $REMOTE ]; then
      echo "# You are up-to-date on version" $TAG
      echo "# Starting the circuitbreaker service ... "
      sudo systemctl start circuitbreaker
      exit 0
    fi
  fi
  echo "# Pulling latest changes..."
  sudo -u circuitbreaker git pull -p
  sudo -u circuitbreaker git reset --hard $TAG

  #TODO PGP verification on update

  echo "# Installing the version: $TAG"
  sudo -u circuitbreaker /usr/local/go/bin/go install ./... || exit 1
  echo
  echo "# Updated to version" $TAG
  echo
  echo "# Starting the circuitbreaker service ... "
  sudo systemctl start circuitbreaker
  echo "# Monitor with: 'sudo journalctl -fu circuitbreaker'"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
