#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "tool to reset or sync credentials (e.g. macaroons)"
  echo "lnd.credentials.sh [reset|sync|check] [?tls|macaroons|keepold]"
  exit 1
fi

# load data from config
source /mnt/hdd/raspiblitz.conf

###########################
# FUNCTIONS
###########################

function copy_mac_set_perms() {
  local file_name=${1}  # the file name (e.g. admin.macaroon)
  local group_name=${2} # the unix group name (e.g. lndadmin)
  local n=${3:-bitcoin} # the network (e.g. bitcoin or litecoin) defaults to bitcoin
  local c=${4:-main}    # the chain (e.g. main, test, sim, reg) defaults to main (for mainnet)

  sudo /bin/cp /mnt/hdd/lnd/data/chain/"${n}"/"${c}"net/"${file_name}" /mnt/hdd/app-data/lnd/data/chain/"${n}"/"${c}"net/"${file_name}"
  sudo /bin/chown --silent admin:"${group_name}" /mnt/hdd/app-data/lnd/data/chain/"${n}"/"${c}"net/"${file_name}"
  sudo /bin/chmod --silent 640 /mnt/hdd/app-data/lnd/data/chain/"${n}"/"${c}"net/"${file_name}"
}

function check_macaroons() {
macaroons="admin.macaroon invoice.macaroon readonly.macaroon invoices.macaroon chainnotifier.macaroon signer.macaroon walletkit.macaroon router.macaroon"
missing=0
for macaroon in $macaroons
do
  local file_name=${macaroon}
  local n=${1:-bitcoin} # the network (e.g. bitcoin or litecoin) defaults to bitcoin
  local c=${2:-main}    # the chain (e.g. main, test, sim, reg) defaults to main (for mainnet)
  if [ ! -f /mnt/hdd/app-data/lnd/data/chain/"${n}"/"${c}"net/"${macaroon}" ]; then
    missing=$(($missing + 1))
    echo "# ${macaroon} is missing ($missing)"
  else
    echo "# ${macaroon} is present"
  fi
done
}

###########################
# RESET Macaroons and TLS
###########################
if [ "$1" = "reset" ]; then

  clear
  echo "### lnd.credentials.sh reset"

  # default reset both
  resetTLS=1
  resetMacaroons=1

  # optional second paramter to just reset one on them
  if [ "$2" == "tls" ]; then
    echo "# just resetting TLS"
    resetTLS=1
    resetMacaroons=0
  fi
  if [ "$2" == "macaroons" ]; then
    echo "# just resetting macaroons"
    resetTLS=0
    resetMacaroons=1
    keepOldMacaroons=0
  fi
  if [ "$2" == "keepold" ]; then
    echo "# add the missing default macaroons without de-authenticating the old ones"
    resetTLS=0
    resetMacaroons=1
    keepOldMacaroons=1
  fi

  if [ ${resetMacaroons} -eq 1 ]; then
    echo "## Resetting Macaroons"
    echo "# all your macaroons get deleted and recreated"
    cd || exit
    sudo find /mnt/hdd/app-data/lnd/data/chain/"${network}"/"${chain}"net/ -iname '*.macaroon' -delete
    sudo find /home/bitcoin/.lnd/data/chain/"${network}"/"${chain}"net/ -iname '*.macaroon' -delete
    if [ "${keepOldMacaroons}" != "1" ]; then
      sudo rm /home/bitcoin/.lnd/data/chain/"${network}"/"${chain}"net/macaroons.db
    fi
  fi

  if [ ${resetTLS} -eq 1 ]; then
    echo "## Resetting TLS"
    echo "# tls cert gets deleted and recreated"
    cd || exit
    sudo /home/admin/config.scripts/lnd.tlscert.sh refresh
  fi

  # unlock wallet after restart
  echo "# restarting LND ... wait 10 secs"
  sudo systemctl start lnd
  sleep 10

  # unlock wallet after restart
  sudo /home/admin/config.scripts/lnd.unlock.sh
  sleep 10

  if [ ${resetMacaroons} -eq 1 ]; then
    echo "# copy new macaroons to central app-data directory and ensure unix ownerships and permissions"
    copy_mac_set_perms admin.macaroon lndadmin "${network}" "${chain}"
    copy_mac_set_perms invoice.macaroon lndinvoice "${network}" "${chain}"
    copy_mac_set_perms readonly.macaroon lndreadonly "${network}" "${chain}"
    echo "# OK DONE"
  fi

  /home/admin/config.scripts/lnd.credentials.sh sync

