#!/bin/bash

# https://github.com/dennisreimann/stacking-sats-kraken

USERNAME=stackingsats
CONFIG_FILE=/mnt/hdd/app-data/stacking-sats-kraken/.env
SCRIPT_NAME=stack-sats.sh

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
    sudo -u $USERNAME git clone https://github.com/dennisreimann/stacking-sats-kraken.git
    cd stacking-sats-kraken
    sudo -u $USERNAME npm install

    # setup stacking config
    sudo mkdir /mnt/hdd/app-data/stacking-sats-kraken
    sudo chown $USERNAME:$USERNAME /mnt/hdd/app-data/stacking-sats-kraken

    configFile=/home/admin/stacking-sats-kraken.env
    touch $configFile
    sudo chmod 600 $configFile || exit 1
echo '# Required settings
KRAKEN_API_KEY="apiKeyFromTheKrakenSettings"
KRAKEN_API_SECRET="privateKeyFromTheKrakenSettings"
KRAKEN_API_FIAT="USD"
KRAKEN_BUY_AMOUNT=21

# Optional settings for confirmation mail – requires `blitz.notify.sh on`
# KRAKEN_MAIL_SUBJECT="Sats got stacked"
# KRAKEN_MAIL_FROM_ADDRESS="humble@satstacker.org"
# KRAKEN_MAIL_FROM_NAME="Humble Satstacker"

# Remove this line after verifying everything works
KRAKEN_DRY_RUN_PLACE_NO_ORDER=1
' > $configFile
    sudo mv $configFile $CONFIG_FILE
    sudo chown $USERNAME:$USERNAME $CONFIG_FILE

    # setup stacking script
    scriptFile="/home/admin/$SCRIPT_NAME"
    touch $scriptFile
    sudo chmod 700 $scriptFile || exit 1
    echo '#!/bin/bash
set -e

# hide deprecation warning
export NODE_OPTIONS="--no-deprecation"

# load config
set -a; source /mnt/hdd/app-data/stacking-sats-kraken/.env; set +a

# run script
cd ~/stacking-sats-kraken
if [[ -z "${KRAKEN_DRY_RUN_PLACE_NO_ORDER}" ]]; then
  result=$(npm run stack-sats 2>&1)
else
  result=$(npm test 2>&1)
fi
echo "$result"

# send email
if [[ ${KRAKEN_MAIL_SUBJECT} && ${KRAKEN_MAIL_FROM_ADDRESS} && ${KRAKEN_MAIL_FROM_NAME} ]]; then
  /home/admin/config.scripts/blitz.notify.sh send "$result" \
    --subject "$KRAKEN_MAIL_SUBJECT" \
    --from-name "$KRAKEN_MAIL_FROM_NAME" \
    --from-address "$KRAKEN_MAIL_FROM_ADDRESS"
fi
' > $scriptFile

    sudo mv $scriptFile /home/$USERNAME/$SCRIPT_NAME
    sudo chown $USERNAME:$USERNAME /home/$USERNAME/$SCRIPT_NAME

    echo "OK - the STACKING-SATS-KRAKEN script is now installed."
    echo ""
    echo "Switch to the '$USERNAME' user and adapt the settings in $CONFIG_FILE"

    # setting value in raspi blitz config
    sudo sed -i "s/^stackingSatsKraken=.*/stackingSatsKraken=on/g" /mnt/hdd/raspiblitz.conf
  else
    echo "STACKING-SATS-KRAKEN already installed."
  fi

  cron_count=$(sudo -u $USERNAME crontab -l | grep "$SCRIPT_NAME" -c)
  if [ "${cron_count}" = "0" ]; then
    echo ""
    echo "You might want to set up a cronjob to run the script in regular intervals."
    echo "As the '$USERNAME' user you can run the 'crontab -e' command."
    echo ""
    echo "Here is an example for daily usage at 6:15am ..."
    echo ""
    echo "15 6 * * * /home/$USERNAME/$SCRIPT_NAME"
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** UNINSTALL STACKING-SATS-KRAKEN ***"
  isInstalled=$(sudo ls /home/$USERNAME 2>/dev/null | grep -c 'stacking-sats-kraken')

  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING STACKING-SATS-KRAKEN ***"

    # setting value in raspi blitz config
    sudo sed -i "s/^stackingSatsKraken=.*/stackingSatsKraken=off/g" /mnt/hdd/raspiblitz.conf

    # remove script and config
    sudo rm -rf /home/$USERNAME/$SCRIPT_NAME
    sudo rm -rf /home/$USERNAME/stacking-sats-kraken
    sudo rm -rf /mnt/hdd/app-data/stacking-sats-kraken

    echo "OK STACKING-SATS-KRAKEN removed."

    cron_count=$(sudo -u $USERNAME crontab -l | grep "$SCRIPT_NAME" -c)
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
