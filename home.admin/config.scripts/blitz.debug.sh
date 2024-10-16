#!/bin/bash

# USE THIS SCRIPT FOR BASIC SYSTEM STATUS DEBUG INFO

if [ "$1" == "redact" ]; then

  # get & check parameters
  redactFile=$2
  if [ "${redactFile}" == "" ]; then
    echo "# FAIL: missing second parameter"
    exit 1
  fi
  echo "# redacting file: ${redactFile}"
  if [ $(ls ${redactFile} 2>/dev/null | grep -c "${redactFile}") -lt 1 ]; then
    echo "# FAIL: file does not exist"
    exi 1
  fi

  # redact nodeIDs
  sed -i 's/[a-z0-9]+@/***@/' ${redactFile}

  # redact IPv4s
  sed -i 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/*.*.*.*/' ${redactFile}

  # redact onion adresses
  sed -i 's/[a-z0-9]*.onion/***.onion/' ${redactFile}

  # redact hostname
  sed -i 's/hostname=[^\r\n]*/hostname=*****/' ${redactFile}

  # redact balances
  sed -i 's/[0-9]* mSAT/* mSAT/' ${redactFile}
  sed -i 's/[0-9]*.[0-9]* BTC/* BTC/' ${redactFile}
  sed -i 's/[0-9]*.[0-9]* BTC/* BTC/' ${redactFile}
  sed -i 's/balance=[^\r\n]*/balance=****/' ${redactFile}
  sed -i 's/Server started with public key .+/Server started with public key ****/' ${redactFile}
  
  # c-lightning self info in logs
  sed -i 's/alias [A-Za-z0-9]* /alias *** /' ${redactFile}
  sed -i 's/public key [a-z0-9]*,/public key *** /' ${redactFile}
  sed -i 's/[a-z0-9][a-z0-9]*.onion/###.onion/' ${redactFile}
  sed -i 's/alias=[^\r\n]*/alias=****/' ${redactFile}
  
  # redact lnbits credentials #3520
  sed -i 's/api-key=[a-zA-Z0-9]\+/api-key=***/' ${redactFile}
  sed -i 's/wallet=[a-zA-Z0-9]\+/wallet=***/' ${redactFile}
  sed -i 's/wal=[a-zA-Z0-9]\+/wal=***/' ${redactFile}
  sed -i 's/usr=[a-zA-Z0-9]\+/usr=***/' ${redactFile}
  sed -i 's/user [a-zA-Z0-9]\+/user ***/' ${redactFile}

  # redact i2p #4507
  sed -i 's/[[:alnum:]]*.b32.i2p/***.b32.i2p/' ${redactFile}

  exit 0
fi


# load code software version
source /home/admin/_version.info
codeCommit=$(git -C /home/admin/raspiblitz rev-parse --short HEAD)

