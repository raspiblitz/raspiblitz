#!/bin/bash

# This script gets called from a fresh SD card
# starting up that has an config file on HDD
# from old RaspiBlitz or manufacturer to
# to install and config services

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# debug info
echo "STARTED Provisioning --> see logs in ${logFile}"
echo "STARTED Provisioning from preset config file" >> ${logFile}
sudo sed -i "s/^message=.*/message='Provisioning from Config'/g" ${infoFile}

# check if there is a config file
configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
  echo "FAIL: no config file (${configFile}) found to run provision!" >> ${logFile}
  exit 1
fi

# check that default parameter exist in config
parameterExists=$(cat /mnt/hdd/raspiblitz.conf | grep -c "lndExtraParameter=")
if [ ${parameterExists} -eq 0 ]; then
  echo "lndExtraParameter=''" >> ${configFile}
fi

# check if file system was expanded to full capacity and sd card is bigger than 8GB
# see: https://github.com/rootzoll/raspiblitz/issues/936
echo "CHECK IF SD CARD NEEDS EXPANSION" >> ${logFile}
source ${infoFile}

minimumSizeByte=8192000000
rootPartition=$(sudo mount | grep " / " | cut -d " " -f 1 | cut -d "/" -f 3)
rootPartitionBytes=$(lsblk -b -o NAME,SIZE | grep "${rootPartition}" | tr -s ' ' | cut -d " " -f 2)

echo "rootPartition(${rootPartition})" >> ${logFile}
echo "rootPartitionBytes(${rootPartitionBytes})" >> ${logFile}

