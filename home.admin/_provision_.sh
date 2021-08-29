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

# log header
echo "" >> ${logFile}
echo "###################################" >> ${logFile}
echo "# _provision_.sh" >> ${logFile}
echo "###################################" >> ${logFile}
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

# import config values
source ${configFile}

##########################
# DISPLAY SETTINGS
##########################

# check if the raspiblitz config has a different display mode than the build image
echo "### DISPLAY SETTINGS ###" >> ${logFile}

# OLD: when nothing is set in raspiblitz.conf (<1.7)
existsDisplayClass=$(sudo cat ${configFile} | grep -c "displayClass=")
if [ "${existsDisplayClass}" == "0" ]; then
  displayClass="lcd"
fi

# OLD: lcd2hdmi (deprecated)
if [ "${lcd2hdmi}" == "on" ]; then
  echo "Convert lcd2hdmi=on to displayClass='hdmi'" >> ${logFile}
  sudo sed -i "s/^lcd2hdmi=.*//g" ${configFile}
  echo "displayClass=hdmi" >> ${configFile}
  displayClass="hdmi"
elif [ "${lcd2hdmi}" != "" ]; then
  echo "Remove old lcd2hdmi pramater from config" >> ${logFile}
  sudo sed -i "s/^lcd2hdmi=.*//g" ${configFile}
  displayClass="lcd"
fi

# OLD: headless (deprecated)
if [ "${headless}" == "on" ]; then
  echo "Convert headless=on to displayClass='headless'" >> ${logFile}
  sudo sed -i "s/^headless=.*//g" ${configFile}
  echo "displayClass=headless" >> ${configFile}
  displayClass="headless"
elif [ "${headless}" != "" ]; then
  echo "Remove old headless parameter from config" >> ${logFile}
  sudo sed -i "s/^headless=.*//g" ${configFile}
  displayClass="lcd"
fi

# NEW: decide by displayClass 
echo "raspiblitz.info(${infoFileDisplayClass}) raspiblitz.conf(${displayClass})" >> ${logFile}
if [ "${infoFileDisplayClass}" != "" ] && [ "${displayClass}" != "" ]; then
  if [ "${infoFileDisplayClass}" != "${displayClass}" ]; then
    echo "Need to update displayClass from (${infoFileDisplayClass}) to (${displayClass})'" >> ${logFile}
    sudo /home/admin/config.scripts/blitz.display.sh set-display ${displayClass} >> ${logFile}
    echo "going into reboot" >> ${logFile}
    sudo cp ${logFile} ${logFile}.display.recover
    sudo shutdown -r now
	  exit 0
  else
    echo "Display Setting is correct ... no need for change" >> ${logFile}
  fi
else
  echo "WARN values in raspiblitz info and/or conf file seem broken" >> ${logFile}
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

echo "# Make sure the user bitcoin is in the debian-tor group"
sudo usermod -a -G debian-tor bitcoin

# set hostname data
echo "Setting lightning alias: ${hostname}" >> ${logFile}
sudo sed -i "s/^alias=.*/alias=${hostname}/g" /home/admin/assets/lnd.${network}.conf >> ${logFile} 2>&1

# backup SSH PubKeys
sudo /home/admin/config.scripts/blitz.ssh.sh backup

# optimze mempool if RAM >1GB
kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
if [ ${kbSizeRAM} -gt 1500000 ]; then
  echo "Detected RAM >1GB --> optimizing ${network}.conf"
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
sudo cp /home/admin/assets/tmux.conf.local /mnt/hdd/.tmux.conf.local >> ${logFile} 2>&1
sudo chown admin:admin /mnt/hdd/.tmux.conf.local >> ${logFile} 2>&1
sudo ln -s -f /mnt/hdd/.tmux.conf.local /home/admin/.tmux.conf.local >> ${logFile} 2>&1


