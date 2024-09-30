#!/bin/bash

# check if run by root user
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root'"
  exit 1
fi

# This script gets called from a fresh SD card
# starting up that has a config file on HDD
# from old RaspiBlitz or manufacturer
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
source ${infoFile}
source ${configFile}

##########################
# BASIC SYSTEM SETTINGS
##########################

echo "### BASIC SYSTEM SETTINGS ###" >> ${logFile}
/home/admin/_cache.sh set message "Setup System ."

echo "# Make sure the user bitcoin is in the debian-tor group"
usermod -a -G debian-tor bitcoin

# make sure to have bitcoin core >=22 is backwards comp
# see https://github.com/rootzoll/raspiblitz/issues/2546
sed -i '/^deprecatedrpc=.*/d' /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null
echo "deprecatedrpc=addresses" >> /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null

# backup SSH PubKeys
/home/admin/config.scripts/blitz.ssh.sh backup

# set timezone
/home/admin/config.scripts/blitz.time.sh set-by-config >> ${logFile}

# optimize mempool if RAM >1GB
kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
if [ ${kbSizeRAM} -gt 1500000 ]; then
  echo "Detected RAM >1GB --> optimizing ${network}.conf"
  sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/${network}/${network}.conf
fi
if [ ${kbSizeRAM} -gt 3500000 ]; then
  echo "Detected RAM >3GB --> optimizing ${network}.conf"
  sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/${network}/${network}.conf
fi

# zram on for all devices
/home/admin/config.scripts/blitz.zram.sh on >> ${logFile}

# link and copy HDD content into new OS on sd card
echo "Copy HDD content for user admin" >> ${logFile}
mkdir /home/admin/.${network} >> ${logFile}
cp /mnt/hdd/${network}/${network}.conf /home/admin/.${network}/${network}.conf >> ${logFile} 2>&1
mkdir /home/admin/.lnd >> ${logFile}
cp /mnt/hdd/lnd/lnd.conf /home/admin/.lnd/lnd.conf >> ${logFile}
cp /mnt/hdd/lnd/tls.cert /home/admin/.lnd/tls.cert >> ${logFile}
mkdir /home/admin/.lnd/data >> ${logFile}
cp -r /mnt/hdd/lnd/data/chain /home/admin/.lnd/data/chain >> ${logFile} 2>&1
chown -R admin:admin /home/admin/.${network} >> ${logFile} 2>&1
chown -R admin:admin /home/admin/.lnd >> ${logFile} 2>&1
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
echo "open firewall for auto nat discover (see issue #129 & #3144)"
ufw allow proto udp from 10.0.0.0/8 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 172.16.0.0/12 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 192.168.0.0/16 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 192.168.0.0/16 port 5350 to any comment 'Bonjour NAT'
ufw allow proto udp from 172.16.0.0/12 port 5350 to any comment 'Bonjour NAT'
ufw allow proto udp from 192.168.0.0/16 port 5351 to any comment 'Bonjour NAT'
ufw allow proto udp from 172.16.0.0/12 port 5351 to any comment 'Bonjour NAT'

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

echo "### CHECKING BLITZ-API/FRONT STATUS ###" >> ${logFile}
blitzApiInstalled=$(systemctl status blitzapi | grep -c "loaded")
echo "# blitzapi(${blitzapi}) blitzApiInstalled(${blitzApiInstalled})"
if [ "${blitzapi}" != "on" ] && [ ${blitzApiInstalled} -gt 0 ]; then
  /home/admin/_cache.sh set message "Deactivated API/WebUI (as in your config) - please use SSH for further setup"
  sleep 10
else
  /home/admin/_cache.sh set message "Installing Services"
fi

# BLITZ WEB SERVICE
echo "Provisioning BLITZ WEB SERVICE - run config script" >> ${logFile}
/home/admin/config.scripts/blitz.web.sh https-on >> ${logFile} 2>&1

# deinstall when not explizit 'on' when blitzapi is installed by fatpack
# https://github.com/raspiblitz/raspiblitz/issues/4171#issuecomment-1728302628
if [ "${blitzapi}" != "on" ] && [ ${blitzApiInstalled} -gt 0 ]; then
  echo "blitz_api directory exists & blitzapi is not 'on' - deactivating blitz-api" >> ${logFile}
  /home/admin/config.scripts/blitz.web.api.sh off >> ${logFile} 2>&1
  /home/admin/config.scripts/blitz.web.ui.sh off >> ${logFile} 2>&1
fi
# WebAPI & UI (in case image was not fatpack - but webapi was switchen on)
if [ "${blitzapi}" == "on" ] && [ $blitzApiInstalled -eq 0 ]; then
    echo "Provisioning BlitzAPI - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup BlitzAPI (takes time)"
    /home/admin/config.scripts/blitz.web.api.sh on DEFAULT >> ${logFile} 2>&1
    /home/admin/config.scripts/blitz.web.ui.sh on DEFAULT >> ${logFile} 2>&1