## get basic info (its OK if not set yet)
source /home/admin/raspiblitz.info 2>/dev/null
source <(/home/admin/_cache.sh get state setupPhase)
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# for old nodes
if [ ${#network} -eq 0 ]; then
  echo "backup info: network"
  network="bitcoin"
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

echo
echo "***************************************************************"
echo "* RASPIBLITZ DEBUG LOGS "
echo "***************************************************************"
echo "blitzversion: ${codeVersion}"
echo "commit-release: ${codeRelease}"
echo "commit-active: ${codeCommit}"
echo "chainnetwork: ${network} / ${chain}"
uptime
echo

echo "*** FAILED SERVICES ***"
echo "list any servcies with problems: sudo systemctl list-units --failed"
sudo systemctl list-units --failed
echo

echo "*** SETUPPHASE / BOOTSTRAP ***"
echo "see logs: cat /home/admin/raspiblitz.log"
echo "setupPhase--> ${setupPhase}"
echo "state--> ${state}"
if [ "${setupPhase}" != "done" ]; then
  sudo tail -n 20 /home/admin/raspiblitz.log
fi
echo

echo "*** BACKGROUNDSERVICE ***"
echo "to monitor Background service call: sudo journalctl -f -u background"
echo

echo "*** BLOCKCHAIN (MAINNET) SYSTEMD STATUS ***"
sudo systemctl status ${network}d -n2 --no-pager
echo
echo "*** LAST BLOCKCHAIN (MAINNET) ERROR LOGS ***"
echo "sudo journalctl -u ${network}d -b --no-pager -n20"
sudo journalctl -u ${network}d -b --no-pager -n20
echo
echo "*** LAST BLOCKCHAIN (MAINNET) INFO LOGS ***"
echo "sudo tail -n 50 /mnt/hdd/${network}/debug.log"
sudo tail -n 50 /mnt/hdd/${network}${pathAdd}/debug.log
echo

echo "*** LND (MAINNET) SYSTEMD STATUS ***"
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ] || [ "${lnd}" == "1" ]; then
  sudo systemctl status lnd -n2 --no-pager
  echo
  echo "*** LAST LND (MAINNET) ERROR LOGS ***"
  echo "sudo journalctl -u lnd -b --no-pager -n12"
  sudo journalctl -u lnd -b --no-pager -n12
  echo
  echo "*** LAST LND (MAINNET) INFO LOGS ***"
  echo "sudo tail -n 50 /mnt/hdd/lnd/logs/${network}/mainnet/lnd.log"
  sudo tail -n 50 /mnt/hdd/lnd/logs/${network}/mainnet/lnd.log
else
  echo "- OFF by config -"
fi
echo

echo "*** CORE LIGHTNING (MAINNET) SYSTEMD STATUS ***"
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ] || [ "${cl}" == "1" ]; then
  sudo systemctl status lightningd -n2 --no-pager
  echo
  echo "*** LAST CORE LIGHTNING (MAINNET) INFO LOGS ***"
  echo "For details also use command --> cllog"
  echo "sudo tail -n 50 /home/bitcoin/.lightning/${network}/cl.log"
  sudo tail -n 50 /home/bitcoin/.lightning/${network}/cl.log
else
  echo "- not activated -"
fi
echo

echo "*** BLOCKCHAIN (TESTNET) SYSTEMD STATUS ***"
if [ "${testnet}" == "on" ] || [ "${testnet}" == "1" ]; then
  sudo systemctl status t${network}d -n2 --no-pager
  echo
  echo "*** LAST BLOCKCHAIN (TESTNET) ERROR LOGS ***"
  echo "sudo journalctl -u t${network}d -b --no-pager -n8"
  sudo journalctl -u t${network}d -b --no-pager -n8
  echo
  echo "*** LAST BLOCKCHAIN (TESTNET) 20 INFO LOGS ***"
  echo "sudo tail -n 20 /mnt/hdd/${network}/testnet3/debug.log"
  sudo tail -n 20 /mnt/hdd/${network}/testnet3/debug.log
  echo
else
  echo "- OFF by config -"
fi

echo "*** LND (TESTNET) SYSTEMD STATUS ***"
if [ "${tlnd}" == "on" ] || [ "${tlnd}" == "1" ]; then
  sudo systemctl status tlnd -n2 --no-pager
  echo
  echo "*** LAST LND (TESTNET) ERROR LOGS ***"
  echo "sudo journalctl -u tlnd -b --no-pager -n12"
  sudo journalctl -u tlnd -b --no-pager -n12
  echo
  echo "*** LAST 30 LND (TESTNET) INFO LOGS ***"
  echo "sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/testnet/tnd.log"
  sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/testnet/lnd.log
else
  echo "- OFF by config -"
fi
echo

echo "*** CORE LIGHTNING (TESTNET) SYSTEMD STATUS ***"
if [ "${tcl}" == "on" ] || [ "${tcl}" == "1" ]; then
  sudo systemctl status tlightningd -n2 --no-pager
  echo
  echo "*** LAST 30 CORE LIGHTNING (TESTNET) INFO LOGS ***"
  echo "sudo tail -n 30 /home/bitcoin/.lightning/testnet/cl.log"
  sudo tail -n 30 /home/bitcoin/.lightning/testnet/cl.log
