#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# Switch charge-lnd on or off (experimental feature)"
  echo "# needs to be switched on manually after every RaspiBlitz update/recovery for now"
  echo "# config is stored in /mnt/hdd/app-data/charge-lnd/charge.config"
  echo "# feedback: https://github.com/raspiblitz/raspiblitz/discussions/3955"
  echo "# bonus.charge-lnd.sh [on|off]"
  exit 1
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if charge-lnd is already installed
  isInstalled=$(sudo ls /etc/systemd/system/charge-lnd.service 2>/dev/null | grep -c 'charge-lnd.service')
  if [ $isInstalled -gt 1 ]; then
    echo "err='charge-lnd is already installed.'"
    exit 1
  fi

  # install charge-lnd
  echo "# Installing charge-lnd ..."
  cd /home/bitcoin
  sudo -u bitcoin git clone https://github.com/accumulator/charge-lnd.git
  cd charge-lnd || exit 1
  export CHARGE_LND_ENV=/home/bitcoin/charge-lnd
  sudo -u bitcoin python3 -m venv ${CHARGE_LND_ENV}
  sudo -u bitcoin ${CHARGE_LND_ENV}/bin/pip3 install -r requirements.txt .

  # check if already a charge-lnd config exists
  if [ -f /mnt/hdd/app-data/charge-lnd/charge.config ]; then
      echo "# skipping charge-lnd config creation because it already exists."
  else

    # setting up charge-lnd config
    echo "Setting up charge-lnd config ..."
    sudo mkdir -p /mnt/hdd/app-data/charge-lnd
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
" | sudo tee /mnt/hdd/app-data/charge-lnd/charge.config
  fi

  sudo chmod 770 -R /mnt/hdd/app-data/charge-lnd
  sudo chown bitcoin:bitcoin -R /mnt/hdd/app-data/charge-lnd

  # setting up systemd service
  echo "# Setting up charge-lnd systemd service ..."
  echo "
[Unit]
Description=charge-lnd
After=lnd.service

[Service]
ExecStart=bash -c '. /home/bitcoin/charge-lnd/bin/activate; /home/bitcoin/charge-lnd/bin/charge-lnd -c /mnt/hdd/app-data/charge-lnd/charge.config'
User=bitcoin
Group=bitcoin
Type=simple
KillMode=process
TimeoutSec=60

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/charge-lnd.service

  # setting up systemd timer for hourly charge-lnd service
  echo "# Setting up charge-lnd systemd timer ..."
  echo "
[Unit]
Description=Runs charge-lnd every hour

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
" | sudo tee /etc/systemd/system/charge-lnd.timer

  # enable timer because the service is only needed every hour once
  sudo systemctl enable charge-lnd.timer
  sudo systemctl start charge-lnd.timer
  echo "# To check if timers are running use: sudo systemctl list-timers"
  echo "# To check logs use: sudo journalctl -u charge-lnd"
  echo "# To edit config: sudo nano /mnt/hdd/app-data/charge-lnd/charge.config"
  echo "# Check options: https://github.com/accumulator/charge-lnd/blob/master/README.md"
  echo "# feedback: https://github.com/raspiblitz/raspiblitz/discussions/3955"

  echo "# charge-lnd installation done."
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check if charge-lnd is installed
  isInstalled=$(sudo ls /etc/systemd/system/charge-lnd.service 2>/dev/null | grep -c 'charge-lnd.service')
  if [ $isInstalled -eq 0 ]; then
    echo "err='charge-lnd is not installed.'"
    exit 1
  fi

  echo "# Removing charge-lnd..."
  sudo systemctl stop charge-lnd.timer
  sudo systemctl disable charge-lnd.timer
  sudo rm /etc/systemd/system/charge-lnd.service
  sudo rm /etc/systemd/system/charge-lnd.timer
  sudo rm -rf /home/bitcoin/charge-lnd
  sudo rm -rf /mnt/hdd/app-data/charge-lnd

  echo "# charge-lnd removal done."
  exit 0
fi

echo "err='invalid parameter.'"
exit 1
