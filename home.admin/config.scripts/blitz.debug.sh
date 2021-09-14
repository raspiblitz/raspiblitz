#!/bin/bash

# USE THIS SCRIPT FOR BASIC SYSTEM STATUS DEBUG INFO

# load code software version
source /home/admin/_version.info

## get basic info (its OK if not set yet)
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# for old nodes
if [ ${#network} -eq 0 ]; then
  echo "backup info: network"
  network="bitcoin"
  litecoinActive=$(sudo ls /mnt/hdd/litecoin/litecoin.conf | grep -c 'litecoin.conf')
  if [ ${litecoinActive} -eq 1 ]; then
    network="litecoin"
  fi
fi

# for non final config nodes
if [ ${#chain} -eq 0 ]; then
  echo "backup info: chain"
  chain="test"
  isMainChain=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep "testnet=0" -c)
  if [ ${isMainChain} -gt 0 ];then
    chain="main"
  fi
fi

clear
echo ""
echo "***************************************************************"
echo "* RASPIBLITZ DEBUG LOGS "
echo "***************************************************************"
echo "blitzversion: ${codeVersion}"
echo "chainnetwork: ${network} / ${chain}"
uptime
echo ""

echo "*** SETUPPHASE / BOOTSTRAP ***"
echo "see logs: cat /home/admin/raspiblitz.log"
echo "setupPhase--> ${setupPhase}"
echo "state--> ${state}"
if [ "${setupPhase}" != "done" ]; then
  sudo tail -n 20 /home/admin/raspiblitz.log
fi
echo ""

echo "*** BACKGROUNDSERVICE ***"
echo "to monitor Background service call: sudo journalctl -f -u background"
echo ""

echo "*** BLOCKCHAIN (MAINNET) SYSTEMD STATUS ***"
sudo systemctl status ${network}d -n2 --no-pager
echo ""
echo "*** LAST BLOCKCHAIN (MAINNET) ERROR LOGS ***"
echo "sudo journalctl -u ${network}d -b --no-pager -n8"
sudo journalctl -u ${network}d -b --no-pager -n8
cat /home/admin/systemd.blockchain.log | grep "ERROR" | tail -n -2
echo ""
echo "*** LAST BLOCKCHAIN (MAINNET) 20 INFO LOGS ***"
echo "sudo tail -n 20 /mnt/hdd/${network}/debug.log"
sudo tail -n 20 /mnt/hdd/${network}${pathAdd}/debug.log
echo ""

echo "*** LND (MAINNET) SYSTEMD STATUS ***"
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ] || [ "${lnd}" == "1" ]; then
  sudo systemctl status lnd -n2 --no-pager
  echo ""
  echo "*** LAST LND (MAINNET) ERROR LOGS ***"
  echo "sudo journalctl -u lnd -b --no-pager -n12"
  sudo journalctl -u lnd -b --no-pager -n12
  cat /home/admin/systemd.lightning.log | grep "ERROR" | tail -n -1
  echo ""
  echo "*** LAST 30 LND (MAINNET) INFO LOGS ***"
  echo "sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/mainnet/lnd.log"
  sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/mainnet/lnd.log
else
  echo "- OFF by config -"
fi
echo ""

echo "*** C-LIGHTNING (MAINNET) SYSTEMD STATUS ***"
if [ "${lightning}" == "cln" ] || [ "${cln}" == "on" ] || [ "${cln}" == "1" ]; then
  sudo systemctl status lightningd -n2 --no-pager
  echo ""
  echo "*** LAST 30 C-LIGHTNING (MAINNET) INFO LOGS ***"
  echo "sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log"
  sudo tail -n 30 /home/bitcoin/.lightning/${network}/cl.log
else
  echo "- not activated -"
fi
echo ""

echo "*** BLOCKCHAIN (TESTNET) SYSTEMD STATUS ***"
if [ "${testnet}" == "on" ] || [ "${testnet}" == "1" ]; then
  sudo systemctl status t${network}d -n2 --no-pager
  echo ""
  echo "*** LAST BLOCKCHAIN (TESTNET) ERROR LOGS ***"
  echo "sudo journalctl -u t${network}d -b --no-pager -n8"
  sudo journalctl -u t${network}d -b --no-pager -n8
  echo ""
  echo "*** LAST BLOCKCHAIN (TESTNET) 20 INFO LOGS ***"
  echo "sudo tail -n 20 /mnt/hdd/${network}/tdebug.log"
  sudo tail -n 20 /mnt/hdd/${network}/tdebug.log
  echo ""
else
  echo "- OFF by config -"
fi

echo "*** LND (TESTNET) SYSTEMD STATUS ***"
if [ "${tlnd}" == "on" ] || [ "${tlnd}" == "1" ]; then
  sudo systemctl status tlnd -n2 --no-pager
  echo ""
  echo "*** LAST LND (TESTNET) ERROR LOGS ***"
  echo "sudo journalctl -u tlnd -b --no-pager -n12"
  sudo journalctl -u tlnd -b --no-pager -n12
  echo ""
  echo "*** LAST 30 LND (TESTNET) INFO LOGS ***"
  echo "sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/testnet/tnd.log"
  sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/testnet/lnd.log
else
  echo "- OFF by config -"
fi
echo ""

echo "*** C-LIGHTNING (TESTNET) SYSTEMD STATUS ***"
if [ "${tcln}" == "on" ] || [ "${tcln}" == "1" ]; then
  sudo systemctl status tlightningd -n2 --no-pager
  echo ""
  echo "*** LAST 30 C-LIGHTNING (TESTNET) INFO LOGS ***"
  echo "sudo tail -n 30 /home/bitcoin/.lightning/testnet/cl.log"
  sudo tail -n 30 /home/bitcoin/.lightning/testnet/cl.log
else
  echo "- not activated -"
fi
echo ""

echo "*** BLOCKCHAIN (SIGNET) SYSTEMD STATUS ***"
if [ "${signet}" == "on" ] || [ "${signet}" == "1" ]; then
  sudo systemctl status s${network}d -n2 --no-pager
  echo ""
  echo "*** LAST BLOCKCHAIN (SIGNET) ERROR LOGS ***"
  echo "sudo journalctl -u s${network}d -b --no-pager -n8"
  sudo journalctl -u s${network}d -b --no-pager -n8
  echo ""
  echo "*** LAST BLOCKCHAIN (SIGNET) 20 INFO LOGS ***"
  echo "sudo tail -n 20 /mnt/hdd/${network}/sdebug.log"
  sudo tail -n 20 /mnt/hdd/${network}/sdebug.log
  echo ""
else
  echo "- OFF by config -"
fi

echo "*** LND (SIGNET) SYSTEMD STATUS ***"
if [ "${slnd}" == "on" ] || [ "${slnd}" == "1" ]; then
  sudo systemctl status slnd -n2 --no-pager
  echo ""
  echo "*** LAST LND (SIGNET) ERROR LOGS ***"
  echo "sudo journalctl -u slnd -b --no-pager -n12"
  sudo journalctl -u slnd -b --no-pager -n12
  echo ""
  echo "*** LAST 30 LND (SIGNET) INFO LOGS ***"
  echo "sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/signet/tnd.log"
  sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/signet/lnd.log
else
  echo "- OFF by config -"
fi
echo ""

echo "*** C-LIGHTNING (SIGNET) SYSTEMD STATUS ***"
if [ "${scln}" == "on" ] || [ "${scln}" == "1" ]; then
  sudo systemctl status slightningd -n2 --no-pager
  echo ""
  echo "*** LAST 30 C-LIGHTNING (SIGNET) INFO LOGS ***"
  echo "sudo tail -n 30 /home/bitcoin/.lightning/signet/cl.log"
  sudo tail -n 30 /home/bitcoin/.lightning/signet/cl.log
else
  echo "- not activated -"
fi
echo ""

echo "*** NGINX SYSTEMD STATUS ***"
sudo systemctl status nginx -n2 --no-pager
echo ""

echo "*** LAST NGINX LOGS ***"
echo "sudo journalctl -u nginx -b --no-pager -n20"
sudo journalctl -u nginx -b --no-pager -n20
echo "--> CHECK CONFIG: sudo nginx -t"
sudo nginx -t
echo ""

echo "*** BLITZAPI SYSTEMD STATUS ***"
sudo systemctl status blitzapi -n2 --no-pager
echo ""

echo "*** LAST BLITZAPI LOGS ***"
echo "sudo journalctl -u blitzapi -b --no-pager -n20"
sudo journalctl -u nginx -b --no-pager -n20
echo "--> CHECK CONFIG: sudo nginx -t"
sudo nginx -t
echo ""

if [ "${touchscreen}" == "" ] || [ "${touchscreen}" == "0" ] || [ "${touchscreen}" == "off" ]; then
  echo "- TOUCHSCREEN is OFF by config"
else
  echo ""
  echo "*** LAST 20 TOUCHSCREEN LOGS ***"
  echo "sudo tail -n 20 /home/pi/.cache/lxsession/LXDE-pi/run.log"
  sudo tail -n 20 /home/pi/.cache/lxsession/LXDE-pi/run.log
  echo ""
fi

if [ "${loop}" == "" ] || [ "${loop}" == "off" ]; then
  echo "- Loop is OFF by config"
else
  echo ""
  echo "*** LAST 20 LOOP LOGS ***"
  echo "sudo journalctl -u loopd -b --no-pager -n20"
  sudo journalctl -u loopd -b --no-pager -n20
  echo ""
fi

if [ "${rtlWebinterface}" == "" ] || [ "${rtlWebinterface}" == "off" ]; then
  echo "- LND-RTL is OFF by config"
else
  echo ""
  echo "*** LND-RTL ***"
  sudo systemctl status RTL -n10 --no-pager
  echo ""
fi

if [ "${crtlWebinterface}" == "" ] || [ "${crtlWebinterface}" == "off" ]; then
  echo "- CLN-RTL is OFF by config"
else
  echo ""
  echo "*** CLN-RTL ***"
  sudo systemctl status cRTL -n10 --no-pager
  echo ""
fi

if [ "${ElectRS}" == "" ] || [ "${ElectRS}" == "off" ]; then
  echo "- Electrum Rust Server is OFF by config"
else
  echo ""
  echo "*** LAST 20 ElectRS LOGS ***"
  echo "sudo journalctl -u electrs -b --no-pager -n20"
  sudo journalctl -u electrs -b --no-pager -n20
  echo ""
  echo "*** ElectRS Status ***"
  sudo /home/admin/config.scripts/bonus.electrs.sh status
  echo ""
fi

if [ "${lit}" == "" ] || [ "${lit}" == "off" ]; then
  echo "- LIT is OFF by config"
else
  echo ""
  echo "*** LAST 20 LIT LOGS ***"
  echo "sudo journalctl -u litd -b --no-pager -n20"
  sudo journalctl -u litd -b --no-pager -n20
  echo ""
fi

if [ "${BTCPayServer}" == "" ] || [ "${BTCPayServer}" == "off" ]; then
  echo "- BTCPayServer is OFF by config"
else
  echo ""
  echo "*** LAST 20 BTCPayServer LOGS ***"
  echo "sudo journalctl -u btcpayserver -b --no-pager -n20"
  sudo journalctl -u btcpayserver -b --no-pager -n20
  echo ""
fi

if [ "${LNBits}" == "" ] || [ "${LNBits}" == "off" ]; then
  echo "- LNbits is OFF by config"
else
  echo ""
  echo "*** LAST 20 LNbits LOGS ***"
  echo "sudo journalctl -u lnbits -b --no-pager -n20"
  sudo journalctl -u lnbits -b --no-pager -n20
  echo ""
fi

if [ "${thunderhub}" == "" ] || [ "${thunderhub}" == "0" ] | [ "${thunderhub}" == "off" ]; then
  echo "- Thunderhub is OFF by config"
else
  echo ""
  echo "*** LAST 20 Thunderhub LOGS ***"
  echo "sudo journalctl -u thunderhub -b --no-pager -n20"
  sudo journalctl -u thunderhub -b --no-pager -n20
  echo ""
fi

if [ "${specter}" == "" ] || [ "${specter}" == "0" ] || [ "${specter}" == "off" ]; then
  echo "- SPECTER is OFF by config"
else
  echo ""
  echo "*** LAST 20 SPECTER LOGS ***"
  echo "sudo journalctl -u specter -b --no-pager -n20"
  sudo journalctl -u specter -b --no-pager -n20
  echo ""
fi

if [ "${sphinxrelay}" == "" ] || [ "${sphinxrelay}" == "0" ] || [ "${sphinxrelay}" == "off" ]; then
  echo "- SPHINX is OFF by config"
else
  echo ""
  echo "*** LAST 20 SPHINX LOGS ***"
  echo "sudo journalctl -u sphinxrelay -b --no-pager -n20"
  sudo journalctl -u sphinxrelay -b --no-pager -n20
  echo ""
fi

echo ""
echo "*** MOUNTED DRIVES ***"
df -T -h
echo ""

echo ""
echo "*** DATADRIVE ***"
sudo /home/admin/config.scripts/blitz.datadrive.sh status
echo ""

echo "*** NETWORK ***"
sudo /home/admin/config.scripts/internet.sh status | grep 'network_device\|localip\|dhcp'
echo ""

echo "*** HARDWARE TEST RESULTS ***"
showImproveInfo=0
if [ ${#undervoltageReports} -gt 0 ]; then
  echo "UndervoltageReports in Logs: ${undervoltageReports}"
  if [ ${undervoltageReports} -gt 0 ]; then
    showImproveInfo=1
  fi
fi
echo ""

echo "*** SYSTEM STATUS (can take some seconds to gather) ***"
sudo /home/admin/config.scripts/blitz.statusscan.sh
echo ""

echo "*** OPTION: SHARE THIS DEBUG OUTPUT ***"
echo "An easy way to share this debug output on GitHub or on a support chat"
echo "use the following command and share the resulting link:"
echo "debug | nc termbin.com 9999"
echo ""
