# config script to make BTC-RPC-Explorer use Electrs if both active
# thx to PatrickScheich for improving the script

source /mnt/hdd/raspiblitz.conf

# explorer start script (waits to start btc-rpc-explorer until eletrs is responsive)
explorerStartDir="/home/admin/system"
explorerStartScript="${explorerStartDir}/btc-rpc-explorer.run.sh"
explorerStartScriptEscaped=$(echo "${explorerStartScript}" | sed 's/\//\\\//g')

# check if "^BTCEXP_ADDRESS_API=electrumx"
btcaddrapiEnabled=$(sudo cat /home/btcrpcexplorer/.config/btc-rpc-explorer.env 2>/dev/null | grep -c "^BTCEXP_ADDRESS_API=electrumx")

# check if service starts the shell script "btc-rpc-explorer.run.sh"
serviceStartsScript=$(sudo cat /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c "^ExecStart=${explorerStartScript}")

# optional return status
if [ "$1" = "status" ]; then
  if [ "${BTCRPCexplorer}" = "" ]; then
    BTCRPCexplorer="off"
  fi
  if [ "${ElectRS}" = "" ]; then
    ElectRS="off"
  fi
  echo "BTCRPCexplorer=${BTCRPCexplorer}"  
  echo "ElectRS=${ElectRS}"
  echo "explorerStartScript='${explorerStartScript}'"
  echo "explorerStartScriptEscaped='${explorerStartScriptEscaped}'"
  echo "# if electrum is set as address api in btc-prc-explorer"
  echo "btcaddrapiEnabled=${btcaddrapiEnabled}"
  echo "# if btc-prc-explorer is started by systemd with btc-rpc-explorer.run.sh"
  echo "# that waits for electrum to become responsive"
  echo "serviceStartsScript=${serviceStartsScript}"
  exit 0
fi

# variable to track if service restart is needed
serviceNeedsRestart=0

# both services are "switched on" in raspiblitz.conf
if [ "${BTCRPCexplorer}" = "on" ] & [ "${ElectRS}" = "on" ]; then

  # make sure that "btc-rpc-explorer.run.sh" exists...
  # if it does not exist, create it and make it executable
  # it is fine to create the script, even the BTC-RPC-Explorer might be started directly
  if [ ! -f ${explorerStartScript} ]; then
    echo "script \"${explorerStartScript}\" does not exist, create it and make it executable"
    sudo -u admin mkdir -p ${explorerStartDir}
    cat > ${explorerStartScript} <<EOF
#!/bin/bash
echo "Waiting Electrs on port 50001..."
while [ \$(sudo -u electrs lsof -i | grep -c 50001) -eq 0 ]; do
  sleep 1
done
echo "Electrs started, launching BTC-RPC-Explorer..."
cd /home/btcrpcexplorer/btc-rpc-explorer
sudo -u btcrpcexplorer /usr/bin/npm start
EOF
  sudo chmod +x ${explorerStartScript}
  fi

  # electrs service is online
  if [ $(sudo -u electrs lsof -i | grep -c 50001) -gt 0 ]; then
    echo "electrs is online"

    # if address API support is not yet enabled => change it in "/home/btcrpcexplorer/.config/btc-rpc-explorer.env"
    if [ ${btcaddrapiEnabled} -ne 1 ]; then
      echo "electrs is active - switching address API support on in BTC-RPC-Explorer"
      sudo -u btcrpcexplorer sed -i 's/^BTCEXP_ADDRESS_API=none/BTCEXP_ADDRESS_API=electrumx/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env
      # make sure to restart the service
      serviceNeedsRestart=1
    else
      echo "electrs is active - address API support in BTC-RPC-Explorer is already enabled, nothing to do here"
    fi

    # make sure that explorer is started thru script
    if [ ${serviceStartsScript} -ne 1 ]; then
      echo "btc-rpc-explorer.service change to start via script: ${explorerStartScript}"
      sudo sed -i "s/^ExecStart=\/usr\/bin\/npm start/ExecStart=${explorerStartScriptEscaped}/g" /etc/systemd/system/btc-rpc-explorer.service
      sudo sed -i "s/^User=.*/User=admin/g" /etc/systemd/system/btc-rpc-explorer.service
      # make sure to restart the service
      serviceNeedsRestart=1
    else
      echo "electrs is active - service start via script is already enabled, nothing to do here"
    fi

  # electrs service is offline
  else
    echo "electrs is offline"

    # make sure to switch address API support off
    if [ ${btcaddrapiEnabled} -ne 1 ]; then
      echo "electrs is not active - address API support in BTC-RPC-Explorer is already disabled, nothing to do here"
    else
      echo "electrs is not active - switching address API support off in BTC-RPC-Explorer"
      sudo -u btcrpcexplorer sed -i 's/^BTCEXP_ADDRESS_API=electrumx/BTCEXP_ADDRESS_API=none/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env
      # make sure to restart the service
      serviceNeedsRestart=1
    fi

    # make sure to start explorer directly
    if [ ${serviceStartsScript} -ne 1 ]; then
      echo "electrs is not active - service direct start is already enabled, nothing to do here"
    else
      echo "btc-rpc-explorer.service change to start directly"
      sudo sed -i "s/^ExecStart=${explorerStartScriptEscaped}/ExecStart=\/usr\/bin\/npm start/g" /etc/systemd/system/btc-rpc-explorer.service
      sudo sed -i "s/^User=.*/User=btcrpcexplorer/g" /etc/systemd/system/btc-rpc-explorer.service
      # make sure to restart the service
      serviceNeedsRestart=1
    fi
  fi

# both services are NOT "switched on" in raspiblitz.conf
else

  # electrs if OFF and explorer ON
  if [ "${BTCRPCexplorer}" = "on" ]; then

    # Disable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
    echo "electrs is off in raspiblitz.conf"
    if [ ${btcaddrapiEnabled} -ne 1 ]; then
      echo "electrs is not active - address API support in BTC-RPC-Explorer is already disabled, nothing to do here"
    else
      echo "electrs is not active - switching address API support off in BTC-RPC-Explorer"
      sudo -u btcrpcexplorer sed -i 's/^BTCEXP_ADDRESS_API=electrumx/BTCEXP_ADDRESS_API=none/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env
      # make sure to restart the service
      serviceNeedsRestart=1
    fi

    # make sure that service is started directly
    if [ ${serviceStartsScript} -ne 1 ]; then
      echo "electrs is not active - service direct start is already enabled, nothing to do here"
    else
      echo "btc-rpc-explorer.service change to start directly"
      sudo sed -i "s/^ExecStart=${explorerStartScriptEscaped}/ExecStart=\/usr\/bin\/npm start/g" /etc/systemd/system/btc-rpc-explorer.service
      sudo sed -i "s/^User=.*/User=btcrpcexplorer/g" /etc/systemd/system/btc-rpc-explorer.service
      # make sure to restart the service
      serviceNeedsRestart=1
    fi

  fi
fi

if [ ${serviceNeedsRestart} -eq 1 ]; then
  echo "BTC-RPC-Explorer service needs restart"
  sudo systemctl daemon-reload
  sudo systemctl restart btc-rpc-explorer
fi