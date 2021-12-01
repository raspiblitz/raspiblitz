#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove LND services on parallel chains"
  echo "lnd.install.sh install - called by the build_sdcard.sh"
  echo "lnd.install.sh on [mainnet|testnet|signet] [?initwallet]"
  echo "lnd.install.sh off [mainnet|testnet|signet]"
  echo "lnd.install.sh display-seed [mainnet|testnet|signet] [?delete]"
  echo
  exit 1
fi

if [ "$1" = "install" ] ; then
  echo "*** PREPARING LND ***"
  
  # "*** LND ***"
  ## based on https://raspibolt.github.io/raspibolt/raspibolt_40_lnd.html#lightning-lnd
  ## see LND releases: https://github.com/lightningnetwork/lnd/releases
  ## !!!! If you change here - make sure to also change interims version in lnd.update.sh !!!
  lndVersion="0.14.1-beta"

  # olaoluwa
  # PGPauthor="roasbeef"
  # PGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
  # PGPcheck="E4D85299674B2D31FAA1892E372CBD7633C61696"

  # guggero
  PGPauthor="guggero"
  PGPpkeys="https://keybase.io/guggero/pgp_keys.asc"
  PGPcheck="F4FC70F07310028424EFC20A8E4256593F177720"

  # bitconner
  #PGPauthor="bitconner"
  #PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
  #PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"
  
  # get LND resources
  cd /home/admin/download || exit 1
  
  # download lnd binary checksum manifest
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt

  # check if checksums are signed by lnd dev team
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-${PGPauthor}-v${lndVersion}.sig
  sudo -u admin wget --no-check-certificate -N -O "pgp_keys.asc" ${PGPpkeys}
  gpg --import --import-options show-only ./pgp_keys.asc
  fingerprint=$(sudo gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
  if [ ${fingerprint} -lt 1 ]; then
    echo ""
    echo "!!! BUILD WARNING --> LND PGP author not as expected"
    echo "Should contain PGP: ${PGPcheck}"
    echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
    read key
  fi
  gpg --import ./pgp_keys.asc
  sleep 3
  verifyResult=$(gpg --verify manifest-${PGPauthor}-v${lndVersion}.sig manifest-v${lndVersion}.txt 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature(${goodSignature})"
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
  echo "correctKey(${correctKey})"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo
    echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
    exit 1
  else
    echo
    echo "****************************************"
    echo "OK --> SIGNATURE LND MANIFEST IS CORRECT"
    echo "****************************************"
    echo
  fi

  # get the lndSHA256 for the corresponding platform from manifest file
  if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
    lndOSversion="armv7"
    lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
    lndOSversion="arm64"
    lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
    lndOSversion="amd64"
    lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
  fi

  echo
  echo "*** LND v${lndVersion} for ${lndOSversion} ***"
  echo "SHA256 hash: $lndSHA256"
  echo
  
  # get LND binary
  binaryName="lnd-linux-${lndOSversion}-v${lndVersion}.tar.gz"
  if [ ! -f "./${binaryName}" ]; then
    lndDownloadUrl="https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/${binaryName}"
    echo "- downloading lnd binary --> ${lndDownloadUrl}"
    sudo -u admin wget ${lndDownloadUrl}
    echo "- download done"
  else
    echo "- using existing lnd binary"
  fi
  
  # check binary was not manipulated (checksum test)
  echo "- checksum test"
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  echo "Valid SHA256 checksum(s) should be: ${lndSHA256}"
  echo "Downloaded binary SHA256 checksum: ${binaryChecksum}"
  checksumCorrect=$(echo "${lndSHA256}" | grep -c "${binaryChecksum}")
  if [ "${checksumCorrect}" != "1" ]; then
    echo "!!! FAIL !!! Downloaded LND BINARY not matching SHA256 checksum in manifest: ${lndSHA256}"
    rm -v ./${binaryName}
    exit 1
  else
    echo
    echo "****************************************"
    echo "OK --> VERIFIED LND CHECKSUM IS CORRECT"
    echo "****************************************"
    echo
    sleep 10
  fi
  
  # install
  echo "- install LND binary"
  sudo -u admin tar -xzf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-${lndOSversion}-v${lndVersion}/*
  sleep 3
  installed=$(sudo -u admin lnd --version)
  if [ ${#installed} -eq 0 ]; then
    echo
    echo "!!! BUILD FAILED --> Was not able to install LND"
    exit 1
  fi
  
  correctVersion=$(sudo -u admin lnd --version | grep -c "${lndVersion}")
  if [ ${correctVersion} -eq 0 ]; then
    echo ""
    echo "!!! BUILD FAILED --> installed LND is not version ${lndVersion}"
    sudo -u admin lnd --version
    exit 1
  fi
  sudo chown -R admin /home/admin
  echo "- OK install of LND done"
  exit 0
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
Description=LND on $CHAIN

[Service]
User=bitcoin
Group=bitcoin
Type=simple
EnvironmentFile=/mnt/hdd/raspiblitz.conf
ExecStartPre=-/home/admin/config.scripts/lnd.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/lnd --configfile=/home/bitcoin/.lnd/${netprefix}lnd.conf
Restart=always
TimeoutSec=120
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
  echo "# Add aliases ${netprefix}lncli, ${netprefix}lndlog"
  if [ $(alias | grep -c "alias ${netprefix}lncli") -eq 0 ];then 
    echo "\
alias ${netprefix}lncli=\"sudo -u bitcoin /usr/local/bin/lncli\
 -n=${CHAIN} --rpcserver localhost:1${rpcportmod}009\"\
" | sudo tee -a /home/admin/_aliases
  fi
  if [ $(alias | grep -c "alias ${netprefix}lndlog") -eq 0 ];then
    echo "\
alias ${netprefix}lndlog=\"sudo tail -n 30 -f /mnt/hdd/lnd/logs/${network}/${CHAIN}/lnd.log\"\
" | sudo tee -a /home/admin/_aliases
  fi

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
      if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi
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