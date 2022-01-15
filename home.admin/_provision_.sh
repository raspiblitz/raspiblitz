#!/bin/bash

# check if run by root user
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

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

# SETUPFILE
# this key/value file contains the state during the setup process
setupFile="/var/cache/raspiblitz/temp/raspiblitz.setup"
source ${setupFile}

# log header
echo "" >> ${logFile}
echo "###################################" >> ${logFile}
echo "# _provision_.sh" >> ${logFile}
echo "###################################" >> ${logFile}
/home/admin/_cache.sh set message "Provisioning from Config"

# check if there is a config file
configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
  /home/admin/config.scripts/blitz.error.sh _provision_.sh "missing-config" "no config file (${configFile}) found to run provision" "" ${logFile}
  exit 1
fi

# import config values
source ${configFile}

##########################
# BASIC SYSTEM SETTINGS
##########################

echo "### BASIC SYSTEM SETTINGS ###" >> ${logFile}
/home/admin/_cache.sh set message "Setup System ."

echo "# Make sure the user bitcoin is in the debian-tor group"
usermod -a -G debian-tor bitcoin

echo "# Optimizing log files: rotate daily, keep 2 weeks & compress old days " >> ${logFile}
sed -i "s/^weekly/daily/g" /etc/logrotate.conf >> ${logFile} 2>&1
sed -i "s/^rotate 4/rotate 14/g" /etc/logrotate.conf >> ${logFile} 2>&1
sed -i "s/^#compress/compress/g" /etc/logrotate.conf >> ${logFile} 2>&1
systemctl restart logrotate

# make sure to have bitcoin core >=22 is backwards comp
# see https://github.com/rootzoll/raspiblitz/issues/2546
sed -i '/^deprecatedrpc=.*/d' /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null
echo "deprecatedrpc=addresses" >> /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null

# backup SSH PubKeys
/home/admin/config.scripts/blitz.ssh.sh backup

# optimze mempool if RAM >1GB
kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
if [ ${kbSizeRAM} -gt 1500000 ]; then
  echo "Detected RAM >1GB --> optimizing ${network}.conf"
  sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/${network}/${network}.conf
fi
if [ ${kbSizeRAM} -gt 3500000 ]; then
  echo "Detected RAM >3GB --> optimizing ${network}.conf"
  sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/${network}/${network}.conf
fi

# link and copy HDD content into new OS on sd card
echo "Copy HDD content for user admin" >> ${logFile}
mkdir /home/admin/.${network} >> ${logFile} 2>&1
cp /mnt/hdd/${network}/${network}.conf /home/admin/.${network}/${network}.conf >> ${logFile} 2>&1
mkdir /home/admin/.lnd >> ${logFile} 2>&1
cp /mnt/hdd/lnd/lnd.conf /home/admin/.lnd/lnd.conf >> ${logFile} 2>&1
cp /mnt/hdd/lnd/tls.cert /home/admin/.lnd/tls.cert >> ${logFile} 2>&1
mkdir /home/admin/.lnd/data >> ${logFile} 2>&1
cp -r /mnt/hdd/lnd/data/chain /home/admin/.lnd/data/chain >> ${logFile} 2>&1
chown -R admin:admin /home/admin/.${network} >> ${logFile} 2>&1
chown -R admin:admin /home/admin/.lnd >> ${logFile} 2>&1
cp /home/admin/assets/${network}d.service /etc/systemd/system/${network}d.service >> ${logFile} 2>&1
cp /home/admin/assets/tmux.conf.local /mnt/hdd/.tmux.conf.local >> ${logFile} 2>&1
chown admin:admin /mnt/hdd/.tmux.conf.local >> ${logFile} 2>&1
ln -s -f /mnt/hdd/.tmux.conf.local /home/admin/.tmux.conf.local >> ${logFile} 2>&1


# PREPARE LND (if activated)
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  # backup LND TLS certs
  # https://github.com/rootzoll/raspiblitz/issues/324
  echo "*** Make backup of LND TLS files" >> ${logFile}
  rm -r  /var/cache/raspiblitz/tls_backup 2>/dev/null
  mkdir /var/cache/raspiblitz/tls_backup 2>/dev/null
  cp /mnt/hdd/lnd/tls.cert /var/cache/raspiblitz/tls_backup/tls.cert >> ${logFile} 2>&1
  cp /mnt/hdd/lnd/tls.key /var/cache/raspiblitz/tls_backup/tls.key >> ${logFile} 2>&1
