#!/bin/bash

if [ $# -eq 0 ]; then
 echo "script to unlock LND wallet"
 echo "lnd.unlock.sh [passwordC]"
 exit 1
fi

# 1. parameter
passwordC="$1"

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
if [ ${#passwordC} -eq 0 ]; then
    manualEntry=1
    passwordC=$(whiptail --passwordbox "\nEnter Password C to unlock wallet:\n" 9 52 "" --title " LND Wallet " --backtitle "RaspiBlitz" 3>&1 1>&2 2>&3)
fi

loopCount=0
while :
  do
    
    # TRY TO UNLOCK ...

    loopCount=$(($loopCount +1))
    echo "# calling: lncli unlock"
    result=$(echo "${passwordC}" | sudo -u bitcoin lncli unlock --recovery_window=5000 --stdin 3>&1 1>&2 2>&3)
    sleep 4


    if [ $(echo "${result} | grep -c 'successfully unlocked'") -gt 0 ]; then

        # SUCCESS UNLOCK

        echo "# OK LND wallet unlocked"
        exit(0)

    elif [ $(echo "${result} | grep -c 'invalid passphrase'") -gt 0 ]; then

        # WRONG PASSWORD

        echo "# wrong password"
        if [ ${manualEntry} -eq 1 ]; then
            passwordC=$(whiptail --passwordbox "\nEnter Password C again:\n" 9 52 "" --title " Password was Wrong " --backtitle "RaspiBlitz - LND Wallet" 3>&1 1>&2 2>&3)
        else
            print("error='wrong password'")
            exit(1)
        fi

    else

        # UNKOWN RESULT

        echo "# unkown error"
        if [ ${manualEntry} -eq 1 ]; then
            clear
            echo "#################################"
            echo "# LND ERROR on unlocking wallet"
            echo "#################################"
            echo
            echo "${result}"
            echo
            echo "PRES ENTER to retry .."
        else
            # maybe lncli is waiting to get ready (wait and loop)
            if [ ${loopCount} -gt 10 ]; then
                echo "error='failed to unlock'"
                exit(1)
            fi
            sleep 2
        fi
    fi

  done