#!/bin/bash

# FIRST PARAMETER can be the name of the blockchain data that is available in the HDD/SS
# if set the user will be given to option to DELETE ALL DATA but KEEP BLOCKCHAIN
blockchainName=$1

keepBlockchain=0
if [ ${blockchainName} != "" ]; then

    whiptail --title " BLOCKCHAIN DATA FOUND " --yes-button "USE BLOCKCHAIN" --no-button "DELETE" --yesno "We found ${blockchainName} blockchain data on your HDD/SSD.

Using existing blockchain data can reduce the setup/sync time. But if you didnt validated the blockchain yourself there is a level of trust involved.

Do you want to use that blockchain data and run ${blockchainName}? 
      " 14 68

    if [ "$?" == "0" ]; then
        # 0 --> use blockchain & delete all other data
        keepBlockchain=1
    fi
fi

# normally when the the HDD will get formatted and the user will get asked about that
# if before the user decided to keep the blockchain instead if formatting just "ALL OTHER DATA" wil get deleted

if [ "${keepBlockchain}" == "1" ]; then

    # deleting all data around blockchain security question
    whiptail --title " DELETING ALL OTHER DATA " --yes-button "DELETE DATA" --no-button "STOP SETUP" --yesno "OK we will keep the blockchain data - but all other data on your HDD/SSD will get deleted on setup. Make sure that there is no important data or old funds on that data drive.

Are you sure to DELETE ALL OTHER DATA on the HDD/SSD?
      " 11 65

    if [ "$?" == "0" ]; then
        # 0 --> keep blockchain + delete all other data
        exit 2
    else
        # 1 --> cancel / stop
        exit 0
    fi

else

    # normal formatting data drive security question
    whiptail --title " FORMATTING DATA DRVE " --yes-button "DELETE DATA" --no-button "STOP SETUP" --yesno "Your data drive will now get formatted. This will delete all data on your connected HDD/SSD. Make sure that there is no important data or old funds on that data drive.

Are you sure to format the HDD/SSD and DELETE ALL DATA on it?
      " 11 65

    if [ "$?" == "0" ]; then
        # 0 --> format drive
        exit 1
    else
        # 1 --> cancel / stop
        exit 0
    fi
fi