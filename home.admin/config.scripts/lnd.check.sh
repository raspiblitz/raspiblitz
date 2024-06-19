#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "# script to check LND states"
  echo "# lnd.check.sh basic-setup [mainnet|testnet|signet]"
  echo "# lnd.check.sh prestart [mainnet|testnet|signet]"
  exit 1
fi

# load raspiblitz conf
source /mnt/hdd/raspiblitz.conf
source <(/home/admin/config.scripts/network.aliases.sh getvars lnd $2)

# config file
echo "# checking lnd config for ${targetchain}"
echo "# lndConfFile(${lndConfFile})"

######################################################################
# PRESTART
# is executed by systemd lnd services everytime before lnd is started
# so it tries to make sure the config is in valid shape
######################################################################

function setting() { # FILE LINENUMBER NAME VALUE
  FILE=$1
  LINENUMBER=$2
  NAME=$3
  VALUE=$4
  settingExists=$(cat ${FILE} | grep -c "^${NAME}=")
  echo "# setting ${FILE} ${LINENUMBER} ${NAME} ${VALUE}"
  echo "# ${NAME} exists->(${settingExists})"
  if [ "${settingExists}" == "0" ]; then
    echo "# adding setting (${NAME})"
    sed -i "${LINENUMBER}i${NAME}=" ${FILE}
  fi
  echo "# updating setting (${NAME}) with value(${VALUE})"
  sed -i "s/^${NAME}=.*/${NAME}=${VALUE}/g" ${FILE}
}

# check/repair lnd config before starting
if [ "$1" == "prestart" ]; then

  echo "### RUNNING lnd.check.sh prestart"

  if [ "$USER" != "bitcoin" ]; then
    echo "# FAIL: run as user 'bitcoin'"
    exit 1
  fi

  ##### CLEAN UP #####

  # all lines with just spaces to empty lines
  sed -i 's/^[[:space:]]*$//g' /mnt/hdd/lnd/lnd.conf
  # all double empty lines to single empty lines
  sed -i '/^$/N;/^\n$/D' /mnt/hdd/lnd/lnd.conf

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

  ##### APPLICATION OPTIONS SECTION #####

  # remove sync-freelist=1 (use =true if you want to overrule raspiblitz)
  # https://github.com/rootzoll/raspiblitz/issues/3251
  sed -i "/^# Avoid slow startup time/d" ${lndConfFile}
  sed -i "/^sync-freelist=1/d" ${lndConfFile}

  # delete autounlock if passwordFile not present
  passwordFile="/mnt/hdd/lnd/data/chain/${network}/${CHAIN}/password.info"
  if ! ls ${passwordFile} &>/dev/null; then
    sed -i "/^wallet-unlock-password-file=/d" ${lndConfFile}
  fi

  ##### BITCOIN OPTIONS SECTION #####

  # [bitcoin]
  sectionName="[Bb]itcoin"
  if [ "${network}" != "bitcoin" ] && [ "${network}" != "" ]; then
    sectionName="${network}"
  fi
  echo "# [${sectionName}] config ..."

  # make sure lnd config has a [bitcoind] section
  sectionExists=$(cat ${lndConfFile} | grep -c "^\[${sectionName}\]")
  echo "# sectionExists(${sectionExists})"
  if [ "${sectionExists}" == "0" ]; then
    echo "# adding section [${network}]"
    echo "
[${network}]
" | tee -a ${lndConfFile}
  fi

  # get line number of [bitcoin] section
  sectionLine=$(cat ${lndConfFile} | grep -n "^\[${sectionName}\]" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${lndConfFile} | cut -d " " -f1)
  echo "# fileLines(${fileLines})"
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
" | tee -a ${lndConfFile}
  fi

  # SET/UPDATE bitcoin.active
  echo "# ${network}.active insert/update"
  setting ${lndConfFile} ${insertLine} "${network}\.active" "1"

  # SET/UPDATE bitcoin.mainnet
  echo "# ${network}.${targetchain} insert/update"
  setting ${lndConfFile} ${insertLine} "${network}\.${targetchain}" "1"

  # SET/UPDATE bitcoin.node
  echo "# ${network}.node insert/update"
  setting ${lndConfFile} ${insertLine} "${network}\.node" "${network}d"

  ##### BITCOIND OPTIONS SECTION #####

  # [bitcoind]
  sectionName="[Bb]itcoind"
  if [ "${network}" != "bitcoin" ] && [ "${network}" != "" ]; then
    sectionName="${network}d"
  fi
  echo "# [${sectionName}] config ..."

  # make sure lnd config has a [bitcoind] section
  sectionExists=$(cat ${lndConfFile} | grep -c "^\[${sectionName}\]")
  echo "# sectionExists(${sectionExists})"
  if [ "${sectionExists}" == "0" ]; then
    echo "# adding section [${network}d]"
    echo "
