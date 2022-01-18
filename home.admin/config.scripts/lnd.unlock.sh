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
    action="unlock"
    passwordC=""
    CHAIN=$2
fi

# dont if state is on reboot or shutdown
source <(/home/admin/_cache.sh get state)
if [ "${state}" == "reboot" ] || [ "${state}" == "shutdown" ]; then
  echo "# ignore unlock - because system is in shutdown/reboot state"
  sleep 1
  exit 0
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd ${chain}net)

# check if wallet is already unlocked
# echo "# checking LND wallet ... (can take some time)"
lndError=$(sudo -u bitcoin lncli --chain=${network} --network=${chain}net getinfo 2>&1)
walletLocked=$(echo "${lndError}" | grep -c "Wallet is encrypted")
if [ "${walletLocked}" == "0" ]; then
    # test for new error message
    walletLocked=$(echo "${lndError}" | grep -c "wallet locked")
fi
macaroonsMissing=$(echo "${lndError}" | grep -c "unable to read macaroon")

# if action sis just status
if [ "${action}" == "status" ]; then
    echo "locked=${walletLocked}"
    echo "missingMacaroons=${macaroonsMissing}"
    exit 0
fi

# if already unlocked all is done
if [ ${walletLocked} -eq 0 ] && [ ${macaroonsMissing} -eq 0 ]; then
    # echo "# OK LND wallet was already unlocked"
    exit 0
fi

# check if LND is below 0.10 (has no STDIN password option)
fallback=0
source <(/home/admin/config.scripts/lnd.update.sh info)
if [ ${lndInstalledVersionMajor} -eq 0 ] && [ ${lndInstalledVersionMain} -lt 10 ]; then
    if [ ${#passwordC} -gt 0 ]; then
        echo "error='lnd version too old'"
        exit 1
    else
      fallback=1
    fi
fi

# if no password check if stored for auto-unlock
if [ ${#passwordC} -eq 0 ]; then
    autoUnlockExists=$(sudo ls /root/lnd.autounlock.pwd 2>/dev/null | grep -c "lnd.autounlock.pwd")
    if [ ${autoUnlockExists} -eq 1 ]; then
        echo "# using auto-unlock"
        passwordC=$(sudo cat /root/lnd.autounlock.pwd)
    fi
fi

# if still no password get from user
manualEntry=0
if [ ${#passwordC} -eq 0 ] && [ ${fallback} -eq 0 ]; then
    echo "# manual input"
    manualEntry=1
    passwordC=$(whiptail --passwordbox "\nEnter Password C to unlock wallet:\n" 9 52 "" --title " LND Wallet " --backtitle "RaspiBlitz" 3>&1 1>&2 2>&3)
fi

loopCount=0
while [ ${fallback} -eq 0 ]
  do
    
    # TRY TO UNLOCK ...

    loopCount=$(($loopCount +1))
    echo "# calling: lncli unlock"
    recoveryOption=""
    if [ "${fundRecovery}" == "1" ]; then
        recoveryOption="--recovery_window=5000 "
        echo "# running unlock with ${recoveryOption}"
    fi
    result=$(echo "$passwordC" | $lncli_alias unlock ${recoveryOption}--stdin 2>&1)
    wasUnlocked=$(echo "${result}" | grep -c 'successfully unlocked')
    wrongPassword=$(echo "${result}" | grep -c 'invalid passphrase')
    if [ ${wasUnlocked} -gt 0 ]; then

        # SUCCESS UNLOCK
        echo "# OK LND wallet unlocked"

        # if autoUnlock set in config (but this manual input was needed)
        # there seems to be no stored password - make sure to store password c now
        if [ "${autoUnlock}" == "on" ]; then
            echo "# storing password C for future Auto-Unlock"
            /home/admin/config.scripts/lnd.autounlock.sh on "${passwordC}"
            sleep 1
        fi

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
    $lncli_alias unlock --recovery_window=1000

    # test unlock
    walletLocked=$($lncli_alias getinfo 2>&1 | grep -c unlock)
    if [ ${walletLocked} -eq 0 ]; then
        echo "# --> OK LND wallet unlocked"
    else
        echo "# --> Was not able to unlock wallet ... try again or use CTRL-C to exit"
    fi

done