else
  echo "- not activated -"
fi
echo

echo "*** BLOCKCHAIN (SIGNET) SYSTEMD STATUS ***"
if [ "${signet}" == "on" ] || [ "${signet}" == "1" ]; then
  sudo systemctl status s${network}d -n2 --no-pager
  echo
  echo "*** LAST BLOCKCHAIN (SIGNET) ERROR LOGS ***"
  echo "sudo journalctl -u s${network}d -b --no-pager -n8"
  sudo journalctl -u s${network}d -b --no-pager -n8
  echo
  echo "*** LAST BLOCKCHAIN (SIGNET) 20 INFO LOGS ***"
  echo "sudo tail -n 20 /mnt/hdd/${network}/signet/debug.log"
  sudo tail -n 20 /mnt/hdd/${network}/signet/debug.log
  echo
else
  echo "- OFF by config -"
fi

echo "*** LND (SIGNET) SYSTEMD STATUS ***"
if [ "${slnd}" == "on" ] || [ "${slnd}" == "1" ]; then
  sudo systemctl status slnd -n2 --no-pager
  echo
  echo "*** LAST LND (SIGNET) ERROR LOGS ***"
  echo "sudo journalctl -u slnd -b --no-pager -n12"
  sudo journalctl -u slnd -b --no-pager -n12
  echo
  echo "*** LAST 30 LND (SIGNET) INFO LOGS ***"
  echo "sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/signet/tnd.log"
  sudo tail -n 30 /mnt/hdd/lnd/logs/${network}/signet/lnd.log
else
  echo "- OFF by config -"
fi
echo

echo "*** CORE LIGHTNING (SIGNET) SYSTEMD STATUS ***"
if [ "${scl}" == "on" ] || [ "${scl}" == "1" ]; then
  sudo systemctl status slightningd -n2 --no-pager
  echo
  echo "*** LAST 30 CORE LIGHTNING (SIGNET) INFO LOGS ***"
  echo "sudo tail -n 30 /home/bitcoin/.lightning/signet/cl.log"
  sudo tail -n 30 /home/bitcoin/.lightning/signet/cl.log
else
  echo "- not activated -"
fi
echo

echo "*** NGINX SYSTEMD STATUS ***"
sudo systemctl status nginx -n2 --no-pager
echo

echo "*** LAST NGINX LOGS ***"
echo "sudo journalctl -u nginx -b --no-pager -n20"
sudo journalctl -u nginx -b --no-pager -n20
echo "--> CHECK CONFIG: sudo nginx -t"
sudo nginx -t 2>&1
echo

echo "*** BLITZAPI STATUS ***"
/home/admin/config.scripts/blitz.web.api.sh info
if [ $(sudo systemctl status blitzapi 2>/dev/null | grep -c "blitzapi.service") -lt 1 ]; then
  echo "- BLITZAPI is not running"
else
  sudo systemctl status blitzapi -n2 --no-pager
  echo

  echo "*** LAST BLITZAPI LOGS ***"
  echo "sudo journalctl -u blitzapi -b --no-pager -n20"
  sudo journalctl -u blitzapi -b --no-pager -n20
  echo
fi

echo "*** BLITZ WebUI STATUS ***"
/home/admin/config.scripts/blitz.web.ui.sh info
echo

if [ "${touchscreen}" == "" ] || [ "${touchscreen}" == "0" ] || [ "${touchscreen}" == "off" ]; then
  echo "- TOUCHSCREEN is OFF by config"
else
  echo
  echo "*** LAST 20 TOUCHSCREEN LOGS ***"
  echo "sudo tail -n 20 /home/pi/.cache/lxsession/LXDE-pi/run.log"
  sudo tail -n 20 /home/pi/.cache/lxsession/LXDE-pi/run.log
  echo
fi

if [ "${loop}" == "" ] || [ "${loop}" == "off" ]; then
  echo "- Loop is OFF by config"
else
  echo
  echo "*** LAST 20 LOOP LOGS ***"
  echo "sudo journalctl -u loopd -b --no-pager -n20"
  sudo journalctl -u loopd -b --no-pager -n20
  echo
