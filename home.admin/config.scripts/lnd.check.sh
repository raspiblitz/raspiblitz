#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "# script to check LND states"
  echo "# lnd.check.sh basic-setup"
  echo "# lnd.check.sh prestart [mainnet|testnet|signet]"
  exit 1
fi

# load raspiblitz conf
source /mnt/hdd/raspiblitz.conf

######################################################################
# PRESTART
# is executed by systemd lnd services everytime before lnd is started
# so it tries to make sure the config is in valid shape
######################################################################

function setting() # FILE LINENUMBER NAME VALUE
{
  FILE=$1
  LINENUMBER=$2
  NAME=$3
  VALUE=$4
  settingExists=$(sudo cat ${FILE} | grep -c "^${NAME}=")
  echo "# ${NAME} exists->(${settingExists})"
  if [ "${settingExists}" == "0" ]; then
    echo "# adding setting (${NAME})"
    sudo sed -i "${LINENUMBER}i${NAME}=" ${FILE}
  fi
  echo "# updating setting (${NAME}) with value(${VALUE})"
  sudo sed -i "s/^${NAME}=.*/${NAME}=${VALUE}/g" ${FILE}
}

# check/repair lnd config before starting
if [ "$1" == "prestart" ]; then

  echo "### RUNNING lnd.check.sh prestart"
  echo "# user($USER)"

  # set default chain parameter
  targetchain=$2
  if [ "${targetchain}" == "" ]; then
    targetchain="mainnet"
  fi

  # restart counting
  if [ "${lightning}" == "lnd" ] && [ "${targetchain}" == "mainnet" ]; then
    # count start if that service is the main lightning client
    /home/admin/config.scripts/blitz.systemd.sh log lightning STARTED
  fi

  # prefixes for parallel services
  if [ "${targetchain}" = "mainnet" ];then
    netprefix=""
    portprefix=""
    rpcportmod=0
    zmqprefix=28
  elif [ "${targetchain}" = "testnet" ];then
    netprefix="t"
    portprefix=1
    rpcportmod=1
    zmqprefix=21
  elif [ "${targetchain}" = "signet" ];then
    netprefix="s"
    portprefix=3
    rpcportmod=3
    zmqprefix=23
  else
    echo "err='unvalid chain parameter on lnd.check.sh'"
    exit 1
  fi

  echo "# checking lnd config for ${targetchain}"
  lndConfFile="/mnt/hdd/lnd/${netprefix}lnd.conf"
  echo "# lndConfFile(${lndConfFile})"

  # [bitcoind] Section ..
  sectionName="[Bb]itcoind"
  if [ "${network}" != "bitcoin" ]; then
    sectionName="${network}d"
  fi
  echo "# [${sectionName}] config ..."

  # make sure lnd config has a [bitcoind] section
  sectionExists=$(sudo cat ${lndConfFile} | grep -c "^\[${sectionName}\]")
  echo "# sectionExists(${sectionExists})"
  if [ "${sectionExists}" == "0" ]; then
    echo "# adding section [${network}d]"
    echo "
