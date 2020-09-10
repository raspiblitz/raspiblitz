# config script to make BTC-RPC-Explorer use Electrs if both active

source /mnt/hdd/raspiblitz.conf

if [ "${BTCRPCexplorer}" = "on" ] & [ "${ElectRS}" = "on" ]; then
  ## Enable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  if [ $(sudo -u electrs lsof -i | grep -c 50001) -gt 0 ]; then
      echo "electrs is active - switching address API support on in BTC-RPC-Explorer"
      sudo -u btcrpcexplorer sed -i 's/^BTCEXP_ADDRESS_API=none/BTCEXP_ADDRESS_API=electrumx/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env

      # create ExecStart=/home/admin/btc-rpc-explorer.run.sh     
      cat > /home/admin/btc-rpc-explorer.run.sh <<EOF
#!/bin/bash
echo "Waiting Electrs on port 50001..."
while [ $(sudo -u electrs lsof -i | grep -c 50001) -eq 0 ]; do
  sleep 1
done
echo "Electrs started, launching BTC-RPC-Explorer..."
cd /home/btcrpcexplorer/btc-rpc-explorer
sudo -u btcrpcexplorer /usr/bin/npm start
EOF
     sudo chmod +x /home/admin/btc-rpc-explorer.run.sh

     sudo sed -i "s/^ExecStart=\/usr\/bin\/npm start/ExecStart=\/home\/admin\/btc-rpc-explorer.run.sh/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo sed -i "s/^User=.*/User=admin/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo systemctl daemon-reload
     sudo systemctl restart btc-rpc-explorer
   
   else
     echo "electrs is not active - switching address API support off in BTC-RPC-Explorer"
     sudo -u btcrpcexplorer sed -i 's/^BTCEXP_ADDRESS_API=electrumx/BTCEXP_ADDRESS_API=none/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env
     
     sudo sed -i "s/^ExecStart=\/home\/admin\/btc-rpc-explorer.run.sh/ExecStart=\/usr\/bin\/npm start/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo sed -i "s/^User=.*/User=btcrpcexplorer/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo systemctl daemon-reload
     sudo systemctl restart btc-rpc-explorer
   fi

else
  ## Disable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  if [ "${BTCRPCexplorer}" = "on" ]; then
     echo "electrs is not active - switching address API support off in BTC-RPC-Explorer"
     sudo -u btcrpcexplorer sed -i 's/^BTCEXP_ADDRESS_API=electrumx/BTCEXP_ADDRESS_API=none/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env
     
     sudo sed -i "s/^ExecStart=\/home\/admin\/btc-rpc-explorer.run.sh/ExecStart=\/usr\/bin\/npm start/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo sed -i "s/^User=.*/User=btcrpcexplorer/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo systemctl daemon-reload
     sudo systemctl restart btc-rpc-explorer
  fi
fi
