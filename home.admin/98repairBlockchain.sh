#!/bin/bash
echo ""

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# Basic Options
OPTIONS=(COPY "Copy from laptop/node over LAN (SKILLED)" \
         RESYNC "Resync thru Peer2Peer Network (TRUSTLESS)" \
         BACKUP "Run Backup LND data first (optional)"
)

CHOICE=$(dialog --backtitle "RaspiBlitz - Repair Script" --clear --title "Repair Blockchain Data" --menu "Choose a repair/recovery option:" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
if [ "${CHOICE}" = "COPY" ]; then
    echo "Starting COPY ..."
    sudo sed -i "s/^state=.*/state=recopy/g" /home/admin/raspiblitz.info
    /home/admin/config.scripts/blitz.copychain.sh target
    sudo sed -i "s/^state=.*/state=na/g" /home/admin/raspiblitz.info

elif [ "${CHOICE}" = "RESYNC" ]; then
    echo "Starting RESYNC ..."
    #TODO #FIXME
    # /home/admin/50syncHDD.sh
    dialog --pause "OK. System will reboot to activate changes." 8 58 8
    clear
    echo "rebooting .. (please wait)"
    sudo /home/admin/config.scripts/blitz.shutdown.sh reboot

elif [ "${CHOICE}" = "REINDEX" ]; then
    echo "Starting REINDEX ..."
    sudo /home/admin/config.scripts/network.reindex.sh

elif [ "${CHOICE}" = "BACKUP" ]; then
    /home/admin/config.scripts/lnd.compact.sh interactive
    sudo /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
    echo "PRESS ENTER to continue."
    read key

else
    echo "CANCEL"
fi