# PREPARE LND (if activated)
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then

  echo "### PREPARE LND" >> ${logFile}
  
  # backup LND dir (especially for macaroons and tlscerts)
  # https://github.com/rootzoll/raspiblitz/issues/324
  echo "*** Make backup of LND directory" >> ${logFile}
  sudo rm -r  /mnt/hdd/backup_lnd 2>/dev/null
  sudo cp -r /mnt/hdd/lnd /mnt/hdd/backup_lnd >> ${logFile} 2>&1
  numOfDiffers=$(sudo diff -arq /mnt/hdd/lnd /mnt/hdd/backup_lnd | grep -c "differ")
  if [ ${numOfDiffers} -gt 0 ]; then
    echo "FAIL: Backup was not successful" >> ${logFile}
    sudo diff -arq /mnt/hdd/lnd /mnt/hdd/backup_lnd >> ${logFile} 2>&1
    echo "removing backup dir to prevent false override" >> ${logFile}
  else
    echo "OK Backup is valid." >> ${logFile}
  fi

fi
echo "" >> ${logFile}

##########################
# FINISH SETUP
##########################

# finish setup (SWAP, Benus, Firewall, Update, ..)
sudo sed -i "s/^message=.*/message='Setup System ..'/g" ${infoFile}

# add bonus scripts (auto install deactivated to reduce third party repos)
mkdir /home/admin/tmpScriptDL
cd /home/admin/tmpScriptDL
echo "installing bash completion for bitcoin-cli and lncli"
wget https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/bitcoin-cli.bash-completion
wget https://raw.githubusercontent.com/lightningnetwork/lnd/master/contrib/lncli.bash-completion
sudo cp *.bash-completion /etc/bash_completion.d/
echo "OK - bash completion available after next login"
echo "type \"bitcoin-cli getblockch\", press [Tab] → bitcoin-cli getblockchaininfo"
rm -r /home/admin/tmpScriptDL
cd

###### SWAP File
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
if [ ${isSwapExternal} -eq 0 ]; then
  echo "No external SWAP found - creating ... "
  sudo /home/admin/config.scripts/blitz.datadrive.sh swap on
else
  echo "SWAP already OK"
fi

####### FIREWALL - just install (not configure)
echo ""
echo "*** Setting and Activating Firewall ***"
echo "deny incoming connection on other ports"
sudo ufw default deny incoming
echo "allow outgoing connections"
sudo ufw default allow outgoing
echo "allow: ssh"
sudo ufw allow ssh
echo "allow: bitcoin testnet"
sudo ufw allow 18333 comment 'bitcoin testnet'
echo "allow: bitcoin mainnet"
sudo ufw allow 8333 comment 'bitcoin mainnet'
echo "allow: litecoin mainnet"
sudo ufw allow 9333 comment 'litecoin mainnet'
echo 'allow: lightning testnet'
sudo ufw allow 19735 comment 'lightning testnet'
echo "allow: lightning mainnet"
sudo ufw allow 9735 comment 'lightning mainnet'
echo "allow: lightning gRPC"
sudo ufw allow 10009 comment 'lightning gRPC'
echo "allow: lightning REST API"
sudo ufw allow 8080 comment 'lightning REST API'
echo "allow: transmission"
sudo ufw allow 49200:49250/tcp comment 'rtorrent'
echo "allow: public web HTTP"
sudo ufw allow from any to any port 80 comment 'allow public web HTTP'
echo "allow: local web admin HTTPS"
sudo ufw allow from 10.0.0.0/8 to any port 443 comment 'allow local LAN HTTPS'
sudo ufw allow from 172.16.0.0/12 to any port 443 comment 'allow local LAN HTTPS'
sudo ufw allow from 192.168.0.0/16 to any port 443 comment 'allow local LAN HTTPS'
echo "open firewall for auto nat discover (see issue #129)"
sudo ufw allow proto udp from 10.0.0.0/8 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
sudo ufw allow proto udp from 172.16.0.0/12 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
sudo ufw allow proto udp from 192.168.0.0/16 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
echo "enable lazy firewall"
sudo ufw --force enable
echo ""

