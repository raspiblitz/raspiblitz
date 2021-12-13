#!/bin/bash

# command info
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove LND services on parallel chains"
  echo "lnd.install.sh on [mainnet|testnet|signet] [?initwallet]"
  echo "lnd.install.sh off [mainnet|testnet|signet]"
  echo "lnd.install.sh display-seed [mainnet|testnet|signet] [?delete]"
  echo
  exit 1
fi

# CHAIN is signet | testnet | mainnet
CHAIN=$2
if [ ${CHAIN} = testnet ]||[ ${CHAIN} = mainnet ]||[ ${CHAIN} = signet ];then
  echo "# Configuring the LND instance on ${CHAIN}"
else
  echo "# ${CHAIN} is not supported"
  exit 1
fi

# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  netprefix="t"
  portprefix=1
  rpcportmod=1
  zmqprefix=21
elif [ ${CHAIN} = signet ];then
  netprefix="s"
  portprefix=3
  rpcportmod=3
  zmqprefix=23
elif [ ${CHAIN} = mainnet ];then
  netprefix=""
  portprefix=""
  rpcportmod=0
  zmqprefix=28
fi

source /home/admin/raspiblitz.info
# add default value to raspi config if needed
if ! grep -Eq "^lightning=" /mnt/hdd/raspiblitz.conf; then
  echo "lightning=lnd" | sudo tee -a /mnt/hdd/raspiblitz.conf
fi
# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}lnd=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}lnd=off" >> /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

function removeParallelService() {
  if [ -f "/etc/systemd/system/${netprefix}lnd.service" ];then
    sudo -u bitcoin /usr/local/bin/lncli\
     --rpcserver localhost:1${rpcportmod}009 stop
    sudo systemctl stop ${netprefix}lnd
    sudo systemctl disable ${netprefix}lnd
    sudo rm /etc/systemd/system/${netprefix}lnd.service 2>/dev/null
    echo "# ${netprefix}lnd.service on ${CHAIN} is stopped and disabled"
    echo
  fi
}


# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${CHAIN}" == "testnet" ] && [ "${testnet}" != "on" ]; then
    echo "# before activating testnet on lnd, first activate testnet on bitcoind"
    echo "err='missing bitcoin testnet'"
    exit 1
  fi

  if [ "${CHAIN}" == "signet" ] && [ "${signet}" != "on" ]; then
    echo "# before activating signet on lnd, first activate signet on bitcoind"
    echo "err='missing bitcoin signet'"
    exit 1
  fi

  initwallet=0
  if [ "$3" == "initwallet" ]; then
    initwallet=1
    echo "# OK will init wallet if not exists (may ask for passwordc)"
  fi

  sudo ufw allow ${portprefix}9735 comment '${netprefix}lnd'
  sudo ufw allow ${portprefix}8080 comment '${netprefix}lnd REST'
  sudo ufw allow 1${rpcportmod}009 comment '${netprefix}lnd RPC'

  echo "# Prepare directories"
  if [ ! -d /mnt/hdd/lnd ]; then
    echo "# Creating /mnt/hdd/lnd"
    sudo mkdir /mnt/hdd/lnd
  fi
  sudo chown -R bitcoin:bitcoin /mnt/hdd/lnd
  if [ ! -L /home/bitcoin/.lnd ];then
    echo "# Linking lnd for user bitcoin"
    sudo rm /home/bitcoin/.lnd 2>/dev/null
    sudo ln -s /mnt/hdd/lnd /home/bitcoin/.lnd
  fi

  echo "# Create /home/bitcoin/.lnd/${netprefix}lnd.conf"
  if [ ! -f /home/bitcoin/.lnd/${netprefix}lnd.conf ];then
    echo "# LND configuration

[Application Options]
# alias=ALIAS # up to 32 UTF-8 characters
# color=COLOR # choose from: https://www.color-hex.com/
listen=0.0.0.0:${portprefix}9735
rpclisten=0.0.0.0:1${rpcportmod}009
restlisten=0.0.0.0:${portprefix}8080
nat=false
debuglevel=debug
gc-canceled-invoices-on-startup=true 
gc-canceled-invoices-on-the-fly=true 
ignore-historical-gossip-filters=1 
sync-freelist=true
stagger-initial-reconnect=true
tlsautorefresh=1
tlsdisableautofill=1
tlscertpath=/home/bitcoin/.lnd/tls.cert
tlskeypath=/home/bitcoin/.lnd/tls.key

[Bitcoin]
bitcoin.active=1
bitcoin.${CHAIN}=1
bitcoin.node=bitcoind
" | sudo -u bitcoin tee /home/bitcoin/.lnd/${netprefix}lnd.conf
  else
    echo "# The file /home/bitcoin/.lnd/${netprefix}lnd.conf is already present"
  fi

  # systemd service  
  removeParallelService
  echo "# Create /etc/systemd/system/.lnd.service"
  echo "
[Unit]
Description=LND on $NETWORK

