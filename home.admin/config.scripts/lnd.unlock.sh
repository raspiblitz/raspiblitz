#!/bin/bash

if [ "$1" == "-h" ] || [ "$1" == "help" ]; then
 echo "script to unlock LND wallet"
 echo "lnd.unlock.sh status"
 echo "lnd.unlock.sh unlock [?passwordC]"
 echo "lnd.unlock.sh chain-unlock [mainnet|testnet|signet]"
 exit 1
fi

# load raspiblitz info & conf
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# 1. parameter (default is unlock)
action="$1"

# 2. parameter (optional password)
passwordC="$2"

# chain-unlock --> unlock with re-arranged parameters
CHAIN="${chain}net"
if [ "${action}" == "chain-unlock" ]; then
    CHAIN=$2
    if [ "${CHAIN}" == "mainnet" ]; then
        chain="main"
        passwordC="$3"
    elif [ "${CHAIN}" == "testnet" ]; then
        chain="test"
        passwordC=""
    elif [ "${CHAIN}" == "signet" ]; then 
        chain="sig"
        passwordC=""
    else
        echo "# unkown chain parameter: ${CHAIN}"
        sleep 1
        exit 1
    fi
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd ${chain}net)

# dont if state is on reboot or shutdown
source <(/home/admin/_cache.sh get state)
if [ "${state}" == "reboot" ] || [ "${state}" == "shutdown" ]; then
  echo "# ignore unlock - because system is in shutdown/reboot state"
  sleep 1
  exit 0
fi

lndStatus=$(sudo systemctl show ${netprefix}lnd --property=StatusText)
echo "# ${netprefix}lnd: ${lndStatus}"
walletUnlocked=$( echo "${lndStatus}"| grep -c "Wallet unlocked")
if [ ${walletUnlocked} -eq 0 ]; then
    walletLocked=1
else
    walletLocked=0
fi

# if action is just status
if [ "${action}" == "status" ]; then
    echo "locked=${walletLocked}"
    exit 0
fi

# if already unlocked all is done
if [ ${walletLocked} -eq 0 ]; then
    echo "# OK LND wallet was already unlocked"
    exit 0
fi

# if still no password get from user
manualEntry=0
if [ ${#passwordC} -eq 0 ]; then
    echo "# manual input"
    manualEntry=1
    passwordC=$(whiptail --passwordbox "\nEnter Password C to unlock wallet:\n" 9 52 "" --title " LND Wallet " --backtitle "RaspiBlitz" 3>&1 1>&2 2>&3)
fi

loopCount=0
fallback=0
while [ ${fallback} -eq 0 ]
  do
    
    # TRY TO UNLOCK ...

    loopCount=$(($loopCount +1))
    echo "# calling: lncli unlock"


    # check if lnd is in recovery mode
    source <(sudo /home/admin/config.scripts/lnd.backup.sh mainnet recoverymode status)
    recoveryOption=""
    if [ "${recoverymode}" == "1" ]; then
        recoveryOption="--recovery_window=5000 "
        echo "# running unlock with ${recoveryOption}"
    fi
    result=$(echo "$passwordC" | $lncli_alias unlock ${recoveryOption}--stdin 2>&1)
    wasUnlocked=$(echo "${result}" | grep -c 'successfully unlocked')
    wrongPassword=$(echo "${result}" | grep -c 'invalid passphrase')
    if [ ${wasUnlocked} -gt 0 ]; then

        # SUCCESS UNLOCK
        echo "# OK LND wallet unlocked"
        exit 0

    elif [ ${wrongPassword} -gt 0 ]; then

        # WRONG PASSWORD

        echo "# wrong password"
        if [ ${manualEntry} -eq 1 ]; then
            passwordC=$(whiptail --passwordbox "\nEnter Password C again:\n" 9 52 "" --title " Password was Wrong " --backtitle "RaspiBlitz - LND Wallet" 3>&1 1>&2 2>&3)
        else
            echo "error='wrong password'"
            exit 1
        fi

    else

        # UNKNOWN RESULT

        # check if wallet was unlocked anyway
        walletLocked=$($lncli_alias getinfo 2>&1 | grep -c unlock)
        if [ "${walletUnlocked}" = "0" ]; then
            echo "# OK LND wallet unlocked"
            exit 0
        fi

        echo "# unknown error"
        if [ ${manualEntry} -eq 1 ]; then
            whiptail --title " LND ERROR " --msgbox "${result}" --ok-button "Try CLI" 8 60
            fallback=1
        else
            # maybe lncli is waiting to get ready (wait and loop)
            if [ ${loopCount} -gt 10 ]; then
                echo "error='failed to unlock'"
                exit 1
            fi
            sleep 2
        fi
    fi

  done

# FALLBACK LND CLI UNLOCK
walletLocked=1
while [ ${walletLocked} -gt 0 ]
do
    # do CLI unlock
    echo
    echo "############################"
    echo "Calling: ${netprefix}lncli unlock"
    echo "Please re-enter Password C:"
    $lncli_alias unlock --recovery_window=5000

    # test unlock
    walletLocked=$($lncli_alias getinfo 2>&1 | grep -c unlock)
    if [ ${walletLocked} -eq 0 ]; then
        echo "# --> OK LND wallet unlocked"
    else
        echo "# --> Was not able to unlock wallet ... try again or use CTRL-C to exit"
    fi

done