fi
echo "" >> ${logFile}

##########################
# FINISH SETUP
##########################

# finish setup (SWAP, Benus, Firewall, Update, ..)
/home/admin/_cache.sh set message "Setup System .."

# add bonus scripts (auto install deactivated to reduce third party repos)
mkdir /home/admin/tmpScriptDL
cd /home/admin/tmpScriptDL
echo "installing bash completion for bitcoin-cli and lncli"
wget https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/bitcoin-cli.bash-completion
wget https://raw.githubusercontent.com/lightningnetwork/lnd/master/contrib/lncli.bash-completion
cp *.bash-completion /etc/bash_completion.d/
echo "OK - bash completion available after next login"
echo "type \"bitcoin-cli getblockch\", press [Tab] → bitcoin-cli getblockchaininfo"
rm -r /home/admin/tmpScriptDL
cd

###### SWAP File
source <(/home/admin/config.scripts/blitz.datadrive.sh status)
if [ ${isSwapExternal} -eq 0 ]; then
  echo "No external SWAP found - creating ... "
  /home/admin/config.scripts/blitz.datadrive.sh swap on
else
  echo "SWAP already OK"
fi

####### FIREWALL - just install (not configure)
echo ""
echo "*** Setting and Activating Firewall ***"
echo "deny incoming connection on other ports"
ufw default deny incoming
echo "allow outgoing connections"
ufw default allow outgoing
echo "allow: ssh"
ufw allow ssh
echo "allow: bitcoin testnet"
ufw allow 18333 comment 'bitcoin testnet'
echo "allow: bitcoin mainnet"
ufw allow 8333 comment 'bitcoin mainnet'
echo 'allow: lightning testnet'
ufw allow 19735 comment 'lightning testnet'
echo "allow: lightning mainnet"
ufw allow 9735 comment 'lightning mainnet'
echo "allow: lightning gRPC"
ufw allow 10009 comment 'lightning gRPC'
echo "allow: lightning REST API"
ufw allow 8080 comment 'lightning REST API'
echo "allow: public web HTTP"
ufw allow from any to any port 80 comment 'allow public web HTTP'
echo "allow: local web admin HTTPS"
ufw allow from 10.0.0.0/8 to any port 443 comment 'allow local LAN HTTPS'
ufw allow from 172.16.0.0/12 to any port 443 comment 'allow local LAN HTTPS'
ufw allow from 192.168.0.0/16 to any port 443 comment 'allow local LAN HTTPS'
echo "open firewall for auto nat discover (see issue #129)"
ufw allow proto udp from 10.0.0.0/8 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 172.16.0.0/12 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 192.168.0.0/16 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
echo "enable lazy firewall"
ufw --force enable
echo ""

# update system
echo ""
echo "*** Update System ***"
apt-mark hold raspberrypi-bootloader
apt-get update -y
echo "OK - System is now up to date"

# mark setup is done
sed -i "s/^setupStep=.*/setupStep=100/g" /home/admin/raspiblitz.info

##########################
# PROVISIONING SERVICES
##########################
/home/admin/_cache.sh set message "Installing Services"

echo "### RUNNING PROVISIONING SERVICES ###" >> ${logFile}

# BLITZ WEB SERVICE
echo "Provisioning BLITZ WEB SERVICE - run config script" >> ${logFile}
/home/admin/config.scripts/blitz.web.sh on >> ${logFile} 2>&1

