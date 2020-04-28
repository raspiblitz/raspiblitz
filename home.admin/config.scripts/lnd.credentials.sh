#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "tool to check and update credentials (e.g. macaroons)"
  echo "lnd.credentials [check|update]"
  exit 1
fi

# load data from config
source /mnt/hdd/raspiblitz.conf

########################
# FUNCTIONS
########################

function copy_mac_set_perms() {
  local file_name=${1}  # the file name (e.g. admin.macaroon)
  local group_name=${2} # the unix group name (e.g. lndadmin)
  local n=${3:-bitcoin} # the network (e.g. bitcoin or litecoin) defaults to bitcoin
  local c=${4:-main} # the chain (e.g. main, test, sim, reg) defaults to main (for mainnet)

  sudo /bin/cp /mnt/hdd/lnd/data/chain/${n}/${c}net/${file_name} /mnt/hdd/app-data/lnd/chain/${n}/${c}net/${file_name}
  sudo /bin/chown --silent admin:${group_name} /mnt/hdd/app-data/lnd/chain/${n}/${c}net/${file_name}
  sudo /bin/chmod --silent 640 /mnt/hdd/app-data/lnd/chain/${n}/${c}net/${file_name}
}

########################
# CHECK
########################

if [ "$1" = "check" ]; then
  echo "CHECK"

  # TODO(frennkie)

fi

########################
# UPDATE
########################
if [ "$1" = "update" ]; then
  echo "UPDATE"

  sudo /bin/mkdir --mode 0755 --parents /mnt/hdd/app-data/lnd/chain/${network}/${chain}net/

  copy_mac_set_perms admin.macaroon lndadmin ${network} ${chain}
  copy_mac_set_perms invoice.macaroon lndinvoice ${network} ${chain}
  copy_mac_set_perms readonly.macaroon lndreadonly ${network} ${chain}

fi

