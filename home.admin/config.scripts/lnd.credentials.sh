#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "tool to reset or sync credentials (e.g. macaroons)"
  echo "lnd.credentials.sh [reset|sync]"
  exit 1
fi

# interactive choose type of action
if [ "$1" = "" ] || [ $# -eq 0 ]; then
    OPTIONS=()
    OPTIONS+=(RESET "Recreate Macaroons + TLS")
    OPTIONS+=(SYNC "Sync with RaspiBlitz Apps/Users")
    OPTIONS+=(EXPORT "Get Macaroons and TLS.cert")
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz" \
                --title "Manage LND credentials" \
                --menu "Choose action" \
                11 50 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        RESET)
          sudo /home/admin/config.scripts/lnd.credentials.sh reset
          echo "Press ENTER to return to main menu."
          read key
          exit 0
          ;;
        SYNC)
          sudo /home/admin/config.scripts/lnd.credentials.sh sync
          echo "Press ENTER to return to main menu."
          read key
          exit 0
          ;;
        EXPORT)
          sudo /home/admin/config.scripts/lnd.export.sh
          exit 0
          ;;
    esac
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

###########################
# RESET Macaroons and TLS
###########################
if [ "$1" = "reset" ]; then
  clear
  echo "###### RESET MACAROONS AND TLS.cert ######"
  echo ""
  echo "All your macaroons and the tls.cert get deleted and recreated."
  echo "Use this to invalidate former EXPORTS for example if you loose a device."
  echo ""
  cd || exit
  echo "- deleting old macaroons"
  sudo find /mnt/hdd/app-data/lnd/data/chain/"${network}"/"${chain}"net/ -iname '*.macaroon' -delete
  sudo find /home/bitcoin/.lnd/data/chain/"${network}"/"${chain}"net/ -iname '*.macaroon' -delete
  sudo rm /home/bitcoin/.lnd/data/chain/"${network}"/"${chain}"net/macaroons.db
  echo "- resetting TLS cert"
  sudo /home/admin/config.scripts/lnd.newtlscert.sh
  echo "- restarting LND ... wait 10 secs"
  sudo systemctl start lnd
  sleep 10
  sudo -u bitcoin lncli --chain="${network}" --network="${chain}"net unlock
  echo "- creating new macaroons ... wait 10 secs"
  sleep 10
  echo "- copy new macaroons to central app-data directory and ensure unix ownerships and permissions"
  copy_mac_set_perms admin.macaroon lndadmin "${network}" "${chain}"
  copy_mac_set_perms invoice.macaroon lndinvoice "${network}" "${chain}"
  copy_mac_set_perms readonly.macaroon lndreadonly "${network}" "${chain}"
  echo "OK DONE"

###########################
# SYNC
###########################
elif [ "$1" = "sync" ]; then
  echo "###### SYNCING MACAROONS, RPC Password AND TLS Certificate ######"

  echo "# make sure LND app-data directories exist"
  sudo /bin/mkdir --mode 0755 --parents /mnt/hdd/app-data/lnd/data/chain/"${network}"/"${chain}"net/

  echo "# copy macaroons to central app-data directory and ensure unix ownerships and permissions"
  copy_mac_set_perms admin.macaroon lndadmin "${network}" "${chain}"
  copy_mac_set_perms invoice.macaroon lndinvoice "${network}" "${chain}"
  copy_mac_set_perms readonly.macaroon lndreadonly "${network}" "${chain}"

  echo "# make sure admin has a symlink at ~/.lnd to /mnt/hdd/app-data/lnd/"
  if ! [[ -L "/home/admin/.lnd" ]]; then
    sudo rm -rf "/home/admin/.lnd"                # not a symlink.. delete it silently
    ln -s /mnt/hdd/app-data/lnd/ /home/admin/.lnd # and create symlink
  fi

  echo "# make sure network (bitcoin/litecoin) RPC password is set correctly in lnd.conf"
  source <(sudo cat /mnt/hdd/"${network}"/"${network}".conf 2>/dev/null | grep "rpcpass" | sed 's/^[a-z]*\./lnd/g')
  if [ "${#rpcpassword}" -gt 0 ]; then
    sudo sed -i 's/^"${network}"d.rpcpass=.*/"${network}"d.rpcpass="${rpcpassword}"/g' /mnt/hdd/lnd/lnd.conf 2>/dev/null
  else
    echo "# WARN: could not get value 'rpcpass' from network config (e.g. bitcoin.conf)"
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

###########################
# UNKNOWN
###########################
else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
