#!/bin/bash
echo ""

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# Basic Options
OPTIONS=(TORRENT "Redownload Prepared Torrent (DEFAULT)" \
         COPY "Copy from another Computer (SKILLED)" \
         RESYNC "Resync thru Peer2Peer Network (TRUSTLESS)" \
         BACKUP "Run Backup LND data first (optional)"
)

CHOICE=$(dialog --backtitle "RaspiBlitz - Repair Script" --clear --title "Repair Blockchain Data" --menu "Choose a repair/recovery option:" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
if [ "${CHOICE}" = "TORRENT" ]; then
    echo "Starting TORRENT ..."
    sudo sed -i "s/^state=.*/state=retorrent/g" /home/admin/raspiblitz.info
    /home/admin/50torrentHDD.sh
    sudo sed -i "s/^state=.*/state=na/g" /home/admin/raspiblitz.info

elif [ "${CHOICE}" = "COPY" ]; then
    echo "Starting COPY ..."
    sudo sed -i "s/^state=.*/state=recopy/g" /home/admin/raspiblitz.info
    /home/admin/50copyHDD.sh
    sudo sed -i "s/^state=.*/state=na/g" /home/admin/raspiblitz.info

elif [ "${CHOICE}" = "RESYNC" ]; then
    echo "Starting RESYNC ..."
    /home/admin/50syncHDD.sh
    dialog --pause "OK. System will reboot to activate changes." 8 58 8
    clear
    echo "rebooting .. (please wait)"
    sudo shutdown -r now

elif [ "${CHOICE}" = "REINDEX" ]; then
    echo "Starting REINDEX ..."
    sudo /home/admin/config.scripts/network.reindex.sh

elif [ "${CHOICE}" = "BACKUP" ]; then
    sudo /home/admin/config.scripts/lnd.rescue.sh backup
    echo "PRESS ENTER to continue."
    read key

else
    echo "CANCEL"
fi