[${network}d]
" | sudo tee -a ${lndConfFile}
  fi

  # get line number of [bitcoind] section
  sectionLine=$(sudo cat ${lndConfFile} | grep -n "^\[${sectionName}\]" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${lndConfFile} | cut -d " " -f1)
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
" | sudo tee -a ${lndConfFile}
  fi

  # CHECK zmqpubrawtx
  setting="zmqpubrawtx"
  value="tcp\:\/\/127\.0\.0\.1\:${zmqprefix}333"
  settingExists=$(sudo cat ${lndConfFile} | grep -c "^${network}d.${setting}=")
  echo "# ${network}d.${setting} exists->(${settingExists})"
  if [ "${settingExists}" == "0" ]; then
    echo "# adding setting (${setting})"
    sudo sed -i "${insertLine}i${network}d\.${setting}=" ${lndConfFile}
  fi
  echo "# updating setting (${setting}) with value(${value})"
  sudo sed -i "s/^${network}d\.${setting}=.*/${network}d\.${setting}=${value}/g" ${lndConfFile}

  # CHECK zmqpubrawblock
  setting ${lndConfFile} ${insertLine} "${network}d\.zmqpubrawblock" "tcp\:\/\/127\.0\.0\.1\:${zmqprefix}332"

    # remove RPC user & pass from lnd.conf ... since v1.7
    # https://github.com/rootzoll/raspiblitz/issues/2160
    # echo "- #2160 lnd.conf --> make sure contains no RPC user/pass for bitcoind" >> ${logFile}
    # sudo sed -i '/^\[Bitcoind\]/d' /mnt/hdd/lnd/lnd.conf
    # sudo sed -i '/^bitcoind.rpchost=/d' /mnt/hdd/lnd/lnd.conf
    # sudo sed -i '/^bitcoind.rpcpass=/d' /mnt/hdd/lnd/lnd.conf
    # sudo sed -i '/^bitcoind.rpcuser=/d' /mnt/hdd/lnd/lnd.conf
    # sudo sed -i '/^bitcoind.zmqpubrawblock=/d' /mnt/hdd/lnd/lnd.conf
    # sudo sed -i '/^bitcoind.zmqpubrawtx=/d' /mnt/hdd/lnd/lnd.conf


######################################################################
# BASIC-SETUP
# analyses if there are any possible problems with lnd setup
######################################################################

# check basic LND setup
elif [ "$1" == "basic-setup" ]; then

  # check TLS exits
  tlsExists=$(sudo ls /mnt/hdd/lnd/tls.cert 2>/dev/null | grep -c 'tls.cert')
  if [ ${tlsExists} -gt 0 ]; then
    echo "tls=1"
  else
    echo "tls=0"
    echo "err='tls.cert is missing in /mnt/hdd/lnd'"
  fi
  # check TLS exits (on SD card for admin)
  tlsExists=$(sudo ls /home/admin/.lnd/tls.cert 2>/dev/null | grep -c 'tls.cert')
  if [ ${tlsExists} -gt 0 ]; then
    echo "tlsCopy=1"
    # check if the same
    orgChecksum=$(sudo shasum -a 256 /mnt/hdd/lnd/tls.cert 2>/dev/null | cut -d " " -f1)
    cpyChecksum=$(sudo shasum -a 256 /home/admin/.lnd/tls.cert 2>/dev/null | cut -d " " -f1)
    if [ "${orgChecksum}" == "${cpyChecksum}" ]; then
      echo "tlsMismatch=0"
    else
      echo "tlsMismatch=1"
      echo "err='tls.cert for user admin is old'"
    fi
  else
    echo "tlsCopy=0"
    echo "tlsMismatch=0"
    echo "err='tls.cert is missing for user admin'"
  fi

  # check lnd.conf exists
  lndConfExists=$(sudo ls /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep -c 'lnd.conf')
  if [ ${lndConfExists} -gt 0 ]; then
    echo "config=1"
  else
    echo "config=0"
    echo "err='lnd.conf is missing in /mnt/hdd/lnd'"
  fi
  # check lnd.conf exits (on SD card for admin)
  lndConfExists=$(sudo ls /home/admin/.lnd/lnd.conf 2>/dev/null | grep -c 'lnd.conf')
  if [ ${lndConfExists} -gt 0 ]; then
    echo "configCopy=1"
    # check if the same
    orgChecksum=$(sudo shasum -a 256 /mnt/hdd/lnd/lnd.conf 2>/dev/null | cut -d " " -f1)
    cpyChecksum=$(sudo shasum -a 256 /home/admin/.lnd/lnd.conf 2>/dev/null | cut -d " " -f1)
    if [ "${orgChecksum}" == "${cpyChecksum}" ]; then
      echo "configMismatch=0"
    else
      echo "configMismatch=1"
      echo "err='lnd.conf for user admin is old'"
    fi
  else
    echo "configCopy=0"
    echo "configMismatch=0"
    echo "err='lnd.conf is missing for user admin'"
  fi

  # get network from config (BLOCKCHAIN)
  lndNetwork=""
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep 'bitcoin.active' | sed 's/^[a-z]*\./bitcoin_/g')
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep 'litecoin.active' | sed 's/^[a-z]*\./litecoin_/g')
  if [ "${bitcoin_active}" == "1" ] && [ "${litecoin_active}" == "1" ]; then
    echo "err='lnd.conf: bitcoin and litecoin are set active at the same time'"
  elif [ "${bitcoin_active}" == "1" ]; then
    lndNetwork="bitcoin"
  elif [ "${litecoin_active}" == "1" ]; then
    lndNetwork="litecoin"
  else
    echo "err='lnd.conf: no blockchain network is set'"
  fi
  echo "network='${lndNetwork}'"

  # check if network is same the raspiblitz config
  if [ "${network}" != "${lndNetwork}" ]; then
    echo "err='lnd.conf: blockchain network in lnd.conf (${lndNetwork}) is different from raspiblitz.conf (${network})'"
  fi

