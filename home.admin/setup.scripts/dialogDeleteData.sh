#!/bin/bash

if [ "$1" == "format" ]; then 

    whiptail --title " FORMATTING DATA DRVE " --yes-button "DELETE DATA" --no-button "CANCEL" --yesno "For fresh setup your data drive needs to be formatted, but there is old data on your HDD/SSD that could contain funds.

Are you really sure that you want delete that old data?
      " 10 65

    if [ "$?" == "0" ]; then
        # 0 --> delete data
        exit 0
    else
        # 1 --> cancel
        exit 1
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