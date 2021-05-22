#!/bin/bash

if [ "$1" == "format" ]; then 

    whiptail --title " FORMATTING DATA DRVE " --yes-button "DELETE DATA" --no-button "STOP SETUP" --yesno "Your data drive will now be formatted. This will delete all data on your connected HDD/SSD. Make sure that there is no important data or old funds on that data drive.

Are you sure to format the HDD/SSD and DELETE ALL DATA on it?
      " 12 65

    if [ "$?" == "0" ]; then
        # 0 --> delete data
        exit 0
    else
        # 1 --> cancel
        exit 1
    fi
fi

if [ "$1" == "keepblockchain" ]; then

    blockchainName=$2
    if [ "${blockchainName}" == "" ]; then
        blockchainName="BITCOIN"
    fi

    whiptail --title " BLOCKCHAIN DATA FOUND " --yes-button "KEEP BLOCKCHAIN" --no-button "NO" --yesno "We found on the data drive ${blockchainName} blockchain data.

This can reduce your setup/sync time but if you didnt validated that blockchain yourself there is a level of trust involved.

Do you want to use that blockchain & its data and DELETE ALL OTHER DATA?
      " 10 65

    if [ "$?" == "0" ]; then
        # 0 --> use blockchain & delete all other data
        exit 0
    else
        # 1 --> cancel
        exit 1
    fi

fi

echo "err='unkown parameter'" 
exit 1