[${network}d]
" | tee -a ${lndConfFile}
  fi

  # get line number of [bitcoind] section
  sectionLine=$(cat ${lndConfFile} | grep -n "^\[${sectionName}\]" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${lndConfFile} | cut -d " " -f1)
  echo "# fileLines(${fileLines})"
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
" | tee -a ${lndConfFile}
  fi

  # SET/UPDATE zmqpubrawtx
  echo "# zmqpubrawtx insert/update"
  setting ${lndConfFile} ${insertLine} "${network}d\.zmqpubrawtx" "tcp\:\/\/127\.0\.0\.1\:${zmqprefix}333"

  # SET/UPDATE zmqpubrawblock
  setting ${lndConfFile} ${insertLine} "${network}d\.zmqpubrawblock" "tcp\:\/\/127\.0\.0\.1\:${zmqprefix}332"

  # SET/UPDATE rpcpass
  RPCPSW=$(cat /mnt/hdd/${network}/${network}.conf | grep "^rpcpassword=" | tail -1 | cut -d "=" -f2 | tail -n 1)
  if [ "${RPCPSW}" == "" ]; then
    RPCPSW=$(cat /mnt/hdd/${network}/${network}.conf | grep "^${network}d.rpcpassword=" | cut -d "=" -f2 | tail -n 1)
  fi
  if [ "${RPCPSW}" == "" ]; then
    echo 1>&2 "FAIL: 'rpcpassword' not found in /mnt/hdd/${network}/${network}.conf"
    exit 11
  fi
  setting ${lndConfFile} ${insertLine} "${network}d\.rpcpass" "${RPCPSW}"

  # SET/UPDATE rpcuser
  RPCUSER=$(cat /mnt/hdd/${network}/${network}.conf | grep "^rpcuser=" | cut -d "=" -f2 | tail -n 1)
  if [ "${RPCUSER}" == "" ]; then
    RPCUSER=$(cat /mnt/hdd/${network}/${network}.conf | grep "^${network}d.rpcuser=" | cut -d "=" -f2 | tail -n 1)
  fi
  if [ "${RPCUSER}" == "" ]; then
    echo 1>&2 "FAIL: 'rpcuser' not found in /mnt/hdd/${network}/${network}.conf"
    exit 12
  fi
  setting ${lndConfFile} ${insertLine} "${network}d\.rpcuser" "${RPCUSER}"

  # SET/UPDATE rpchost
  setting ${lndConfFile} ${insertLine} "${network}d\.rpchost" "127\.0\.0\.1\:${portprefix}8332"

  ##### APPLICATION OPTIONS SECTION #####

  sectionLine=$(cat ${lndConfFile} | grep -n "^\[Application Options\]" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)

  # make sure API ports are set to standard
  setting ${lndConfFile} ${insertLine} "rpclisten" "0\.0\.0\.0\:1${L2rpcportmod}009"
  setting ${lndConfFile} ${insertLine} "restlisten" "0\.0\.0\.0\:${portprefix}8080"

  # enforce LND port is set correctly (if set in raspiblitz.conf)
  if [ "${lndPort}" != "" ]; then
    setting ${lndConfFile} ${insertLine} "listen" "0\.0\.0\.0\:${portprefix}${lndPort}"
  else
    lndPort=9735
  fi

  # enforce PublicIP if (if not running Tor)
  if [ "${runBehindTor}" != "on" ]; then
    setting ${lndConfFile} ${insertLine} "externalip" "${publicIP}:${lndPort}"
  else
    # when running Tor a public ip can make startup problems - so remove
    sed -i '/^externalip=*/d' ${lndConfFile}
  fi

  ##### BOLT SECTION #####
  # https://github.com/lightningnetwork/lnd/blob/0aa0831619cb320dbb74883c37a80ccbdde7f320/sample-lnd.conf#L1205
  sectionName="bolt"
  echo "# [${sectionName}] config ..."
  # make sure lnd config has a [bolt] section
  sectionExists=$(cat ${lndConfFile} | grep -c "^\[${sectionName}\]")
  echo "# sectionExists(${sectionExists})"
  if [ "${sectionExists}" == "0" ]; then
    echo "# adding section [${sectionName}]"
    echo "