# update system
echo ""
echo "*** Update System ***"
sudo apt-mark hold raspberrypi-bootloader
sudo apt-get update -y
echo "OK - System is now up to date"

# mark setup is done
sudo sed -i "s/^setupStep=.*/setupStep=100/g" /home/admin/raspiblitz.info

##########################
# PROVISIONING SERVICES
##########################
sudo sed -i "s/^message=.*/message='Installing Services'/g" ${infoFile}

echo "### RUNNING PROVISIONING SERVICES ###" >> ${logFile}

# BLITZ WEB SERVICE
echo "Provisioning BLITZ WEB SERVICE - run config script" >> ${logFile}
/home/admin/config.scripts/blitz.web.sh on >> ${logFile} 2>&1

# BITCOIN INTERIMS UPDATE
if [ ${#bitcoinInterimsUpdate} -gt 0 ]; then
  sudo sed -i "s/^message=.*/message='Provisioning Bitcoin Core update'/g" ${infoFile}
  if [ "${bitcoinInterimsUpdate}" == "reckless" ]; then
    # recklessly update Bitcoin Core to latest release on GitHub
    echo "Provisioning Bitcoin Core reckless interims update" >> ${logFile}
    sudo /home/admin/config.scripts/bitcoin.update.sh reckless >> ${logFile}
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this a update with a newer RaspiBlitz version .. interims update will be ignored
    # because standard Bitcoin Core version is most more up to date
    echo "Provisioning BItcoin Core tested interims update" >> ${logFile}
    sudo /home/admin/config.scripts/bitcoin.update.sh tested ${bitcoinInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning Bitcoin Core interims update - keep default" >> ${logFile}
fi

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

# Bitcoin Testnet
if [ "${testnet}" == "on" ]; then
    echo "Provisioning ${network} Testnet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/bitcoin.chains.sh on testnet >> ${logFile} 2>&1
    sudo systemctl start tbitcoind >> ${logFile} 2>&1
else
    echo "Provisioning ${network} Testnet - not activ" >> ${logFile}
fi

# Bitcoin Signet
if [ "${signet}" == "on" ]; then
    echo "Provisioning ${network} Signet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/bitcoin.chains.sh on signet >> ${logFile} 2>&1
    sudo systemctl start sbitcoind >> ${logFile} 2>&1
else
    echo "Provisioning ${network} Signet - not activ" >> ${logFile}
fi

# LND Mainnet (when not main instance)
if [ "${lnd}" == "on" ] && [ "${lightning}" != "lnd" ]; then
    echo "Provisioning LND Mainnet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/lnd.chain.sh on mainnet >> ${logFile} 2>&1
else
    echo "Provisioning LND Mainnet - not activ as secondary option" >> ${logFile}
fi

# LND Testnet
if [ "${tlnd}" == "on" ]; then
    echo "Provisioning LND Testnet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/lnd.chain.sh on testnet >> ${logFile} 2>&1
    sudo systemctl start tlnd >> ${logFile} 2>&1
else
    echo "Provisioning LND Testnet - not activ" >> ${logFile}
fi

# LND Signet
if [ "${slnd}" == "on" ]; then
    echo "Provisioning LND Signet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/lnd.chain.sh on signet >> ${logFile} 2>&1
    sudo systemctl start slnd >> ${logFile} 2>&1
else
    echo "Provisioning LND Signet - not activ" >> ${logFile}
fi

# CLN Mainnet (when not main instance)
if [ "${cln}" == "on" ] && [ "${lightning}" != "cln" ]; then
    echo "Provisioning CLN Mainnet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/cln.install.sh on mainnet >> ${logFile} 2>&1
else
    echo "Provisioning CLN Mainnet - not activ as secondary option" >> ${logFile}
fi

# CLN Testnet
if [ "${tcln}" == "on" ]; then
    echo "Provisioning CLN Testnet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/cln.install.sh on testnet >> ${logFile} 2>&1
else
    echo "Provisioning CLN Testnet - not activ" >> ${logFile}
fi

# CLN Signet
if [ "${scln}" == "on" ]; then
    echo "Provisioning CLN Signet - run config script" >> ${logFile}
    sudo /home/admin/config.scripts/cln.install.sh on signet >> ${logFile} 2>&1
else
    echo "Provisioning CLN Signet - not activ" >> ${logFile}
fi

# TOR
if [ "${runBehindTor}" == "on" ]; then
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

# RTL (LND)
if [ "${rtlWebinterface}" = "on" ]; then
    echo "Provisioning RTL LND - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup RTL (takes time)'/g" ${infoFile}
    sudo -u admin /home/admin/config.scripts/bonus.rtl.sh on lnd mainnet >> ${logFile} 2>&1
    sudo systemctl disable RTL # will get enabled after recover dialog
else
    echo "Provisioning RTL LND - keep default" >> ${logFile}
fi

# RTL (CLN)
if [ "${crtlWebinterface}" = "on" ]; then
    echo "Provisioning RTL CLN - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup RTL (takes time)'/g" ${infoFile}
    sudo -u admin /home/admin/config.scripts/bonus.rtl.sh on cln mainnet >> ${logFile} 2>&1
    sudo systemctl disable cRTL # will get enabled after recover dialog
else
    echo "Provisioning RTL CLN - keep default" >> ${logFile}
fi

# SPARKO
if [ "${sparko}" = "on" ]; then
    echo "Provisioning Sparko - run config script" >> ${logFile}
    sudo sed -i "s/^message=.*/message='Setup SPARKO (takes time)'/g" ${infoFile}
    sudo -u admin /home/admin/config.scripts/cln-plugin.sparko.sh on mainnet >> ${logFile} 2>&1
    sudo systemctl disable cRTL # will get enabled after recover dialog
else
    echo "Provisioning RTL CLN - keep default" >> ${logFile}
fi

#LOOP
# install only if LiT won't be installed
if [ "${loop}" = "on" ] && [ "${#lit}" -eq 0 ] || [ "${lit}" = "off" ]; then
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
sudo /home/admin/config.scripts/blitz.display.sh rotate ${lcdrotate} >> ${logFile} 2>&1

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
  sudo -u admin /home/admin/config.scripts/bonus.specter.sh on >> ${logFile} 2>&1
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

# Pool
# install only if LiT won't be installed
if [ "${pool}" = "on" ] && [ "${#lit}" -eq 0 ] || [ "${lit}" = "off" ]; then
  echo "Provisioning Pool - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup Pool'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.pool.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Pool - keep default" >> ${logFile}
fi

# lit (make sure to be installed after RTL)
if [ "${lit}" = "on" ]; then
  echo "Provisioning LIT - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup LIT'/g" ${infoFile}
  sudo -u admin /home/admin/config.scripts/bonus.lit.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LIT - keep default" >> ${logFile}
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
echo "*** Repair Bitcoin Conf (if needed)" >> ${logFile}
confExists="$(sudo ls /mnt/hdd/${network} | grep -c "${network}.conf")"
if [ ${confExists} -eq 0 ]; then
  echo "Doing init of ${network}.conf" >> ${logFile}
  sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
  sudo chown bitcoin:bitcoin /mnt/hdd/bitcoin/bitcoin.conf
fi

# signal setup done
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

# MAKE SURE SERVICES ARE RUNNING
echo "Make sure main services are running .." >> ${logFile}
sudo systemctl start ${network}d
if [ "${lightning}" == "lnd" ];then
  sudo systemctl start lnd
elif [ "${lightning}" == "cln" ];then
  sudo systemctl start lightningd
fi

echo "DONE - Give raspi some cool off time after hard building .... 5 secs sleep" >> ${logFile}
sleep 5

echo "END Provisioning" >> ${logFile}