fi


if [ "${rtlWebinterface}" == "on" ]; then
  echo
  echo "*** LND-RTL ***"
  sudo systemctl status RTL -n10 --no-pager
  echo
else
  echo "- LND-RTL is OFF by config"
fi

if [ "${crtlWebinterface}" == "on" ]; then
  echo
  echo "*** CL-RTL ***"
  sudo systemctl status cRTL -n10 --no-pager
  echo
else
  echo "- CL-RTL is OFF by config"
fi

if [ "${ElectRS}" == "on" ]; then
  echo
  echo "*** LAST 20 ElectRS LOGS ***"
  echo "sudo journalctl -u electrs -b --no-pager -n20"
  sudo journalctl -u electrs -b --no-pager -n20
  echo
  echo "*** ElectRS Status ***"
  sudo /home/admin/config.scripts/bonus.electrs.sh status
  echo "*** ElectRS Status-Sync ***"
  sudo /home/admin/config.scripts/bonus.electrs.sh status-sync
  echo
else
  echo "- Electrum Rust Server is OFF by config"
fi

if [ "${lit}" == "on" ]; then
  echo
  echo "*** LAST 20 LIT LOGS ***"
  echo "sudo journalctl -u litd -b --no-pager -n20"
  sudo journalctl -u litd -b --no-pager -n20
  echo
else
  echo "- LIT is OFF by config"
fi

if [ "${lndg}" == "on" ]; then
  echo
  echo "*** LNDg Status ***"
  sudo /home/admin/config.scripts/bonus.lndg.sh status
  echo
  echo "*** LNDg JOBS SYSTEMD STATUS ***"
  sudo systemctl status jobs-lndg.service -n2 --no-pager
  echo "sudo tail -n 5 /var/log/lnd_jobs_error.log"
  sudo tail -n 5 /var/log/lnd_jobs_error.log
  echo
  echo "*** LNDg REBALANCER SYSTEMD STATUS ***"
  sudo systemctl status rebalancer-lndg.service -n2 --no-pager
  echo "sudo tail -n 5 /var/log/lnd_rebalancer_error.log"
  sudo tail -n 5 /var/log/lnd_rebalancer_error.log
  echo
  echo "*** LNDg HTLC-STREAM SYSTEMD STATUS ***"
  sudo systemctl status htlc-stream-lndg.service -n2 --no-pager
  echo "sudo tail -n 5 /var/log/lnd_htlc_stream_error.log"
  sudo tail -n 5 /var/log/lnd_htlc_stream_error.log
  echo
  echo "*** LNDg GUNICORN SERVER SYSTEMD STATUS ***"
  sudo systemctl status gunicorn.service -n2 --no-pager
  echo "sudo tail -n 5 /var/log/gunicorn_error.log"
  sudo tail -n 5 /var/log/gunicorn_error.log 2>/dev/null
  echo
  echo "*** LAST 10 LNDg LOGS ***"
  echo "sudo journalctl -u lndg -b --no-pager -n10"
  sudo journalctl -u lndg -b --no-pager -n20
  echo
else
  echo "- LNDg is OFF by config"
fi

if [ "${BTCPayServer}" == "on" ]; then
  echo
  echo "*** LAST 20 BTCPayServer LOGS ***"
  echo "sudo journalctl -u btcpayserver -b --no-pager -n20"
  sudo journalctl -u btcpayserver -b --no-pager -n20
  echo
else
  echo "- BTCPayServer is OFF by config"
fi

if [ "${BTCRPCexplorer}" == "on" ]; then
  echo
  echo "*** LAST 20 BTC-RPC-Explorer LOGS ***"
  echo "sudo journalctl -u btc-rpc-explorer -b --no-pager -n20"
  sudo journalctl -u btc-rpc-explorer -b --no-pager -n20
  echo
else
  echo "- BTC-RPC-Explorer is OFF by config"
fi

