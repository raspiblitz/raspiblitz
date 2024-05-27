#!/bin/bash

# This script installs and configures charge-lnd according to the specified plan.

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to switch charge-lnd on or off"
  echo "bonus.charge-lnd.sh [on|off]"
  exit 1
fi

# add default value to raspi config if needed
source /mnt/hdd/raspiblitz.conf
if ! grep -Eq "^charge-lnd=" /mnt/hdd/raspiblitz.conf; then
  echo "charge-lnd=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if charge-lnd is already installed
  if [ $(grep -c 'charge-lnd=on' /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "charge-lnd is already installed."
    exit 1
  fi

  # mark charge-lnd in raspiblitz.conf as installed
  sudo sed -i "s/^charge-lnd=.*/charge-lnd=on/g" /mnt/hdd/raspiblitz.conf

  # install charge-lnd
  echo "Installing charge-lnd..."
  cd /home/bitcoin || exit 1
  sudo -u bitcoin git clone https://github.com/accumulator/charge-lnd.git
  cd charge-lnd || exit 1
  sudo -u bitcoin /home/bitcoin/charge-lnd/bin/charge-lnd

  # setting up charge-lnd config
  echo "Setting up charge-lnd config..."
  mkdir -p /mnt/hdd/app-data/charge-lnd
  config="/mnt/hdd/app-data/charge-lnd/charge.config"
  echo "
[discourage-routing-out-of-balance]
chan.max_ratio = 0.1
chan.min_capacity = 250000
strategy = static
base_fee_msat = 2000
fee_ppm = 690

[encourage-routing-to-balance]
chan.min_ratio = 0.9
chan.min_capacity = 250000
strategy = static
base_fee_msat = 1000
fee_ppm = 21

[default-proportional]
chan.max_ratio = 0.9
chan.min_ratio = 0.1
chan.min_capacity = 250000
strategy = proportional
min_fee_ppm = 21
max_fee_ppm = 210
base_fee_msat = 2000
" > ${config}

  # add charge-lnd to crontab
  echo "Adding charge-lnd to crontab..."
  (crontab -l 2>/dev/null; echo "0 */6 * * * /home/bitcoin/charge-lnd/bin/charge-lnd -c ${config}") | crontab -

  # setting up systemd service
  echo "Setting up charge-lnd systemd service..."
  echo "
[Unit]
Description=charge-lnd
After=lnd.service

[Service]
ExecStart=/home/bitcoin/charge-lnd/bin/charge-lnd -c ${config}
User=bitcoin
Group=bitcoin
Type=simple
KillMode=process
TimeoutSec=60
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/charge-lnd.service
  sudo systemctl enable charge-lnd
  sudo systemctl start charge-lnd

  echo "charge-lnd installation done."
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check if charge-lnd is installed
  if [ $(grep -c 'charge-lnd=off' /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "charge-lnd is not installed."
    exit 1
  fi

  echo "Removing charge-lnd..."
  sudo systemctl stop charge-lnd
  sudo systemctl disable charge-lnd
  sudo rm /etc/systemd/system/charge-lnd.service
  sudo rm -rf /home/bitcoin/charge-lnd
  (crontab -l | grep -v '/home/bitcoin/charge-lnd/bin/charge-lnd') | crontab -
  sudo sed -i "s/^charge-lnd=.*/charge-lnd=off/g" /mnt/hdd/raspiblitz.conf

  echo "charge-lnd removal done."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
