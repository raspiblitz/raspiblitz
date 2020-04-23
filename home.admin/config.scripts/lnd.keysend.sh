#!/bin/bash

# based on: https://github.com/rootzoll/raspiblitz/issues/1000

if [ $# -eq 0 ]; then
 echo "activate/deactivate LND keysend feature"
 echo "lnd.keysend.sh [on|off|status]"
 exit 1
fi

# note: this script is not run during provision/recovery 
# because if the lnd extra parameter is set in raspiblitz.conf,
# it will automatically be used by the service 

source /mnt/hdd/raspiblitz.conf

parameter=$1
if [ "${parameter}" == "on" ]; then

  # store to raspiblitz config (delete old line / add new)
  sudo sed -i '/lndExtraParameter=.*/d' /mnt/hdd/raspiblitz.conf
  echo "lndExtraParameter='--accept-keysend'" >> /mnt/hdd/raspiblitz.conf

  echo "# OK - keysend feature is switched ON"
  echo "# LND or RaspiBlitz needs restart"

elif [ "${parameter}" == "off" ]; then

 # just remove the parameter from the config file
 sudo sed -i '/lndExtraParameter=.*/d' /mnt/hdd/raspiblitz.conf

 echo "# OK - keysend feature is switched OFF"
 echo "# LND or RaspiBlitz needs restart"

elif [ "${parameter}" == "status" ]; then

  keysendOn=$(echo "${lndExtraParameter}" | grep -c 'accept-keysend')
  keysendRunning=$(sudo systemctl status lnd | grep -c 'accept-keysend')
  echo "keysendOn=${keysendOn}"
  echo "keysendRunning=${keysendRunning}"

else
  echo "err='unknown parameter'"
fi
