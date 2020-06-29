#!/bin/bash

# https://github.com/dennisreimann/stacking-sats-kraken

USERNAME=stackingsats

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch stacking-sats-kraken on or off"
 echo "bonus.stacking-sats-kraken.sh [on|off]"
 exit 1
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL STACKING-SATS-KRAKEN ***"

  isInstalled=$(sudo ls /home/$USERNAME 2>/dev/null | grep -c 'stacking-sats-kraken')
  if [ ${isInstalled} -eq 0 ]; then

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh

    echo "*** Add the 'stackingsats' user ***"
    sudo adduser --disabled-password --gecos "" $USERNAME

    # install stacking-sats-kraken
    cd /home/$USERNAME
    sudo -u $USERNAME git clone https://github.com/dennisreimann/stacking-sats-kraken.git stacking-sats-kraken
    cd stacking-sats-kraken
    sudo -u $USERNAME npm install

    # setup stacking config
    configFile=/home/admin/stacking-sats-kraken.env
    touch $configFile
    sudo chmod 600 $configFile || exit 1
    cat > $configFile <<EOF
KRAKEN_API_KEY="apiKeyFromTheKrakenSettings"
KRAKEN_API_SECRET="privateKeyFromTheKrakenSettings"
KRAKEN_API_FIAT="USD"
KRAKEN_BUY_AMOUNT=21

# Remove this line after verifying everything works
KRAKEN_DRY_RUN_PLACE_NO_ORDER=1
EOF
    sudo mv $configFile /home/$USERNAME/.config/stacking-sats-kraken.env
    sudo chown $USERNAME:$USERNAME /home/$USERNAME/.config/stacking-sats-kraken.env

    # setup stacking script
    scriptFile=/home/admin/stack-sats-kraken.sh
    touch $scriptFile
    sudo chmod 700 $scriptFile || exit 1
    echo '#!/bin/bash
set -e

# hide deprecation warning
export NODE_OPTIONS="--no-deprecation"

# load config
set -a; source ~/.config/stacking-sats-kraken.env; set +a

# run script
cd ~/stacking-sats-kraken
if [[ -z "${KRAKEN_DRY_RUN_PLACE_NO_ORDER}" ]]; then
  result=$(npm run stack-sats 2>&1)
else
  result=$(npm test 2>&1)
fi
echo "$result"

# optional: send email – requires `blitz.notify.sh on`
# /home/admin/config.scripts/blitz.notify.sh send "$result" --subject "Sats got stacked"' > $scriptFile

    sudo mv $scriptFile /home/$USERNAME/stack-sats-kraken.sh
    sudo chown $USERNAME:$USERNAME /home/$USERNAME/stack-sats-kraken.sh

    echo "OK - the STACKING-SATS-KRAKEN script is now installed."
    echo ""
    echo "You need to adapt the settings in /home/$USERNAME/.config/stacking-sats-kraken.env"

    cron_count=$(crontab -l | grep "stack-sats.sh" -c)
    if [ "${cron_count}" = "0" ]; then
      echo ""
      echo "You might want to set up a cronjob to run the script in regular intervals."
      echo "Switch to the '$USERNAME' user and add it using the 'crontab -e' command."
      echo "Here is an example for daily usage at 6:15am..."
      echo ""
      echo "15 6 * * * /home/$USERNAME/stack-sats.sh"
    fi
  else
    echo "STACKING-SATS-KRAKEN already installed."
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** UNINSTALL STACKING-SATS-KRAKEN ***"
  isInstalled=$(sudo ls /home/$USERNAME 2>/dev/null | grep -c 'stacking-sats-kraken')

  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING STACKING-SATS-KRAKEN ***"

    sudo rm -rf /home/$USERNAME/stack-sats-kraken.sh
    sudo rm -rf /home/$USERNAME/stacking-sats-kraken
    sudo rm -f /home/$USERNAME/.config/stacking-sats-kraken.env

    echo "OK STACKING-SATS-KRAKEN removed."

    cron_count=$(crontab -l | grep "stack-sats.sh" -c)
    if [ "${cron_count}" != "0" ]; then
      echo ""
      echo "You should remove any cronjob that ran the script."
    fi
  else
    echo "STACKING-SATS-KRAKEN is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