[Service]
User=bitcoin
Group=bitcoin
Type=simple
EnvironmentFile=/mnt/hdd/raspiblitz.conf
ExecStartPre=-/home/admin/config.scripts/lnd.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/lnd --configfile=/home/bitcoin/.lnd/${netprefix}lnd.conf
Restart=always
TimeoutSec=240
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${netprefix}lnd.service
  sudo systemctl enable ${netprefix}lnd 
  echo "# Enabled the ${netprefix}lnd.service"
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${netprefix}lnd
    echo "# Started the ${netprefix}lnd.service"
  fi

  echo
  echo "# Adding aliases"
  echo "\
alias ${netprefix}lncli=\"sudo -u bitcoin /usr/local/bin/lncli\
 -n=${CHAIN} --rpcserver localhost:1${rpcportmod}009\"\
" | sudo tee -a /home/admin/_aliases

  # if parameter "initwallet" was set and wallet does not exist yet
  walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${CHAIN}/wallet.db 2>/dev/null | grep -c "wallet.db")
  if [ "${initwallet}" == "1" ] && [ "${walletExists}" == "0" ]; then
      # only ask on mainnet for passwordC - for the testnet/signet its default 'raspiblitz'
      if [ "${CHAIN}" == "mainnet" ]; then      
        tempFile="/var/cache/raspiblitz/passwordc.tmp"
        sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD C - LND Wallet Password" ${tempFile}
        passwordC=$(sudo cat ${tempFile})
        sudo rm ${tempFile}
      else
        passwordC="raspiblitz"
      fi
      source <(sudo /home/admin/config.scripts/lnd.initwallet.py new ${CHAIN} ${passwordC})
      if [ "${err}" != "" ]; then
        clear
        echo "# !!! LND ${CHAIN} wallet creation failed"
        echo "# ${err}"
        echo "# press ENTER to continue"
        read key
      else
        seedFile="/mnt/hdd/lnd/data/chain/${network}/${CHAIN}/seedwords.info"
        echo "seedwords='${seedwords}'" | sudo tee ${seedFile}
        echo "seedwords6x4='${seedwords6x4}'" | sudo tee -a ${seedFile}
      fi
  fi

  echo
  echo "# The installed LND version is: $(sudo -u bitcoin /usr/local/bin/lnd --version)"
  echo   
  echo "# To activate the aliases reopen the terminal or use:"
  echo "source ~/_aliases"
  echo "# Monitor the ${netprefix}lnd with:"
  echo "sudo journalctl -fu ${netprefix}lnd"
  echo "sudo systemctl status ${netprefix}lnd"
  echo "# logs:"
  echo "sudo tail -f /home/bitcoin/.lnd/logs/bitcoin/${CHAIN}/lnd.log"
  echo "# for the command line options use"
  echo "${netprefix}lncli help"
  echo

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}lnd=.*/${netprefix}lnd=on/g" /mnt/hdd/raspiblitz.conf

  # if this is the first lightning mainnet turned on - make default
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "" ]; then
    echo "# LND is now default lighthning implementation"
    sudo sed -i "s/^lightning=.*/lightning=lnd/g" /mnt/hdd/raspiblitz.conf
  fi

  exit 0
fi

if [ "$1" = "display-seed" ]; then
  
  # check if sudo
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (with sudo)"
    exit 1
  fi

  # get network and aliasses from second parameter (default mainnet)
  displayNetwork=$2
  if [ "${displayNetwork}" == "" ]; then
    displayNetwork="mainnet"
  fi

  deleteSeedInfoAfterDisplay=0
  if [ "$3" == "delete" ]; then
    echo "# deleting seedinfo after display"
    deleteSeedInfoAfterDisplay=1
  fi

  # check if seedword file exists
  seedwordFile="/mnt/hdd/lnd/data/chain/${network}/${CHAIN}/seedwords.info"
  echo "# seewordFile(${seedwordFile})"
  seedwordFileExists=$(ls ${seedwordFile} 2>/dev/null | grep -c "seedwords.info")
  echo "# seewordFileExists(${seewordFileExists})"
  if [ "${seedwordFileExists}" == "1" ]; then
    source ${seedwordFile}
    #echo "# seedwords(${seedwords})"
    #echo "# seedwords6x4(${seedwords6x4})"
    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "LND ${displayNetwork} Wallet" \
        --msgbox "This is your LND ${displayNetwork} wallet seed. Store these numbered words in a safe location:\n\n${seedwords6x4}" 13 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
    if [ "${deleteSeedInfoAfterDisplay}" == "1" ]; then
      echo "# deleting seed info"
      sudo shred ${seedwordFile}
      sudo rm ${seedwordFile}
    fi
  else
    walletFile="/mnt/hdd/lnd/data/chain/${network}/${CHAIN}/wallet.db"
    whiptail --title "LND ${displayNetwork} Wallet Info" --msgbox "Your LND ${displayNetwork} wallet was already created before - there are no seed words available.\n\nTo secure your wallet secret you can manually backup the file: ${walletFile}" 11 76
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# removing ${CHAIN} lnd service (if active)"

  removeParallelService

  # setting value in raspiblitz config
  sudo sed -i "s/^${netprefix}lnd=.*/${netprefix}lnd=off/g" /mnt/hdd/raspiblitz.conf

  # if lnd mainnet was default - remove 
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "lnd" ]; then
    echo "# LND is REMOVED as default lightning implementation"
    sudo sed -i "s/^lightning=.*/lightning=/g" /mnt/hdd/raspiblitz.conf
    if [ "${cl}" == "on" ]; then
      echo "# CL is now the new default lightning implementation"
      sudo sed -i "s/^lightning=.*/lightning=cl/g" /mnt/hdd/raspiblitz.conf
    fi
  fi

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