if [ ${#rootPartition} -gt 0 ]; then
   echo "### CHECKING ROOT PARTITION SIZE ###" >> ${logFile}
   sudo sed -i "s/^message=.*/message='Checking Disk size'/g" ${infoFile}
   echo "Size in Bytes is: ${rootPartitionBytes} bytes on ($rootPartition)" >> ${logFile}
   if [ $rootPartitionBytes -lt $minimumSizeByte ]; then
      echo "Disk filesystem is smaller than ${minimumSizeByte} byte." >> ${logFile}
      if [ ${fsexpanded} -eq 1 ]; then
        echo "There was already an attempt to expand the fs, but still not bigger than 8GB." >> ${logFile}
        echo "SD card seems to small - at least a 16GB disk is needed. Display on LCD to user." >> ${logFile}
        sudo sed -i "s/^state=.*/state=sdtoosmall/g" ${infoFile}
        sudo sed -i "s/^message=.*/message='Min 16GB SD card needed'/g" ${infoFile}
        exit 1
      else
        echo "Try to expand SD card FS, display info and reboot." >> ${logFile}
        sudo sed -i "s/^state=.*/state=reboot/g" ${infoFile}
        sudo sed -i "s/^message=.*/message='Expanding SD Card'/g" ${infoFile}
        sudo sed -i "s/^fsexpanded=.*/fsexpanded=1/g" ${infoFile}
        sleep 4
        if [ "${cpu}" == "x86_64"  ]; then
            echo "Please expand disk size." >> ${logFile}
	          # TODO: Expand disk size on x86_64
        elif [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "raspios_arm64" ]; then
            resizeRaspbian="/usr/bin/raspi-config"
            if [ -x ${resizeRaspbian} ]; then
              echo "RUNNING EXPAND RASPBERRYPI: ${resizeRaspbian}" >> ${logFile}
		          sudo $resizeRaspbian --expand-rootfs
              sudo shutdown -r now
	            exit 0
	          else
              echo "FAIL to execute: ${resizeRaspbian}" >> ${logFile}
            fi
        elif [ "${baseImage}" = "armbian" ]; then
            resizeArmbian="/usr/lib/armbian/armbian-resize-filesystem"
            if [ -x ${resizeArmbian} ]; then
              echo "RUNNING EXPAND ARMBIAN: ${resizeArmbian}" >> ${logFile}
              sudo $resizeArmbian start
              sudo shutdown -r now
	            exit 0
	          else
              echo "FAIL to execute: ${resizeArmbian}" >> ${logFile}
            fi
        else
          echo "WARN on provision - Not known system expand-rootfs OS" >> ${logFile}
        fi
      fi
   else
      echo "Size looks good. Bigger than ${minimumSizeByte} byte disk is used." >> ${logFile}
   fi
else
   echo "Disk of root partition ('$rootPartition') not detected, skipping the size check." >> ${logFile}
fi

# import config values
sudo chmod 777 ${configFile}
source ${configFile}

# check if the system was configured for HDMI and needs switch
# keep as one of the first so that user can see video output
if [ "${lcd2hdmi}" == "on" ]; then
  echo "RaspiBlitz has config to run with HDMI video outout." >> ${logFile}
  # check that raspiblitz.info shows that confing script was not run yet
  switchScriptNotRunYet=$(sudo cat /home/admin/raspiblitz.info | grep -c "lcd2hdmi=off")
  if [ ${switchScriptNotRunYet} -eq 1 ]; then
    echo "--> Switching to HDMI video output & rebooting" >> ${logFile}
    sudo /home/admin/config.scripts/blitz.lcd.sh hdmi on
  else
    echo "OK RaspiBlitz was already switched to HDMI output." >> ${logFile}
  fi
fi

##########################
# BASIC SYSTEM SETTINGS
##########################

echo "### BASIC SYSTEM SETTINGS ###" >> ${logFile}
sudo sed -i "s/^message=.*/message='Setup System .'/g" ${infoFile}

# install litecoin (just if needed)
if [ "${network}" = "litecoin" ]; then
  echo "Installing Litecoin ..." >> ${logFile}
  /home/admin/config.scripts/blitz.litecoin.sh on >> ${logFile}
fi

# set hostname data
echo "Setting lightning alias: ${hostname}" >> ${logFile}
sudo sed -i "s/^alias=.*/alias=${hostname}/g" /home/admin/assets/lnd.${network}.conf >> ${logFile} 2>&1

# link old SSH PubKeys
# so that client ssh_known_hosts is not complaining after update
if [ -d "/mnt/hdd/ssh" ]; then
  echo "Old SSH PubKey exists on HDD > copy them HDD to SD card for next start" >> ${logFile}
  sudo cp -r /mnt/hdd/ssh/* /etc/ssh/ >> ${logFile} 2>&1
else
  echo "No SSH PubKey exists on HDD > copy from SD card to HDD as backup" >> ${logFile}
  sudo cp -r /etc/ssh /mnt/hdd/ssh >> ${logFile} 2>&1
fi
# just copy - dont link anymore so that sshd will also start without HDD connected
# see: https://github.com/rootzoll/raspiblitz/issues/1798
#sudo rm -rf /etc/ssh >> ${logFile} 2>&1
#sudo ln -s /mnt/hdd/ssh /etc/ssh >> ${logFile} 2>&1
#sudo /home/admin/config.scripts/blitz.systemd.sh update-sshd >> ${logFile} 2>&1

# optimze if RAM >1GB
kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
if [ ${kbSizeRAM} -gt 1500000 ]; then
  echo "Detected RAM >1GB --> optimizing ${network}.conf"
  sudo sed -i "s/^dbcache=.*/dbcache=1024/g" /mnt/hdd/${network}/${network}.conf
  sudo sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/${network}/${network}.conf
fi
if [ ${kbSizeRAM} -gt 3500000 ]; then
  echo "Detected RAM >3GB --> optimizing ${network}.conf"
  sudo sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/${network}/${network}.conf
fi

# link and copy HDD content into new OS on sd card
echo "Copy HDD content for user admin" >> ${logFile}
sudo mkdir /home/admin/.${network} >> ${logFile} 2>&1
sudo cp /mnt/hdd/${network}/${network}.conf /home/admin/.${network}/${network}.conf >> ${logFile} 2>&1
sudo mkdir /home/admin/.lnd >> ${logFile} 2>&1
sudo cp /mnt/hdd/lnd/lnd.conf /home/admin/.lnd/lnd.conf >> ${logFile} 2>&1
sudo cp /mnt/hdd/lnd/tls.cert /home/admin/.lnd/tls.cert >> ${logFile} 2>&1
sudo mkdir /home/admin/.lnd/data >> ${logFile} 2>&1
sudo cp -r /mnt/hdd/lnd/data/chain /home/admin/.lnd/data/chain >> ${logFile} 2>&1
sudo chown -R admin:admin /home/admin/.${network} >> ${logFile} 2>&1
sudo chown -R admin:admin /home/admin/.lnd >> ${logFile} 2>&1
sudo cp /home/admin/assets/${network}d.service /etc/systemd/system/${network}d.service >> ${logFile} 2>&1
sed -i "5s/.*/Wants=${network}d.service/" /home/admin/assets/lnd.service >> ${logFile} 2>&1
sed -i "6s/.*/After=${network}d.service/" /home/admin/assets/lnd.service >> ${logFile} 2>&1
sudo cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service >> ${logFile} 2>&1

sudo cp /home/admin/assets/tmux.conf.local /mnt/hdd/.tmux.conf.local >> ${logFile} 2>&1
sudo chown admin:admin /mnt/hdd/.tmux.conf.local >> ${logFile} 2>&1
sudo ln -s -f /mnt/hdd/.tmux.conf.local /home/admin/.tmux.conf.local >> ${logFile} 2>&1

# backup LND dir (especially for macaroons and tlscerts)
# https://github.com/rootzoll/raspiblitz/issues/324
echo "*** Make backup of LND directory" >> ${logFile}
sudo rm -r  /mnt/hdd/backup_lnd
sudo cp -r /mnt/hdd/lnd /mnt/hdd/backup_lnd >> ${logFile} 2>&1
numOfDiffers=$(sudo diff -arq /mnt/hdd/lnd /mnt/hdd/backup_lnd | grep -c "differ")
if [ ${numOfDiffers} -gt 0 ]; then
  echo "FAIL: Backup was not successfull" >> ${logFile}
  sudo diff -arq /mnt/hdd/lnd /mnt/hdd/backup_lnd >> ${logFile} 2>&1
  echo "removing backup dir to prevent false override" >> ${logFile}
else
  echo "OK Backup is valid." >> ${logFile}
fi
echo "" >> ${logFile}

# finish setup (SWAP, Benus, Firewall, Update, ..)
sudo sed -i "s/^message=.*/message='Setup System ..'/g" ${infoFile}
/home/admin/90finishSetup.sh >> ${logFile} 2>&1

##########################
# PROVISIONING SERVICES
##########################
sudo sed -i "s/^message=.*/message='Installing Services'/g" ${infoFile}

echo "### RUNNING PROVISIONING SERVICES ###" >> ${logFile}

# BLITZ WEB SERVICE
echo "Provisioning BLITZ WEB SERVICE - run config script" >> ${logFile}
/home/admin/config.scripts/blitz.web.sh on >> ${logFile} 2>&1

# LND INTERIMS UPDATE
if [ ${#lndInterimsUpdate} -gt 0 ]; then
  sudo sed -i "s/^message=.*/message='Provisioning LND update'/g" ${infoFile}
  if [ "${lndInterimsUpdate}" == "reckless" ]; then
    # recklessly update LND to latest release on GitHub (just for test & dev nodes)
    echo "Provisioning LND reckless interims update" >> ${logFile}
    sudo /home/admin/config.scripts/lnd.update.sh reckless >> ${logFile}
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this a update with a newer RaspiBlitz version .. interims update will be ignored
    # because standard LND version is most more up to date
    echo "Provisioning LND verified interims update" >> ${logFile}
    sudo /home/admin/config.scripts/lnd.update.sh verified ${lndInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning LND interims update - keep default" >> ${logFile}
fi

# TESTNET
if [ "${chain}" = "test" ]; then
    echo "Provisioning TESTNET - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Provisioning Testnet'/g" ${infoFile}
    sudo /home/admin/config.scripts/network.chain.sh testnet >> ${logFile} 2>&1
else
    echo "Provisioning TESTNET - keep default" >> ${logFile}
fi

# TOR
if [ "${runBehindTor}" = "on" ]; then
    echo "Provisioning TOR - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup Tor (takes time)'/g" ${infoFile}
    sudo /home/admin/config.scripts/internet.tor.sh on >> ${logFile} 2>&1
else
    echo "Provisioning TOR - keep default" >> ${logFile}
fi

# AUTO PILOT
if [ "${autoPilot}" = "on" ]; then
    echo "Provisioning AUTO PILOT - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup AutoPilot'/g" ${infoFile}
    sudo /home/admin/config.scripts/lnd.autopilot.sh on >> ${logFile} 2>&1
else
    echo "Provisioning AUTO PILOT - keep default" >> ${logFile}
fi

# NETWORK UPNP
if [ "${networkUPnP}" = "on" ]; then
    echo "Provisioning NETWORK UPnP - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup UPnP'/g" ${infoFile}
    sudo /home/admin/config.scripts/network.upnp.sh on >> ${logFile} 2>&1
else
    echo "Provisioning NETWORK UPnP  - keep default" >> ${logFile}
fi

# LND AUTO NAT DISCOVERY
if [ "${autoNatDiscovery}" = "on" ]; then
    echo "Provisioning LND AUTO NAT DISCOVERY - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup AutoNAT'/g" ${infoFile}
    sudo /home/admin/config.scripts/lnd.autonat.sh on >> ${logFile} 2>&1
else
    echo "Provisioning AUTO NAT DISCOVERY - keep default" >> ${logFile}
fi

# DYNAMIC DOMAIN
if [ "${#dynDomain}" -gt 0 ]; then
    echo "Provisioning DYNAMIC DOMAIN - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup DynamicDomain'/g" ${infoFile}
    sudo /home/admin/config.scripts/internet.dyndomain.sh on ${dynDomain} ${dynUpdateUrl} >> ${logFile} 2>&1
else
    echo "Provisioning DYNAMIC DOMAIN - keep default" >> ${logFile}
fi

# RTL
if [ "${rtlWebinterface}" = "on" ]; then
    echo "Provisioning RTL - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup RTL (takes time)'/g" ${infoFile}
    sudo -u admin /home/admin/config.scripts/bonus.rtl.sh on >> ${logFile} 2>&1
    sudo systemctl disable RTL # will get enabled after recover dialog
else
    echo "Provisioning RTL - keep default" >> ${logFile}
fi

#LOOP
if [ "${loop}" = "on" ]; then
  echo "Provisioning Lightning Loop - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Lightning Loop'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.loop.sh on >> ${logFile} 2>&1
  sudo systemctl disable loopd # will get enabled after recover dialog
else
  echo "Provisioning Lightning Loop - keep default" >> ${logFile}
fi

#BTC RPC EXPLORER
if [ "${BTCRPCexplorer}" = "on" ]; then
  echo "Provisioning BTCRPCexplorer - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup BTCRPCexplorer (takes time)'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.btc-rpc-explorer.sh on >> ${logFile} 2>&1
  sudo systemctl disable btc-rpc-explorer # will get enabled after recover dialog
else
  echo "Provisioning BTCRPCexplorer - keep default" >> ${logFile}
fi

#ELECTRS
if [ "${ElectRS}" = "on" ]; then
  echo "Provisioning ElectRS - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup ElectRS (takes time)'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.electrs.sh on >> ${logFile} 2>&1
  sudo systemctl disable electrs # will get enabled after recover dialog
else
  echo "Provisioning ElectRS - keep default" >> ${logFile}
fi

# BTCPAYSERVER 
if [ "${BTCPayServer}" = "on" ]; then

  echo "Provisioning BTCPAYSERVER on TOR - running setup" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup BTCPay (takes time)'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.btcpayserver.sh on >> ${logFile} 2>&1

  #echo "Provisioning BTCPAYSERVER on TOR - run on after bootup script" >> ${logFile}
  # because BTCPAY server freezes during recovery .. it will get installed after reboot
  #echo "sudo -u admin /home/admin/config.scripts/bonus.btcpayserver.sh on" >> /home/admin/setup.sh
  #sudo chmod +x /home/admin/setup.sh >> ${logFile}
  #sudo ls -la /home/admin/setup.sh >> ${logFile}

else
  echo "Provisioning BTCPayServer - keep default" >> ${logFile}
fi

# deprecated - see: #2031
# LNDMANAGE
#if [ "${lndmanage}" = "on" ]; then
#  echo "Provisioning lndmanage - run config script" >> ${logFile}
#  sudo sed -i "s/^message=.*/message='Setup lndmanage '/g" ${infoFile}
#  sudo -u admin /home/admin/config.scripts/bonus.lndmanage.sh on >> ${logFile} 2>&1
#else
#  echo "Provisioning lndmanage - not active" >> ${logFile}
#fi

# CUSTOM PORT
echo "Provisioning LND Port" >> ${logFile}
if [ ${#lndPort} -eq 0 ]; then
  lndPort=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep "^listen=*" | cut -f2 -d':')
fi
if [ ${#lndPort} -gt 0 ]; then
  if [ "${lndPort}" != "9735" ]; then
    echo "User is running custom LND port: ${lndPort}" >> ${logFile}
    sudo /home/admin/config.scripts/lnd.setport.sh ${lndPort} >> ${logFile} 2>&1
  else
    echo "User is running standard LND port: ${lndPort}" >> ${logFile}
  fi
else
  echo "Was not able to get LND port from config." >> ${logFile}
fi

# DNS Server
if [ ${#dnsServer} -gt 0 ]; then
    echo "Provisioning DNS Server - Setting DNS Server" >> ${logFile}
    sudo /home/admin/config.scripts/internet.dns.sh ${dnsServer} >> ${logFile} 2>&1
else
    echo "Provisioning DNS Server - keep default" >> ${logFile}
fi

# CHANTOOLS
if [ "${chantools}" == "on" ]; then
    echo "Provisioning chantools - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/bonus.chantools.sh on >> ${logFile} 2>&1
else
    echo "Provisioning chantools - keep default" >> ${logFile}
fi

# ROOT SSH KEYS
# check if a backup on HDD exists – if so, restore it
backupRootSSH=$(sudo ls /mnt/hdd/ssh/root_backup 2>/dev/null | grep -c "id_rsa")
if [ ${backupRootSSH} -gt 0 ]; then
    echo "Provisioning Root SSH Keys - RESTORING from HDD" >> ${logFile}
    sudo cp -r /mnt/hdd/ssh/root_backup /root/.ssh
    sudo chown -R root:root /root/.ssh
else
    echo "Provisioning Root SSH Keys - keep default" >> ${logFile}
fi

# SSH TUNNEL
if [ "${#sshtunnel}" -gt 0 ]; then
    echo "Provisioning SSH Tunnel - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup SSH Tunnel'/g" ${infoFile}
    sudo /home/admin/config.scripts/internet.sshtunnel.py restore ${sshtunnel} >> ${logFile} 2>&1
else
    echo "Provisioning SSH Tunnel - not active" >> ${logFile}
fi

# ZEROTIER
if [ "${#zerotier}" -gt 0 ] && [ "${zerotier}" != "off" ]; then
    echo "Provisioning ZeroTier - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup ZeroTier'/g" ${infoFile}
    sudo /home/admin/config.scripts/bonus.zerotier.sh on ${zerotier} >> ${logFile} 2>&1
else
    echo "Provisioning ZeroTier - not active" >> ${logFile}
fi

# LCD ROTATE
if [ "${#lcdrotate}" -eq 0 ]; then
  # when upgrading from an old raspiblitz - enforce lcdrotate = 0
  lcdrotate=0
fi
echo "Provisioning LCD rotate - run config script" >> ${logFile}
sudo sed -i "s/^message=.*/message='LCD Rotate'/g" ${infoFile}
sudo /home/admin/config.scripts/blitz.lcd.sh rotate ${lcdrotate} >> ${logFile} 2>&1

# TOUCHSCREEN
if [ "${#touchscreen}" -gt 0 ]; then
    echo "Provisioning Touchscreen - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup Touchscreen'/g" ${infoFile}
    sudo /home/admin/config.scripts/blitz.touchscreen.sh ${touchscreen} >> ${logFile} 2>&1
else
    echo "Provisioning Touchscreen - not active" >> ${logFile}
fi

# UPS
if [ "${#ups}" -gt 0 ]; then
    echo "Provisioning UPS - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup UPS'/g" ${infoFile}
    sudo /home/admin/config.scripts/blitz.ups.sh on ${ups} >> ${logFile} 2>&1
else
    echo "Provisioning UPS - not active" >> ${logFile}
fi

# LNbits
if [ "${LNBits}" = "on" ]; then
  echo "Provisioning LNbits - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup LNbits '/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LNbits - keep default" >> ${logFile}
fi

# JoinMarket
if [ "${joinmarket}" = "on" ]; then
  echo "Provisioning JoinMarket - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup JoinMarket'/g" ${infoFile}
  sudo /home/admin/config.scripts/bonus.joinmarket.sh on >> ${logFile} 2>&1
else
  echo "Provisioning JoinMarket - keep default" >> ${logFile}
fi

# Specter
if [ "${specter}" = "on" ]; then
  echo "Provisioning Specter - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Specter'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.cryptoadvance-specter.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Specter - keep default" >> ${logFile}
fi

# Faraday
if [ "${faraday}" = "on" ]; then
  echo "Provisioning Faraday - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Faraday'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.faraday.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Faraday - keep default" >> ${logFile}
fi

# BOS
if [ "${bos}" = "on" ]; then
  echo "Provisioning Balance of Satoshis - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Balance of Satoshis'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.bos.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Balance of Satoshis - keep default" >> ${logFile}
fi

# thunderhub
if [ "${thunderhub}" = "on" ]; then
  echo "Provisioning ThunderHub - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup ThunderHub'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.thunderhub.sh on >> ${logFile} 2>&1
else
  echo "Provisioning ThunderHub - keep default" >> ${logFile}
fi

# mempool space
if [ "${mempoolExplorer}" = "on" ]; then
  echo "Provisioning MempoolSpace - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Mempool Space'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.mempool.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Mempool Explorer - keep default" >> ${logFile}
fi

# letsencrypt
if [ "${letsencrypt}" = "on" ]; then
  echo "Provisioning letsencrypt - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup letsencrypt'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.letsencrypt.sh on >> ${logFile} 2>&1
else
  echo "Provisioning letsencrypt - keep default" >> ${logFile}
fi

# kindle-display
if [ "${kindleDisplay}" = "on" ]; then
  echo "Provisioning kindle-display - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup kindle-display'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.kindle-display.sh on >> ${logFile} 2>&1
else
  echo "Provisioning kindle-display - keep default" >> ${logFile}
fi

# pyblock
if [ "${pyblock}" = "on" ]; then
  echo "Provisioning pyblock - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup pyblock'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.pyblock.sh on >> ${logFile} 2>&1
else
  echo "Provisioning pyblock - keep default" >> ${logFile}
fi

# stacking-sats-kraken
if [ "${stackingSatsKraken}" = "on" ]; then
  echo "Provisioning Stacking Sats Kraken - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Stacking Sats Kraken'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.stacking-sats-kraken.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Stacking Sats Kraken - keep default" >> ${logFile}
fi

# pool
if [ "${pool}" = "on" ]; then
  echo "Provisioning Pool - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Pool'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.pool.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Pool - keep default" >> ${logFile}
fi

# sphinxrelay
if [ "${sphinxrelay}" = "on" ]; then
  echo "Sphinx-Relay - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Sphinx-Relay'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.sphinxrelay.sh on >> ${logFile} 2>&1
else
  echo "Sphinx-Relay - keep default" >> ${logFile}
fi

# circuitbreaker
if [ "${circuitbreaker}" = "on" ]; then
  echo "Provisioning CircuitBreaker - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup CircuitBreaker'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.circuitbreaker.sh on >> ${logFile} 2>&1
else
  echo "Provisioning CircuitBreaker - keep default" >> ${logFile}
fi

# custom install script from user
customInstallAvailable=$(sudo ls /mnt/hdd/app-data/custom-installs.sh 2>/dev/null | grep -c "custom-installs.sh")
if [ ${customInstallAvailable} -gt 0 ]; then
  echo "Running the custom install script .." >> ${logFile}
  # copy script over to admin (in case HDD is not allowing exec)
  sudo cp -av /mnt/hdd/app-data/custom-installs.sh /home/admin/custom-installs.sh >> ${logFile}
  # make sure script is executable
  sudo chmod +x /home/admin/custom-installs.sh >> ${logFile}
  # run it & delete it again
  sudo /home/admin/custom-installs.sh >> ${logFile}
  sudo rm /home/admin/custom-installs.sh >> ${logFile}
  echo "Done" >> ${logFile}
else
  echo "No custom install script ... adding the placeholder." >> ${logFile}
  sudo cp /home/admin/assets/custom-installs.sh /mnt/hdd/app-data/custom-installs.sh
fi

# replay backup LND conf & tlscerts
# https://github.com/rootzoll/raspiblitz/issues/324
echo "" >> ${logFile}
echo "*** Replay backup of LND conf/tls" >> ${logFile}
if [ -d "/mnt/hdd/backup_lnd" ]; then

  echo "Copying TLS ..." >> ${logFile}
  sudo cp /mnt/hdd/backup_lnd/tls.cert /mnt/hdd/lnd/tls.cert >> ${logFile} 2>&1
  sudo cp /mnt/hdd/backup_lnd/tls.key /mnt/hdd/lnd/tls.key >> ${logFile} 2>&1
  sudo chown -R bitcoin:bitcoin /mnt/hdd/lnd >> ${logFile} 2>&1
  echo "On next final restart admin creds will be updated by _boostrap.sh" >> ${logFile}

  echo "DONE" >> ${logFile}
else
  echo "No BackupDir so skipping that step." >> ${logFile}
fi
echo "" >> ${logFile}

# repair Bitcoin conf if needed
echo "*** Repair Bitcioin Conf (if needed)" >> ${logFile}
confExists="$(sudo ls /mnt/hdd/${network} | grep -c "${network}.conf")"
if [ ${confExists} -eq 0 ]; then
  echo "Doing init of ${network}.conf" >> ${logFile}
  sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
  sudo chown bitcoin:bitcoin /mnt/hdd/bitcoin/bitcoin.conf
fi
echo "Aligning lnd.conf & ${network}.conf" >> ${logFile}
rpcpass=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep "${network}d.rpcpass" | cut -d "=" -f2)
sudo sed -i "s/^rpcpassword=.*/rpcpassword=${rpcpass}/g" /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null

# singal setup done
sudo sed -i "s/^message=.*/message='Setup Done'/g" ${infoFile}

# set the local network hostname (just if set in config - will not be set anymore by default in newer version)
# have at the end - see https://github.com/rootzoll/raspiblitz/issues/462
# see also https://github.com/rootzoll/raspiblitz/issues/819
if [ ${#hostname} -gt 0 ]; then
  hostnameSanatized=$(echo "${hostname}"| tr -dc '[:alnum:]\n\r')
  if [ ${#hostnameSanatized} -gt 0 ]; then
    # by default set hostname for older versions on update
    if [ ${#setnetworkname} -eq 0 ]; then
      setnetworkname=1
    fi
    if [ "${setnetworkname}" = "1" ]; then
      echo "Setting new network hostname '$hostnameSanatized'" >> ${logFile}
      sudo raspi-config nonint do_hostname ${hostnameSanatized} >> ${logFile} 2>&1
    else
      echo "Not setting local network hostname" >> ${logFile}
    fi
  else
    echo "WARNING: hostname in raspiblitz.conf contains just special chars" >> ${logFile}
  fi
else
  echo "No hostname set." >> ${logFile}
fi

# PERMANENT MOUNT OF HDD/SSD
# always at the end, because data drives will be just available again after a reboot
echo "Prepare fstab for permanent data drive mounting .." >> ${logFile}
# get info on data drive
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
# update /etc/fstab
echo "datadisk --> ${datadisk}" >> ${logFile}
echo "datapartition --> ${datapartition}" >> ${logFile}
if [ ${isBTRFS} -eq 0 ]; then
  sudo /home/admin/config.scripts/blitz.datadrive.sh fstab ${datapartition} >> ${logFile}
else
  sudo /home/admin/config.scripts/blitz.datadrive.sh fstab ${datadisk} >> ${logFile}
fi

echo "DONE - Give raspi some cool off time after hard building .... 5 secs sleep" >> ${logFile}
sleep 5

echo "END Provisioning" >> ${logFile}
