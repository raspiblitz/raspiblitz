#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

whiptail --title "70initLND - WARNING" --yes-button "Retry" --no-button "Show Logs" --yesno "Service ${network}d is not running." 8 50
echo "choice($?)"
exit 1

# CHECK 1: BITCOIND is running correctly
# - systemd says its running
echo "*** Checking ${network} ***"
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
if [ ${bitcoinRunning} -eq 0 ]; then
  bitcoinRunning=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo  | grep -c verificationprogress)
fi
if [ ${bitcoinRunning} -eq 0 ]; then

fi
echo "OK - ${network}d is running"
echo ""

# CHECK 2: LND is running correctly
# - systemd says its running
# - TLS.cert was created

# CHECK 3: Does LND wallet already exists
# - yes: Jump to next point or ask to delete
# sudo systemctl stop lnd
# sudo rm /mnt/hdd/lnd/data/chain/bitcoin/mainnet/wallet.db
# sudo systemctl start lnd

# UI: Ask if user wants NEW wallet or RECOVER a wallet
OPTIONS=(NEW "Setup a brand new Lightning Node" \
         RECOVER "Recover funds from Seed Word List" \
         RESTORE "Restore LND data from rescue file")
CHOICE=$(dialog --backtitle "RaspiBlitz - LND Setup" --clear --title "LND Data & Wallet" --menu "Choose how to setup your Node data:" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)
echo "choice($CHOICE)"

#source lnd/bin/activate
#python /home/admin/config.scripts/lnd.initwallet.py new 12345678