#  # get chain from config (TESTNET / MAINNET)
#  lndChain=""
#  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep "${lndNetwork}.mainnet" | sed 's/^[a-z]*\.//g')
#  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep "${lndNetwork}.testnet" | sed 's/^[a-z]*\.//g')
#  if [ "${mainnet}" == "1" ] && [ "${testnet}" == "1" ]; then
#    echo "err='lnd.conf: mainnet and testnet are set active at the same time'"
#  elif [ "${mainnet}" == "1" ]; then
#    lndChain="main"
#  elif [ "${testnet}" == "1" ]; then
#    lndChain="test"
#  else
#    echo "err='lnd.conf: neither testnet or mainnet is set active (raspiblitz needs one of them active in lnd.conf)'"
#  fi
#  echo "chain='${lndChain}'"
#
#  # check if chain is same the raspiblitz config
#  if [ "${chain}" != "${lndChain}" ]; then
#    echo "err='lnd.conf: testnet/mainnet in lnd.conf (${lndChain}) is different from raspiblitz.conf (${chain})'"
#  fi

  # check for admin macaroon exist (on HDD)
  adminMacaroonExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c 'admin.macaroon')
  if [ ${adminMacaroonExists} -gt 0 ]; then
    echo "macaroon=1"
  else
    echo "macaroon=0"
    echo "err='admin.macaroon is missing in /mnt/hdd/lnd/data/chain/${network}/${chain}net'"
  fi
  # check for admin macaroon exist (on SD card for admin)
  adminMacaroonExists=$(sudo ls /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c 'admin.macaroon')
  if [ ${adminMacaroonExists} -gt 0 ]; then
    echo "macaroonCopy=1"
    # check if the same
    orgChecksum=$(sudo shasum -a 256 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | cut -d " " -f1)
    cpyChecksum=$(sudo shasum -a 256 /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | cut -d " " -f1)
    if [ "${orgChecksum}" == "${cpyChecksum}" ]; then
      echo "macaroonMismatch=0"
    else
      echo "macaroonMismatch=1"
      echo "err='admin.macaroon for user admin is old'"
    fi
  else
    echo "macaroonCopy=0"
    echo "macaroonMismatch=0"
    echo "err='admin.macaroon is missing for user admin'"
  fi

  # check for walletDB exist
  walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/wallet.db 2>/dev/null | grep -c 'wallet.db')
  if [ ${walletExists} -gt 0 ]; then
    echo "wallet=1"
  else
    echo "wallet=0"
  fi

  # check basic LND logs
  torConnectionProblem=$(sudo journalctl -u lnd -b --no-pager -n14 | grep "lnd\[" | grep -c "dial tcp 127.0.0.1:9050: connect: connection refused")
  if [ ${torConnectionProblem} -gt 0 ]; then
    echo "err='Tor tcp connection refused'"
  fi

else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
