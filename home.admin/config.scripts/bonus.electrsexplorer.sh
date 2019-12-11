# config script to make BTC-RPC-Explorer use Electrs if both active

source /mnt/hdd/raspiblitz.conf

# determine nodeJS DISTRO
isARM=$(uname -m | grep -c 'arm')   
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
isX86_32=$(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786')
if [ ${isARM} -eq 1 ] ; then
DISTRO="linux-armv7l"
fi
if [ ${isAARCH64} -eq 1 ] ; then
DISTRO="linux-arm64"
fi
if [ ${isX86_64} -eq 1 ] ; then
DISTRO="linux-x64"
fi
if [ ${isX86_32} -eq 1 ] ; then
echo "FAIL: No X86 32bit build available - will abort setup"
exit 1
fi
if [ ${#DISTRO} -eq 0 ]; then
echo "FAIL: Was not able to determine architecture"
exit 1
fi

if [ "${BTCRPCexplorer}" = "on" ] & [ "${ElectRS}" = "on" ]; then
  ## Enable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  if [ $(sudo -u electrs lsof -i | grep -c 50001) -gt 0 ]; then
      echo "electrs is active - switching address API support on in BTC-RPC-Explorer"
      sudo -u bitcoin sed -i 's/^BTCEXP_ADDRESS_API=none/BTCEXP_ADDRESS_API=electrumx/g' /home/bitcoin/.config/btc-rpc-explorer.env

      # create ExecStart=/home/bitcoin/btc-rpc-explorer.run.sh     
      cat > /home/admin/btc-rpc-explorer.run.sh <<EOF
#!/bin/bash
echo "Waiting Electrs on port 50001..."
while [ $(sudo -u electrs lsof -i | grep -c 50001) -eq 0 ]; do
  sleep 1
done
echo "Electrs started, launching BTC-RPC-Explorer..."
/usr/local/lib/nodejs/node-$(node -v)-$DISTRO/bin/btc-rpc-explorer
EOF
     sudo mv /home/admin/btc-rpc-explorer.run.sh /home/bitcoin/btc-rpc-explorer.run.sh
     sudo chown bitcoin:bitcoin /home/bitcoin/btc-rpc-explorer.run.sh
     sudo chmod +x /home/bitcoin/btc-rpc-explorer.run.sh

     sudo sed -i "s/^ExecStart=\/usr\/local\/lib\/nodejs\/node-$(node -v)-$DISTRO\/bin\/btc-rpc-explorer/ExecStart=\/home\/bitcoin\/btc-rpc-explorer.run.sh/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo systemctl daemon-reload
     sudo systemctl restart btc-rpc-explorer
   
   else
     echo "electrs is not active - switching address API support off in BTC-RPC-Explorer"
     sudo -u bitcoin sed -i 's/^BTCEXP_ADDRESS_API=electrumx/BTCEXP_ADDRESS_API=none/g' /home/bitcoin/.config/btc-rpc-explorer.env
     
     sudo sed -i "s/^ExecStart=\/home\/bitcoin\/btc-rpc-explorer.run.sh/ExecStart=\/usr\/local\/lib\/nodejs\/node-$(node -v)-$DISTRO\/bin\/btc-rpc-explorer/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo systemctl daemon-reload
     sudo systemctl restart btc-rpc-explorer
   fi

else
  ## Disable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  if [ "${BTCRPCexplorer}" = "on" ]; then
     echo "electrs is not active - switching address API support off in BTC-RPC-Explorer"
     sudo -u bitcoin sed -i 's/^BTCEXP_ADDRESS_API=electrumx/BTCEXP_ADDRESS_API=none/g' /home/bitcoin/.config/btc-rpc-explorer.env
     
     sudo sed -i "s/^ExecStart=\/home\/bitcoin\/btc-rpc-explorer.run.sh/ExecStart=\/usr\/local\/lib\/nodejs\/node-$(node -v)-$DISTRO\/bin\/btc-rpc-explorer/g" /etc/systemd/system/btc-rpc-explorer.service
     sudo systemctl daemon-reload
     sudo systemctl restart btc-rpc-explorer
  fi
fi
