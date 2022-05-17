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

  # store to raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh delete lndExtraParameter
  /home/admin/config.scripts/blitz.conf.sh set lndKeysend "on"

  echo "# OK - keysend feature is switched ON"
  echo "# will be enfored by lnd.check.sh prestart"
  echo "# LND or RaspiBlitz needs restart"

elif [ "${parameter}" == "off" ]; then

 # just remove the parameter from the config file
 /home/admin/config.scripts/blitz.conf.sh delete lndExtraParameter
 /home/admin/config.scripts/blitz.conf.sh delete lndKeysend
 sudo sed -i '/accept-keysend=.*/d' /mnt/hdd/lnd/lnd.conf 2>/dev/null
 sudo sed -i '/accept-keysend=.*/d' /mnt/hdd/lnd/tlnd.conf 2>/dev/null
 sudo sed -i '/accept-keysend=.*/d' /mnt/hdd/lnd/slnd.conf 2>/dev/null

 echo "# OK - keysend enforcement is switched OFF"
 echo "# LND or RaspiBlitz needs restart"

elif [ "${parameter}" == "status" ]; then

  keysendOn=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c '^lndKeysend=on')
  keysendRunning=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c '^accept-keysend\=true')
  echo "keysendOn=${keysendOn}"
  echo "keysendRunning=${keysendRunning}"

else
  echo "err='unknown parameter'"
fi