[${sectionName}]
" | tee -a ${lndConfFile}
  fi

  sectionLine=$(cat ${lndConfFile} | grep -n "^\[bolt\]" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)

  # make sure API ports are set to standard
  setting ${lndConfFile} ${insertLine} "db.bolt.auto-compact-min-age" "672h"
  setting ${lndConfFile} ${insertLine} "db.bolt.auto-compact" "true"

  ##### WORKERS SECTION #####
  # https://github.com/lightningnetwork/lnd/blob/5c36d96c9cbe8b27c29f9682dcbdab7928ae870f/sample-lnd.conf#L1131
  cores=$(nproc)
  if [ "${cores}" -lt 8 ]; then
    sectionName="workers"
    echo "# [${sectionName}] config ..."
    # make sure lnd config has a [bolt] section
    sectionExists=$(cat ${lndConfFile} | grep -c "^\[${sectionName}\]")
    echo "# sectionExists(${sectionExists})"
    if [ "${sectionExists}" == "0" ]; then
      echo "# adding section [${sectionName}]"
      echo "
[${sectionName}]
" | tee -a ${lndConfFile}
    fi

    sectionLine=$(cat ${lndConfFile} | grep -n "^\[workers\]" | cut -d ":" -f1)
    echo "# sectionLine(${sectionLine})"
    insertLine=$(expr $sectionLine + 1)

    # limit workers to the number of cores
    setting ${lndConfFile} ${insertLine} "workers.write" "${cores}"
    setting ${lndConfFile} ${insertLine} "workers.sig" "${cores}"
  fi

  ##### TOR SECTION #####

  if [ "${runBehindTor}" == "on" ]; then

    # make sure lnd config has a [tor] section
    echo "# [tor] config ..."
    sectionExists=$(cat ${lndConfFile} | grep -c "^\[[Tt]or\]")
    echo "# sectionExists(${sectionExists})"
    if [ "${sectionExists}" == "0" ]; then
      echo "# adding section [tor]"
      echo "
[tor]
" | tee -a ${lndConfFile}
    fi

    # get line number of [tor] section
    sectionLine=$(cat ${lndConfFile} | grep -n "^\[[Tt]or\]" | cut -d ":" -f1)
    echo "# sectionLine(${sectionLine})"
    insertLine=$(expr $sectionLine + 1)
    echo "# insertLine(${insertLine})"
    fileLines=$(wc -l ${lndConfFile} | cut -d " " -f1)
    echo "# fileLines(${fileLines})"
    if [ ${fileLines} -lt ${insertLine} ]; then
      echo "# adding new line for inserts"
      echo "
" | tee -a ${lndConfFile}
    fi

    setting ${lndConfFile} ${insertLine} "tor.control" "9051"
    setting ${lndConfFile} ${insertLine} "tor.socks" "9050"
    setting ${lndConfFile} ${insertLine} "tor.privatekeypath" "\/mnt\/hdd\/lnd\/${netprefix}v3_onion_private_key"
    setting ${lndConfFile} ${insertLine} "tor.v3" "true"
    setting ${lndConfFile} ${insertLine} "tor.active" "true"

    # take care of incompatible settings https://github.com/rootzoll/raspiblitz/issues/2787#issuecomment-991245694
    if [ $(cat ${lndConfFile} | grep -c "^tor.skip-proxy-for-clearnet-targets=true") -gt 0 ] ||
      [ $(cat ${lndConfFile} | grep -c "^tor.skip-proxy-for-clearnet-targets=1") -gt 0 ]; then
      setting ${lndConfFile} ${insertLine} "tor.streamisolation" "false"
    fi

    # deprecate Tor password (remove if in lnd.conf)
    sed -i '/^tor.password=*/d' ${lndConfFile}

  fi

  ##### RPCMIDDLEWARE SECTION #####
  sectionName="rpcmiddleware"
  echo "# [${sectionName}] config ..."

  # make sure lnd config has a [rpcmiddleware] section
  sectionExists=$(cat ${lndConfFile} | grep -c "^\[${sectionName}\]")
  echo "# sectionExists(${sectionExists})"
  if [ "${sectionExists}" == "0" ]; then
    echo "# adding section [${sectionName}]"
    echo "
