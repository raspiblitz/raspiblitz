#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"
source $SETUPFILE


#################################
# SELECT BLOCKCHAIN --> SKIPPED (litecoin deactivated, reactivate selection when other bitcoin implementations)
# when not already set by setupfile
if [ "${network}" == "" ]; then
    network="bitcoin"
fi
if [ "${network}" == "" ]; then

    OPTIONS=()
    OPTIONS+=(BITCOIN "Setup BITCOIN Blockchain (BitcoinCore)")
    OPTIONS+=(LITECOIN "Setup LITECOIN Blockchain (experimental)")
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz ${codeVersion} - Setup" \
                --title "⚡ Blockchain ⚡" \
                --menu "\nChoose which Blockchain to run: \n " \
                11 64 5 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        BITCOIN)
            # bitcoin core
            network="bitcoin"
            ;;
        LITECOIN)
            # litecoin
            network="litecoin"
            # can only work with LND
            lightning="lnd"
            ;;
        *)
            clear
            echo "User Cancel"
            exit 1
    esac
fi


#################################
# SELECT LIGHTNING
# only possible when network is bitcoin

if [ "${network}" == "bitcoin" ]; then

     # choose lightning client
    OPTIONS=()
    OPTIONS+=(LND "LND - Lightning Network Daemon (DEFAULT)")
    OPTIONS+=(CL "C-lightning by Blockstream (NEW)")
    OPTIONS+=(NONE "Run without Lightning")
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz ${codeVersion} - Setup" \
                --title "⚡ Lightning ⚡" \
                --menu "\nChoose your Lightning Client to run on RaspiBlitz: \n " \
                12 64 6 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        LND)
            lightning="lnd"
            ;;
        CL)
            lightning="cl"
            ;;
        NONE)
            lightning="none"
            ;;
        *)
            clear
            echo "User Cancel"
            exit 1
    esac
fi

# write results to setup sate
echo "lightning=${lightning}" >> $SETUPFILE
echo "network=${network}" >> $SETUPFILE
echo "chain=main" >> $SETUPFILE

exit 0