if [ "${LNBits}" == "on" ]; then
  echo
  echo "*** LAST 20 LNbits LOGS ***"
  echo "sudo journalctl -u lnbits -b --no-pager -n20"
  sudo journalctl -u lnbits -b --no-pager -n20
  echo
else
  echo "- LNbits is OFF by config"
fi

if [ "${thunderhub}" == "on" ]; then
  echo
  echo "*** LAST 20 Thunderhub LOGS ***"
  echo "sudo journalctl -u thunderhub -b --no-pager -n20"
  sudo journalctl -u thunderhub -b --no-pager -n20
  echo
else
  echo "- Thunderhub is OFF by config"
fi

if [ "${specter}" == "on" ]; then
  echo
  echo "*** LAST 20 SPECTER LOGS ***"
  echo "sudo journalctl -u specter -b --no-pager -n20"
  sudo journalctl -u specter -b --no-pager -n20
  echo
else
  echo "- SPECTER is OFF by config"
fi

if [ "${sphinxrelay}" == "on" ]; then
  echo
  echo "*** LAST 20 SPHINX LOGS ***"
  echo "sudo journalctl -u sphinxrelay -b --no-pager -n20"
  sudo journalctl -u sphinxrelay -b --no-pager -n20
  echo
else
  echo "- SPHINX is OFF by config"
fi

if [ "${fints}" == "on" ]; then  
  echo
  echo "*** LAST 20 FINTS LOGS ***"
  echo "sudo journalctl -u fints -b --no-pager -n20"
  sudo journalctl -u fints -b --no-pager -n20
  echo "sudo tail -n 30 /home/fints/log/fuelifints.log"
  sudo tail -n 30 /home/fints/log/fuelifints.log
else
  echo "- FINTS is OFF by config"
fi

if [ "${publicpool}" == "on" ]; then  
  echo
  echo "*** LAST 20 PUBLIPOOL LOGS ***"
  echo "sudo journalctl -u publicpool -b --no-pager -n20"
  sudo journalctl -u publicpool -b --no-pager -n20
else
  echo "- PUBLICPOOL is OFF by config"
fi

echo
echo "*** MOUNTED DRIVES ***"
echo "df -T -h"
df -T -h

echo
echo "*** SD CARD HOMES ***"
echo "sudo du -ahd1 /home"
sudo du -ahd1 /home

echo
echo "*** LOGFILES ***"
sudo journalctl --disk-usage
sudo du -sh /var/log

echo
echo "*** DATADRIVE ***"
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
sudo /home/admin/config.scripts/blitz.datadrive.sh status
sudo smartctl -a /dev/${datadisk}
echo

echo "*** NETWORK ***"
sudo /home/admin/config.scripts/internet.sh status | grep 'network_device\|localip\|dhcp'
echo

echo
echo "*** ZRAM ***"
sudo /home/admin/config.scripts/blitz.zram.sh status
echo

echo "*** HARDWARE TEST RESULTS ***"
sudo vcgencmd get_throttled 2>/dev/null
source <(/home/admin/_cache.sh get system_count_undervoltage)
showImproveInfo=0
if [ ${#system_count_undervoltage} -gt 0 ]; then
  echo "UndervoltageReports in Logs: ${system_count_undervoltage}"
  if [ ${system_count_undervoltage} -gt 0 ]; then
    showImproveInfo=1
  fi
fi
echo

echo "*** SYSTEM CACHE STATUS ***"
/home/admin/_cache.sh "export" system_
/home/admin/_cache.sh "export" ln_default | grep -v "ln_default_address"
/home/admin/_cache.sh "export" btc_default | grep -v "btc_default_address"

echo "*** POSSIBLE ERROR REPORTS ***"
ls -1  /home/admin/error* 2>/dev/null
echo

echo
echo "*** OPTION: SHARE THIS DEBUG OUTPUT ***"
echo "An easy way to share this debug output on GitHub or on a support chat"
echo "Use the following command and share the resulting link using termbin.com service and tor proxy:"
echo " debug -l"
echo "If tor is failing and you don't mind leaking your ip address to the termbin service, use without tor:"
echo " debug -l -n"
echo