###########################
# SYNC
###########################
elif [ "$1" = "sync" ]; then

  echo "###### SYNCING MACAROONS, RPC Password AND TLS Certificate ######"

  echo "# make sure LND app-data directories exist"
  sudo /bin/mkdir --mode 0755 --parents /mnt/hdd/app-data/lnd/data/chain/"${network}"/"${chain}"net/

  echo `# make sure all user groups exit for default macaroons`
  sudo /usr/sbin/groupadd --force --gid 9700 lndadmin
  sudo /usr/sbin/groupadd --force --gid 9701 lndinvoice
  sudo /usr/sbin/groupadd --force --gid 9702 lndreadonly
  sudo /usr/sbin/groupadd --force --gid 9703 lndinvoices
  sudo /usr/sbin/groupadd --force --gid 9704 lndchainnotifier
  sudo /usr/sbin/groupadd --force --gid 9705 lndsigner
  sudo /usr/sbin/groupadd --force --gid 9706 lndwalletkit
  sudo /usr/sbin/groupadd --force --gid 9707 lndrouter

  echo "# copy macaroons to central app-data directory and ensure unix ownerships and permissions"
  copy_mac_set_perms admin.macaroon lndadmin "${network}" "${chain}"
  copy_mac_set_perms invoice.macaroon lndinvoice "${network}" "${chain}"
  copy_mac_set_perms readonly.macaroon lndreadonly "${network}" "${chain}"
  copy_mac_set_perms invoices.macaroon lndinvoices "${network}" "${chain}"
  copy_mac_set_perms chainnotifier.macaroon lndchainnotifier "${network}" "${chain}"
  copy_mac_set_perms signer.macaroon lndsigner "${network}" "${chain}"
  copy_mac_set_perms walletkit.macaroon lndwalletkit "${network}" "${chain}"
  copy_mac_set_perms router.macaroon lndrouter "${network}" "${chain}"

  echo "# make sure admin has a symlink at ~/.lnd to /mnt/hdd/app-data/lnd/"
  if ! [[ -L "/home/admin/.lnd" ]]; then
    sudo rm -rf "/home/admin/.lnd"                # not a symlink.. delete it silently
    ln -s /mnt/hdd/app-data/lnd/ /home/admin/.lnd # and create symlink
  fi

  echo "# make sure LND conf is readable and symlinked"
  sudo chmod 644 "/mnt/hdd/lnd/lnd.conf"
  sudo chown bitcoin:bitcoin "/mnt/hdd/lnd/lnd.conf"
  if ! [[ -L "/mnt/hdd/app-data/lnd/lnd.conf" ]]; then
    sudo rm -rf "/mnt/hdd/app-data/lnd/lnd.conf"                # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/lnd/lnd.conf" "/mnt/hdd/app-data/lnd/lnd.conf"  # and create symlink
  fi

  echo "# make sure TLS certificate is readable and symlinked"
  sudo chmod 644 "/mnt/hdd/lnd/tls.cert"
  sudo chown bitcoin:bitcoin "/mnt/hdd/lnd/tls.cert"
  if ! [[ -L "/mnt/hdd/app-data/lnd/tls.cert" ]]; then
    sudo rm -rf "/mnt/hdd/app-data/lnd/tls.cert"                    # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/lnd/tls.cert" "/mnt/hdd/app-data/lnd/tls.cert"  # and create symlink
  fi
  
  if [ "${LNBits}" = "on" ]; then
    echo "# fix the macaroon for LNbits" 
    # https://github.com/rootzoll/raspiblitz/pull/1156#issuecomment-623293240
    sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh write-macaroons
  fi
  
###########################
# Check Macaroons and fix missing
###########################
elif [ "$1" = "check" ]; then
  check_macaroons ${network} ${chain}
  if [ $missing -gt 0 ]; then
    /home/admin/config.scrips/lnd.creds.sh reset keepold
  fi

###########################
# UNKNOWN
###########################
else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