# BITCOIN INTERIMS UPDATE
if [ ${#bitcoinInterimsUpdate} -gt 0 ]; then
  /home/admin/_cache.sh set message "Provisioning Bitcoin Core update"
  if [ "${bitcoinInterimsUpdate}" == "reckless" ]; then
    # recklessly update Bitcoin Core to latest release on GitHub
    echo "Provisioning Bitcoin Core reckless interims update" >> ${logFile}
    /home/admin/config.scripts/bitcoin.update.sh reckless >> ${logFile}
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this a update with a newer RaspiBlitz version .. interims update will be ignored
    # because standard Bitcoin Core version is most more up to date
    echo "Provisioning Bitcoin Core tested interims update" >> ${logFile}
    /home/admin/config.scripts/bitcoin.update.sh tested ${bitcoinInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning Bitcoin Core interims update - keep default" >> ${logFile}
fi

# LND INTERIMS UPDATE
if [ ${#lndInterimsUpdate} -gt 0 ]; then
  /home/admin/_cache.sh set message "Provisioning LND update"
  if [ "${lndInterimsUpdate}" == "reckless" ]; then
    # recklessly update LND to latest release on GitHub (just for test & dev nodes)
    echo "Provisioning LND reckless interims update" >> ${logFile}
    /home/admin/config.scripts/lnd.update.sh reckless >> ${logFile}
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this a update with a newer RaspiBlitz version .. interims update will be ignored
    # because standard LND version is most more up to date
    echo "Provisioning LND verified interims update" >> ${logFile}
    /home/admin/config.scripts/lnd.update.sh verified ${lndInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning LND interims update - keep default" >> ${logFile}
fi

# CL INTERIMS UPDATE
if [ ${#clInterimsUpdate} -gt 0 ]; then
  /home/admin/_cache.sh set message "Provisioning CL update"
  if [ "${clInterimsUpdate}" == "reckless" ]; then
    # recklessly update CL to latest release on GitHub (just for test & dev nodes)
    echo "Provisioning CL reckless interims update" >> ${logFile}
    /home/admin/config.scripts/cl.update.sh reckless >> ${logFile}
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this a update with a newer RaspiBlitz version .. interims update will be ignored
    # because standard CL version is most more up to date
    echo "Provisioning CL verified interims update" >> ${logFile}
    /home/admin/config.scripts/cl.update.sh verified ${clInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning CL interims update - keep default" >> ${logFile}
fi

# Bitcoin Testnet
if [ "${testnet}" == "on" ]; then
    echo "Provisioning ${network} Testnet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on testnet >> ${logFile} 2>&1
    systemctl start tbitcoind >> ${logFile} 2>&1
else
    echo "Provisioning ${network} Testnet - not active" >> ${logFile}
fi

# Bitcoin Signet
if [ "${signet}" == "on" ]; then
    echo "Provisioning ${network} Signet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on signet >> ${logFile} 2>&1
    systemctl start sbitcoind >> ${logFile} 2>&1
else
    echo "Provisioning ${network} Signet - not active" >> ${logFile}
fi

# LND binary install
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ] || [ "${tlnd}" == "on" ] || [ "${slnd}" == "on" ]; then
  # if already installed by fatpack will skip 
  echo "Provisioning LND Binary - run config script" >> ${logFile}
  /home/admin/config.scripts/lnd.install.sh install >> ${logFile} 2>&1
else
    echo "Provisioning LND Binary - not active" >> ${logFile}
fi

# LND Mainnet (when not main instance)
if [ "${lnd}" == "on" ] && [ "${lightning}" != "lnd" ]; then
    echo "Provisioning LND Mainnet - run config script" >> ${logFile}
    /home/admin/config.scripts/lnd.install.sh on mainnet >> ${logFile} 2>&1
else
    echo "Provisioning LND Mainnet - not active as secondary option" >> ${logFile}
fi

# LND Testnet
if [ "${tlnd}" == "on" ]; then
    echo "Provisioning LND Testnet - run config script" >> ${logFile}
    /home/admin/config.scripts/lnd.install.sh on testnet >> ${logFile} 2>&1
    systemctl start tlnd >> ${logFile} 2>&1
else
    echo "Provisioning LND Testnet - not active" >> ${logFile}
fi

# LND Signet
if [ "${slnd}" == "on" ]; then
    echo "Provisioning LND Signet - run config script" >> ${logFile}
    /home/admin/config.scripts/lnd.install.sh on signet >> ${logFile} 2>&1
    systemctl start slnd >> ${logFile} 2>&1
else
  echo "Provisioning LND Signet - not active" >> ${logFile}
fi

# LND binary install
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ] || [ "${tcl}" == "on" ] || [ "${scl}" == "on" ]; then
  # if already installed by fatpack will skip 
  echo "Provisioning C-Lightning Binary - run config script" >> ${logFile}
  /home/admin/config.scripts/cl.install.sh on install >> ${logFile} 2>&1
else
    echo "Provisioning C-Lightning Binary - not active" >> ${logFile}
fi

# CL Mainnet (when not main instance)
if [ "${cl}" == "on" ] && [ "${lightning}" != "cl" ]; then
    echo "Provisioning CL Mainnet - run config script" >> ${logFile}
    /home/admin/config.scripts/cl.install.sh on mainnet >> ${logFile} 2>&1
else
  echo "Provisioning CL Mainnet - not active as secondary option" >> ${logFile}
fi

# CL Testnet
if [ "${tcl}" == "on" ]; then
    echo "Provisioning CL Testnet - run config script" >> ${logFile}
    /home/admin/config.scripts/cl.install.sh on testnet >> ${logFile} 2>&1
else
    echo "Provisioning CL Testnet - not active" >> ${logFile}
fi

# CL Signet
if [ "${scl}" == "on" ]; then
    echo "Provisioning CL Signet - run config script" >> ${logFile}
    /home/admin/config.scripts/cl.install.sh on signet >> ${logFile} 2>&1
else
    echo "Provisioning CL Signet - not active" >> ${logFile}
fi

# TOR
if [ "${runBehindTor}" == "on" ]; then
    echo "Provisioning TOR - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup Tor (takes time)"
    /home/admin/config.scripts/tor.network.sh on >> ${logFile} 2>&1
else
    echo "Provisioning Tor - keep default" >> ${logFile}
fi

# AUTO PILOT
if [ "${autoPilot}" = "on" ]; then
    echo "Provisioning AUTO PILOT - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup AutoPilot"
    /home/admin/config.scripts/lnd.autopilot.sh on >> ${logFile} 2>&1
else
    echo "Provisioning AUTO PILOT - keep default" >> ${logFile}
fi

# NETWORK UPNP
if [ "${networkUPnP}" = "on" ]; then
    echo "Provisioning NETWORK UPnP - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup UPnP"
    /home/admin/config.scripts/network.upnp.sh on >> ${logFile} 2>&1
else
    echo "Provisioning NETWORK UPnP  - keep default" >> ${logFile}
fi

# LND AUTO NAT DISCOVERY
if [ "${autoNatDiscovery}" = "on" ]; then
    echo "Provisioning LND AUTO NAT DISCOVERY - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup AutoNAT"
    /home/admin/config.scripts/lnd.autonat.sh on >> ${logFile} 2>&1
else
    echo "Provisioning AUTO NAT DISCOVERY - keep default" >> ${logFile}
fi

# DYNAMIC DOMAIN
if [ "${#dynDomain}" -gt 0 ]; then
    echo "Provisioning DYNAMIC DOMAIN - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup DynamicDomain"
    /home/admin/config.scripts/internet.dyndomain.sh on ${dynDomain} ${dynUpdateUrl} >> ${logFile} 2>&1
else
    echo "Provisioning DYNAMIC DOMAIN - keep default" >> ${logFile}
fi

# RTL (LND)
if [ "${rtlWebinterface}" = "on" ]; then
    echo "Provisioning RTL LND - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup RTL LND (takes time)"
    sudo -u admin /home/admin/config.scripts/bonus.rtl.sh on lnd mainnet >> ${logFile} 2>&1
else
    echo "Provisioning RTL LND - keep default" >> ${logFile}
fi

# RTL (CL)
if [ "${crtlWebinterface}" = "on" ]; then
    echo "Provisioning RTL CL - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup RTL CL (takes time)"
    sudo -u admin /home/admin/config.scripts/bonus.rtl.sh on cl mainnet >> ${logFile} 2>&1
else
    echo "Provisioning RTL CL - keep default" >> ${logFile}
fi

# SPARKO
if [ "${sparko}" = "on" ]; then
    echo "Provisioning Sparko - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup SPARKO"
    sudo -u admin /home/admin/config.scripts/cl-plugin.sparko.sh on mainnet >> ${logFile} 2>&1
else
    echo "Provisioning Sparko - keep default" >> ${logFile}
fi

# clHTTPplugin
if [ "${clHTTPplugin}" = "on" ]; then
    echo "Provisioning clHTTPplugin - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup clHTTPplugin"
    sudo -u admin /home/admin/config.scripts/cl-plugin.http.sh on >> ${logFile} 2>&1
else
    echo "Provisioning clHTTPplugin - keep default" >> ${logFile}
fi

# SPARK
if [ "${spark}" = "on" ]; then
    echo "Provisioning Spark Wallet - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup SPARK WALLET"
    sudo -u admin /home/admin/config.scripts/cl.spark.sh on mainnet >> ${logFile} 2>&1
else
    echo "Provisioning Spark Wallet - keep default" >> ${logFile}
fi

#LOOP - install only if LiT won't be installed
if [ "${loop}" = "on" ] && [ "${lit}" != "on" ]; then
  echo "Provisioning Lightning Loop - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Lightning Loop"
  sudo -u admin /home/admin/config.scripts/bonus.loop.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Lightning Loop - keep default" >> ${logFile}
fi

#BTC RPC EXPLORER
if [ "${BTCRPCexplorer}" = "on" ]; then
  echo "Provisioning BTCRPCexplorer - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup BTCRPCexplorer (takes time)"
  sudo -u admin /home/admin/config.scripts/bonus.btc-rpc-explorer.sh on >> ${logFile} 2>&1
else
  echo "Provisioning BTCRPCexplorer - keep default" >> ${logFile}
fi

#ELECTRS
if [ "${ElectRS}" = "on" ]; then
  echo "Provisioning ElectRS - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup ElectRS (takes time)"
  sudo -u admin /home/admin/config.scripts/bonus.electrs.sh on >> ${logFile} 2>&1
else
  echo "Provisioning ElectRS - keep default" >> ${logFile}
fi

# BTCPAYSERVER
if [ "${BTCPayServer}" = "on" ]; then

  echo "Provisioning BTCPAYSERVER on TOR - running setup" >> ${logFile}
  /home/admin/_cache.sh set message "Setup BTCPay (takes time)"
  sudo -u admin /home/admin/config.scripts/bonus.btcpayserver.sh on >> ${logFile} 2>&1

else
  echo "Provisioning BTCPayServer - keep default" >> ${logFile}
fi

# deprecated - see: #2031
# LNDMANAGE
#if [ "${lndmanage}" = "on" ]; then
#  echo "Provisioning lndmanage - run config script" >> ${logFile}
#  /home/admin/_cache.sh set message "Setup lndmanage"
#  sudo -u admin /home/admin/config.scripts/bonus.lndmanage.sh on >> ${logFile} 2>&1
#else
#  echo "Provisioning lndmanage - not active" >> ${logFile}
#fi

# CUSTOM PORT
echo "Provisioning LND Port" >> ${logFile}
if [ ${#lndPort} -eq 0 ]; then
  lndPort=$(cat /mnt/hdd/lnd/lnd.conf | grep "^listen=*" | cut -f2 -d':')
fi
if [ ${#lndPort} -gt 0 ]; then
  if [ "${lndPort}" != "9735" ]; then
    echo "User is running custom LND port: ${lndPort}" >> ${logFile}
    /home/admin/config.scripts/lnd.setport.sh ${lndPort} >> ${logFile} 2>&1
  else
    echo "User is running standard LND port: ${lndPort}" >> ${logFile}
  fi
else
  echo "Was not able to get LND port from config." >> ${logFile}
fi

# DNS Server
if [ ${#dnsServer} -gt 0 ]; then
    echo "Provisioning DNS Server - Setting DNS Server" >> ${logFile}
    /home/admin/config.scripts/internet.dns.sh ${dnsServer} >> ${logFile} 2>&1
else
    echo "Provisioning DNS Server - keep default" >> ${logFile}
fi

# CHANTOOLS
if [ "${chantools}" == "on" ]; then
    echo "Provisioning chantools - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup Chantools"
    /home/admin/config.scripts/bonus.chantools.sh on >> ${logFile} 2>&1
else
    echo "Provisioning chantools - keep default" >> ${logFile}
fi

# SSH TUNNEL
if [ "${#sshtunnel}" -gt 0 ]; then
    echo "Provisioning SSH Tunnel - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup SSH Tunnel"
    /home/admin/config.scripts/internet.sshtunnel.py restore ${sshtunnel} >> ${logFile} 2>&1
else
    echo "Provisioning SSH Tunnel - not active" >> ${logFile}
fi

# ZEROTIER
if [ "${#zerotier}" -gt 0 ] && [ "${zerotier}" != "off" ]; then
    echo "Provisioning ZeroTier - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup ZeroTier"
    /home/admin/config.scripts/bonus.zerotier.sh on ${zerotier} >> ${logFile} 2>&1
else
    echo "Provisioning ZeroTier - not active" >> ${logFile}
fi

# LCD ROTATE
if [ ${#lcdrotate} -eq 0 ]; then
  # when upgrading from an old raspiblitz - enforce lcdrotate = 0
  lcdrotate=0
fi
if [ "${lcdrotate}" == "0" ]; then
  echo "Provisioning LCD rotate - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "LCD Rotate"
  /home/admin/config.scripts/blitz.display.sh rotate ${lcdrotate} >> ${logFile} 2>&1
else
  echo "Provisioning LCD rotate - not needed, keep default rotate on" >> ${logFile}
fi

# TOUCHSCREEN
if [ "${#touchscreen}" -gt 0 ]; then
    echo "Provisioning Touchscreen - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup Touchscreen"
    /home/admin/config.scripts/blitz.touchscreen.sh ${touchscreen} >> ${logFile} 2>&1
else
    echo "Provisioning Touchscreen - not active" >> ${logFile}
fi

# UPS
if [ "${#ups}" -gt 0 ]; then
    echo "Provisioning UPS - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup UPS"
    /home/admin/config.scripts/blitz.ups.sh on ${ups} >> ${logFile} 2>&1
else
    echo "Provisioning UPS - not active" >> ${logFile}
fi

# LNbits
if [ "${LNBits}" = "on" ]; then
  if [ "${LNBitsFunding}" == "" ]; then
    LNBitsFunding="lnd"
  fi
  echo "Provisioning LNbits (${LNBitsFunding}) - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LNbits (${LNBitsFunding})"
  sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh on ${LNBitsFunding} >> ${logFile} 2>&1
else
  echo "Provisioning LNbits - keep default" >> ${logFile}
fi

# JoinMarket
if [ "${joinmarket}" = "on" ]; then
  echo "Provisioning JoinMarket - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup JoinMarket"
  /home/admin/config.scripts/bonus.joinmarket.sh on >> ${logFile} 2>&1
else
  echo "Provisioning JoinMarket - keep default" >> ${logFile}
fi

# JoinMarket Web UI
if [ "${joinmarketWebUI}" = "on" ]; then
  echo "Provisioning JoinMarket Web UI - run config script" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Setup JoinMarket Web UI'/g" ${infoFile}
  sudo /home/admin/config.scripts/bonus.joinmarket-webui.sh on >> ${logFile} 2>&1
else
  echo "Provisioning JoinMarket Web UI - keep default" >> ${logFile}
fi

# Specter
if [ "${specter}" = "on" ]; then
  echo "Provisioning Specter - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Specter"
  sudo -u admin /home/admin/config.scripts/bonus.specter.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Specter - keep default" >> ${logFile}
fi

# Faraday
if [ "${faraday}" = "on" ]; then
  echo "Provisioning Faraday - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Faraday"
  sudo -u admin /home/admin/config.scripts/bonus.faraday.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Faraday - keep default" >> ${logFile}
fi

# BOS
if [ "${bos}" = "on" ]; then
  echo "Provisioning Balance of Satoshis - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Balance of Satoshis"
  sudo -u admin /home/admin/config.scripts/bonus.bos.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Balance of Satoshis - keep default" >> ${logFile}
fi

# thunderhub
if [ "${thunderhub}" = "on" ]; then
  echo "Provisioning ThunderHub - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup ThunderHub"
  sudo -u admin /home/admin/config.scripts/bonus.thunderhub.sh on >> ${logFile} 2>&1
else
  echo "Provisioning ThunderHub - keep default" >> ${logFile}
fi

# mempool space
if [ "${mempoolExplorer}" = "on" ]; then
  echo "Provisioning MempoolSpace - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Mempool Space"
  sudo -u admin /home/admin/config.scripts/bonus.mempool.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Mempool Explorer - keep default" >> ${logFile}
fi

# letsencrypt
if [ "${letsencrypt}" = "on" ]; then
  echo "Provisioning letsencrypt - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup letsencrypt"
  sudo -u admin /home/admin/config.scripts/bonus.letsencrypt.sh on >> ${logFile} 2>&1
else
  echo "Provisioning letsencrypt - keep default" >> ${logFile}
fi

# kindle-display
if [ "${kindleDisplay}" = "on" ]; then
  echo "Provisioning kindle-display - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup kindle-display"
  sudo -u admin /home/admin/config.scripts/bonus.kindle-display.sh on >> ${logFile} 2>&1
else
  echo "Provisioning kindle-display - keep default" >> ${logFile}
fi

# pyblock
if [ "${pyblock}" = "on" ]; then
  echo "Provisioning pyblock - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup pyblock"
  sudo -u admin /home/admin/config.scripts/bonus.pyblock.sh on >> ${logFile} 2>&1
else
  echo "Provisioning pyblock - keep default" >> ${logFile}
fi

# stacking-sats-kraken
if [ "${stackingSatsKraken}" = "on" ]; then
  echo "Provisioning Stacking Sats Kraken - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Stacking Sats Kraken"
  sudo -u admin /home/admin/config.scripts/bonus.stacking-sats-kraken.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Stacking Sats Kraken - keep default" >> ${logFile}
fi

# Pool - install only if LiT won't be installed
if [ "${pool}" = "on" ] && [ "${lit}" != "on" ]; then
  echo "Provisioning Pool - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Pool"
  sudo -u admin /home/admin/config.scripts/bonus.pool.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Pool - keep default" >> ${logFile}
fi

# lit (make sure to be installed after RTL)
if [ "${lit}" = "on" ]; then
  echo "Provisioning LIT - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LIT"
  sudo -u admin /home/admin/config.scripts/bonus.lit.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LIT - keep default" >> ${logFile}
fi

# sphinxrelay
if [ "${sphinxrelay}" = "on" ]; then
  echo "Sphinx-Relay - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Sphinx-Relay"
  sudo -u admin /home/admin/config.scripts/bonus.sphinxrelay.sh on >> ${logFile} 2>&1
else
  echo "Sphinx-Relay - keep default" >> ${logFile}
fi

# circuitbreaker
if [ "${circuitbreaker}" = "on" ]; then
  echo "Provisioning CircuitBreaker - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup CircuitBreaker"
  sudo -u admin /home/admin/config.scripts/bonus.circuitbreaker.sh on >> ${logFile} 2>&1
else
  echo "Provisioning CircuitBreaker - keep default" >> ${logFile}
fi

# tallycoin_connect
if [ "${tallycoinConnect}" = "on" ]; then
  echo "Provisioning Tallycoin Connect - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Tallycoin Connect"
  sudo -u admin /home/admin/config.scripts/bonus.tallycoin-connect.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Tallycoin Connect - keep default" >> ${logFile}
fi

# custom install script from user
customInstallAvailable=$(ls /mnt/hdd/app-data/custom-installs.sh 2>/dev/null | grep -c "custom-installs.sh")
if [ ${customInstallAvailable} -gt 0 ]; then
  echo "Running the custom install script .." >> ${logFile}
  /home/admin/_cache.sh set message "Running Custom Install Script"
  # copy script over to admin (in case HDD is not allowing exec)
  cp -av /mnt/hdd/app-data/custom-installs.sh /home/admin/custom-installs.sh >> ${logFile}
  # make sure script is executable
  chmod +x /home/admin/custom-installs.sh >> ${logFile}
  # run it & delete it again
  /home/admin/custom-installs.sh >> ${logFile}
  rm /home/admin/custom-installs.sh >> ${logFile}
  echo "Done" >> ${logFile}
else
  echo "No custom install script ... adding the placeholder." >> ${logFile}
  cp /home/admin/assets/custom-installs.sh /mnt/hdd/app-data/custom-installs.sh
fi

# replay backup LND conf & tlscerts
# https://github.com/rootzoll/raspiblitz/issues/324
echo "" >> ${logFile}
echo "*** Replay backup of LND conf/tls" >> ${logFile}
if [ -d "/var/cache/raspiblitz/tls_backup" ]; then

  echo "Copying TLS ..." >> ${logFile}
  cp /var/cache/raspiblitz/tls_backup/tls.cert /mnt/hdd/lnd/tls.cert >> ${logFile} 2>&1
  cp /var/cache/raspiblitz/tls_backup/tls.key /mnt/hdd/lnd/tls.key >> ${logFile} 2>&1
  chown -R bitcoin:bitcoin /mnt/hdd/lnd >> ${logFile} 2>&1
  echo "On next final restart admin creds will be updated by _boostrap.sh" >> ${logFile}

  echo "DONE" >> ${logFile}
else
  echo "No BackupDir so skipping that step." >> ${logFile}
fi
echo "" >> ${logFile}

# repair Bitcoin conf if needed
echo "*** Repair Bitcoin Conf (if needed)" >> ${logFile}
confExists="$(ls /mnt/hdd/${network} | grep -c "${network}.conf")"
if [ ${confExists} -eq 0 ]; then
  echo "Doing init of ${network}.conf" >> ${logFile}
  cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
  chown bitcoin:bitcoin /mnt/hdd/bitcoin/bitcoin.conf
fi

# signal setup done
/home/admin/_cache.sh set message "Setup Done"

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
    if [ "${setnetworkname}" == "1" ]; then
      echo "Setting new network hostname '$hostnameSanatized'" >> ${logFile}
      if [ "${baseimage}" == "raspios_arm64" ]; then
         raspi-config nonint do_hostname ${hostnameSanatized} >> ${logFile} 2>&1
      else
         hostnameCurrent=$(hostname)
         sed -i "s/${hostnameCurrent}/${hostnameSanatized}/g" /etc/hostname 2>&1
         sed -i "s/${hostnameCurrent}/${hostnameSanatized}/g" /etc/hosts 2>&1
      fi
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
source <(/home/admin/config.scripts/blitz.datadrive.sh status)
# update /etc/fstab
echo "datadisk --> ${datadisk}" >> ${logFile}
echo "datapartition --> ${datapartition}" >> ${logFile}
if [ ${isBTRFS} -eq 0 ]; then
  /home/admin/config.scripts/blitz.datadrive.sh fstab ${datapartition} >> ${logFile}
else
  /home/admin/config.scripts/blitz.datadrive.sh fstab ${datadisk} >> ${logFile}
fi

# MAKE SURE SERVICES ARE RUNNING
echo "Make sure main services are running .." >> ${logFile}
systemctl start ${network}d
if [ "${lightning}" == "lnd" ];then
  systemctl start lnd
  # set password c if given in flag from migration prep
  passwordFlagExists=$(ls /mnt/hdd/passwordc.flag | grep -c "passwordc.flag")
  if [ "${passwordFlagExists}" == "1" ]; then
    echo "Found /mnt/hdd/passwordc.flag .. changing password" >> ${logFile}
    oldPasswordC=$(cat /mnt/hdd/passwordc.flag)
    if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi
    /home/admin/config.scripts/lnd.initwallet.py change-password mainnet "${oldPasswordC}" "${passwordC}" >> ${logFile}
    shred -u /mnt/hdd/passwordc.flag
  else
    echo "No /mnt/hdd/passwordc.flag" >> ${logFile}
  fi
elif [ "${lightning}" == "cl" ];then
  systemctl start lightningd
fi

echo "DONE - Give raspi some cool off time after hard building .... 5 secs sleep" >> ${logFile}
sleep 5

echo "END Provisioning" >> ${logFile}
exit 0