else
    echo "Provisioning BlitzAPI - keep default" >> ${logFile}
fi

echo "### RUNNING PROVISIONING SERVICES ###" >> ${logFile}

# BITCOIN INTERIMS UPDATE
if [ ${#bitcoinInterimsUpdate} -gt 0 ]; then
  /home/admin/_cache.sh set message "Bitcoin Core update"
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
    # determine the database version # Examples: 216 is CLN v23.02.2 # 219 is CLN v23.05
    clDbVersion=$(sqlite3 /mnt/hdd/app-data/.lightning/bitcoin/lightningd.sqlite3 "SELECT version FROM version;")
    if [ ${#clDbVersion} -eq 0 ]; then
      echo "Could not determine the CLN database version - using 0" >> ${logFile}
      clDbVersion=0
    else
      echo "The CLN database version is ${clDbVersion}" >> ${logFile}
    fi
    if [ ${clDbVersion} -lt 217 ]; then
      # even if reckless is set - update to the recommended release
      echo "Provisioning CL verified interims update" >> ${logFile}
      /home/admin/config.scripts/cl.update.sh verified >> ${logFile}
    else # 217 or higher
      # recklessly update CL to latest release on GitHub (just for test & dev nodes)
      echo "Provisioning CL reckless interims update" >> ${logFile}
      /home/admin/config.scripts/cl.update.sh reckless >> ${logFile}
    fi
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this is an update with a newer RaspiBlitz version .. interims update will be ignored
    # because the standard CL version is up to date
    echo "Provisioning CL verified interims update" >> ${logFile}
    /home/admin/config.scripts/cl.update.sh verified ${clInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning CL interims update - keep default" >> ${logFile}
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

# CORE LIGHTNING binary install
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ] || [ "${tcl}" == "on" ] || [ "${scl}" == "on" ]; then
  # if already installed by fatpack will skip
  echo "Provisioning Core Lightning Binary - run config script" >> ${logFile}
  /home/admin/config.scripts/cl.install.sh install >> ${logFile} 2>&1
else
    echo "Provisioning Core Lightning Binary - not active" >> ${logFile}
fi

# CL Mainnet
if [ "${cl}" == "on" ]; then
    echo "Provisioning CL Mainnet - run config script" >> ${logFile}
    /home/admin/config.scripts/cl.install.sh on mainnet >> ${logFile} 2>&1
else
  echo "Provisioning CL Mainnet - not active" >> ${logFile}
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

# NETWORK UPNP
if [ "${networkUPnP}" = "on" ]; then
    echo "Provisioning NETWORK UPnP - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup UPnP"
    /home/admin/config.scripts/network.upnp.sh on >> ${logFile} 2>&1
else
    echo "Provisioning NETWORK UPnP  - keep default" >> ${logFile}
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

# clHTTPplugin
if [ "${clHTTPplugin}" = "on" ]; then
    echo "Provisioning clHTTPplugin - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup clHTTPplugin"
    sudo -u admin /home/admin/config.scripts/cl-plugin.http.sh on >> ${logFile} 2>&1
else
    echo "Provisioning clHTTPplugin - keep default" >> ${logFile}
fi

# clboss
if [ "${clboss}" = "on" ]; then
    echo "Provisioning clboss - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup clboss"
    sudo -u admin /home/admin/config.scripts/cl-plugin.clboss.sh on >> ${logFile} 2>&1
else
    echo "Provisioning clboss - keep default" >> ${logFile}
fi

# clWatchtowerClient
if [ "${clWatchtowerClient}" = "on" ]; then
    echo "Provisioning clWatchtowerClient - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup clWatchtowerClient"
    sudo -u admin /home/admin/config.scripts/cl-plugin.watchtower-client.sh on >> ${logFile} 2>&1
else
    echo "Provisioning clWatchtowerClient - keep default" >> ${logFile}
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

#FULCRUM
if [ "${fulcrum}" = "on" ]; then
  echo "Provisioning Fulcrum - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Fulcrum"
  sudo -u admin /home/admin/config.scripts/bonus.fulcrum.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Fulcrum - keep default" >> ${logFile}
fi

# BTCPAYSERVER
if [ "${BTCPayServer}" = "on" ]; then

  echo "Provisioning BTCPAYSERVER on TOR - running setup" >> ${logFile}
  /home/admin/_cache.sh set message "Setup BTCPay (takes time)"
  sudo -u admin /home/admin/config.scripts/bonus.btcpayserver.sh on >> ${logFile} 2>&1

else
  echo "Provisioning BTCPayServer - keep default" >> ${logFile}
fi

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

# TOUCHSCREEN - deactivated see https://github.com/raspiblitz/raspiblitz/pull/4609#issuecomment-2144406124
# if [ "${#touchscreen}" -gt 0 ]; then
#     echo "Provisioning Touchscreen - run config script" >> ${logFile}
#     /home/admin/_cache.sh set message "Setup Touchscreen"
#     /home/admin/config.scripts/blitz.touchscreen.sh ${touchscreen} >> ${logFile} 2>&1
# else
#     echo "Provisioning Touchscreen - not active" >> ${logFile}
# fi

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

# Jam
if [ "${jam}" = "on" ]; then
  echo "Provisioning Jam - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Jam"
  sudo /home/admin/config.scripts/bonus.jam.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Jam - keep default" >> ${logFile}
fi

# Specter
if [ "${specter}" = "on" ]; then
  echo "Provisioning Specter - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Specter"
  sudo -u admin /home/admin/config.scripts/bonus.specter.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Specter - keep default" >> ${logFile}
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

# lit (make sure to be installed after RTL)
if [ "${lit}" = "on" ]; then
  echo "Provisioning LIT - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LIT"
  sudo -u admin /home/admin/config.scripts/bonus.lit.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LIT - keep default" >> ${logFile}
fi

# labelbase
if [ "${labelbase}" = "on" ]; then
  echo "Provisioning Labelbase - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Labelbase"
  sudo -u admin /home/admin/config.scripts/bonus.labelbase.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Labelbase - keep default" >> ${logFile}
fi

# lndg
if [ "${lndg}" = "on" ]; then
  echo "Provisioning LNDg - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LNDg"
  sudo -u admin /home/admin/config.scripts/bonus.lndg.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LNDg - keep default" >> ${logFile}
fi

# helipad
if [ "${helipad}" = "on" ]; then
  echo "Helipad - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Helipad"
  sudo -u admin /home/admin/config.scripts/bonus.helipad.sh on >> ${logFile} 2>&1
else
  echo "Helipad - keep default" >> ${logFile}
fi

# circuitbreaker
if [ "${circuitbreaker}" = "on" ]; then
  echo "Provisioning CircuitBreaker - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup CircuitBreaker"
  sudo -u admin /home/admin/config.scripts/bonus.circuitbreaker.sh on >> ${logFile} 2>&1
else
  echo "Provisioning CircuitBreaker - keep default" >> ${logFile}
fi

# squeaknode
if [ "${squeaknode}" = "on" ]; then
  echo "Provisioning Squeaknode - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Squeaknode"
  sudo -u admin /home/admin/config.scripts/bonus.squeaknode.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Squeaknode - keep default" >> ${logFile}
fi

# LightningTipBot
if [ "${lightningtipbot}" = "on" ]; then
  echo "Provisioning LightningTipBot - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LightningTipBot"
  sudo -u admin /home/admin/config.scripts/bonus.lightningtipbot.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LightningTipBot - keep default" >> ${logFile}
fi

# FinTS
if [ "${fints}" = "on" ]; then
  echo "Provisioning FinTS - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup FinTS"
  sudo -u admin /home/admin/config.scripts/bonus.fints.sh on >> ${logFile} 2>&1
else
  echo "Provisioning FinTS - keep default" >> ${logFile}
fi

# Bostr2
if [ "${bostr2}" = "on" ]; then
  echo "Provisioning Bostr2 - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Bostr2"
  sudo -u admin /home/admin/config.scripts/bonus.bostr2.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Bostr2 - keep default" >> ${logFile}
fi

# Tailscale
if [ "${tailscale}" = "on" ]; then
  echo "Provisioning Tailscale - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Tailscale"
  sudo -u admin /home/admin/config.scripts/bonus.tailscale.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Tailscale - keep default" >> ${logFile}
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
  echo "On next final restart admin creds will be updated by _bootstrap.sh" >> ${logFile}

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

# I2P
echo "Start i2pd" >> ${logFile}
/home/admin/_cache.sh set message "i2pd setup"
/home/admin/config.scripts/blitz.i2pd.sh on >> ${logFile}

# clean up raspiblitz config from old settings
sed -i '/^autoPilot=/d' /mnt/hdd/raspiblitz.conf
sed -i '/^lndKeysend=/d' /mnt/hdd/raspiblitz.conf

# signal setup done
/home/admin/_cache.sh set message "Setup Done"

# set the local network hostname (just if set in config - will not be set anymore by default in newer version)
# have at the end - see https://github.com/rootzoll/raspiblitz/issues/462
# see also https://github.com/rootzoll/raspiblitz/issues/819
if [ ${#hostname} -gt 0 ]; then
  hostnameSanatized=$(echo "${hostname}"| tr -dc '[:alnum:]\n\r')
  if [ ${#hostnameSanatized} -gt 0 ]; then
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
  sleep 10
  # set password c if given in flag from migration prep
  passwordFlagExists=$(ls /mnt/hdd/passwordc.flag | grep -c "passwordc.flag")
  if [ "${passwordFlagExists}" == "1" ]; then
    echo "Found /mnt/hdd/passwordc.flag .. changing password" >> ${logFile}
    oldPasswordC=$(cat /mnt/hdd/passwordc.flag)
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