[${sectionName}]
" | tee -a ${lndConfFile}
  fi

  # get line number of [rpcmiddleware] section
  sectionLine=$(cat ${lndConfFile} | grep -n "^\[${sectionName}\]" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${lndConfFile} | cut -d " " -f1)
  echo "# fileLines(${fileLines})"
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
" | tee -a ${lndConfFile}
  fi

  # remove erroneous entries
  sed -i '/^  \[rpcmiddleware\]/d' ${lndConfFile}
  sed -i '/^  \[\[Rr\]pcmiddleware\]/d' ${lndConfFile}

  # SET/UPDATE rpcmiddleware.enable
  setting ${lndConfFile} ${insertLine} "rpcmiddleware.enable" "true"

  ##### HEALTHCHECK SECTION #####
  sectionName="healthcheck"
  echo "# [${sectionName}] config ..."

  # make sure lnd config has a [healthcheck] section
  sectionExists=$(cat ${lndConfFile} | grep -c "^\[${sectionName}\]")
  echo "# sectionExists(${sectionExists})"
  if [ "${sectionExists}" == "0" ]; then
    echo "# adding section [${sectionName}]"
    echo "
[${sectionName}]
" | tee -a ${lndConfFile}
  fi

  # get line number of [healthcheck] section
  sectionLine=$(cat ${lndConfFile} | grep -n "^\[${sectionName}\]" | cut -d ":" -f1)
  echo "# sectionLine(${sectionLine})"
  insertLine=$(expr $sectionLine + 1)
  echo "# insertLine(${insertLine})"
  fileLines=$(wc -l ${lndConfFile} | cut -d " " -f1)
  echo "# fileLines(${fileLines})"
  if [ ${fileLines} -lt ${insertLine} ]; then
    echo "# adding new line for inserts"
    echo "
" | tee -a ${lndConfFile}
  fi

  # SET/UPDATE healthcheck values
  setting ${lndConfFile} ${insertLine} "healthcheck.chainbackend.attempts" "3"
  setting ${lndConfFile} ${insertLine} "healthcheck.chainbackend.timeout" "2m0s"
  setting ${lndConfFile} ${insertLine} "healthcheck.chainbackend.interval" "1m30s"

  echo "# OK PRESTART DONE"

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
  lndConfExists=$(sudo ls ${lndConfFile} 2>/dev/null | grep -c "${netprefix}lnd.conf")
  if [ ${lndConfExists} -gt 0 ]; then
    echo "config=1"
  else
    echo "config=0"
    echo "err='${netprefix}lnd.conf is missing in ${lndConfFile}'"
  fi
  # check lnd.conf exits (on SD card for admin)
  lndConfExists=$(sudo ls /home/admin/.lnd/${netprefix}lnd.conf 2>/dev/null | grep -c 'lnd.conf')
  if [ ${lndConfExists} -gt 0 ]; then
    echo "configCopy=1"
    # check if the same
    orgChecksum=$(sudo shasum -a 256 ${lndConfFile} 2>/dev/null | cut -d " " -f1)
    cpyChecksum=$(sudo shasum -a 256 /home/admin/.lnd/${netprefix}lnd.conf 2>/dev/null | cut -d " " -f1)
    if [ "${orgChecksum}" == "${cpyChecksum}" ]; then
      echo "configMismatch=0"
    else
      echo "configMismatch=1"
      echo "err='${netprefix}lnd.conf for user admin is old'"
    fi
  else
    echo "configCopy=0"
    echo "configMismatch=0"
    echo "err='$(netprefix)lnd.conf is missing for user admin'"
  fi

  # get network from config (BLOCKCHAIN)
  lndNetwork="bitcoin"
  echo "network='${lndNetwork}'"

  # check if network is same the raspiblitz config
  if [ "${network}" != "${lndNetwork}" ]; then
    echo "err='$(netprefix)lnd.conf: blockchain network in $(netprefix)lnd.conf (${lndNetwork}) is different from raspiblitz.conf (${network})'"
  fi

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
