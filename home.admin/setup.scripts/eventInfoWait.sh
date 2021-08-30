#!/bin/bash
# this is an dialog that handles all UI events during setup that require a "info & wait" with no interaction

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/_version.info 2>/dev/null
source /home/admin/raspiblitz.info 2>/dev/null

# 1st PARAMETER: eventID
# fixed ID string for a certain event
eventID=$1
if [ "${eventID}" == "" ]; then
    echo "err='missing eventID'"
    exit 1
fi

# 2nd PARAMETER (optional): dynamic content that can be used in two ways
# 1) contentWords[] --> if eventID is known & well defined between backend & frontend, then use the single words of this string as dynamic content for static text info
# 2) contentString  --> if eventID is new and not well defined yet, then just show a generic info and use the complete string as info message 
# just see examples of this two use cases below
contentWords=($2)
contentString=$2

# 3rd PARAMETER (optional): Place of display - could be "lcd" or "ssh" (defalt)
mode=$3
if [ "${mode}" == "" ]; then
    mode="ssh"
fi
if [ "${mode}" != "lcd" ] && [ "${mode}" != "ssh" ]; then
    echo "error='unknown 3rd parameter value'"
    exit 1
fi

# default backtitle for dialog
backtitle="RaspiBlitz ${codeVersion} / ${eventID} / ${localip}"

################################################
# 1) WELL DEFINED EVENTS
################################################

if [ "${eventID}" == "starting" ] || [ "${eventID}" == "system-init" ] || [ "${eventID}" == "ready" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Starting RaspiBlitz
Please wait ...
" 6 24

elif [ "${eventID}" == "waitsync" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Preparing Blockchain Sync
Please wait ...
" 6 30

elif [ "${eventID}" == "reboot" ] && [ "${contentString}" == "finalsetup" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Final Setup Reboot
" 5 23

elif [ "${eventID}" == "reboot" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Shutting down for reboot.
" 5 30

elif [ "${eventID}" == "reboot-init" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Rebooting for Setup (${contentString})
" 5 30

elif [ "${eventID}" == "error" ] && [ "${mode}" == "lcd" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
SYSTEM RAN INTO AN ERROR:
${contentString}
------------------------------------
Use terminal command to login:
ssh admin@${localip}
" 10 41

elif [ "${eventID}" == "error" ] && [ "${mode}" == "ssh" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
SYSTEM RAN INTO AN ERROR:
${contentString}

Please report to the Raspiblitz GitHub
CTRL+C to exit to terminal for commands:
cat raspiblitz.log --> see error log
off --> shutdown system
" 11 50

elif [ "${eventID}" == "provision" ] || [ "${eventID}" == "recovering" ]; then

    if [ "${mode}" == "ssh" ]; then

        # provision info when logged in
        dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Upgrade/Recover/Provision
---> ${contentString}

Run 'tail -f ./raspiblitz.log' in
new terminal to follow install logs.
" 9 40

    else

        # provision on LCD, etc
        dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Upgrade/Recover/Provision
---> ${contentString}
Please keep running until done.
" 7 40

    fi

elif [ "${eventID}" == "repair" ] && [ "${mode}" == "lcd" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Repair-Mode - Login for Details:
ssh admin@${localip}
Use your Password A
" 7 41

elif [ "${eventID}" == "copysource" ] && [ "${mode}" == "lcd" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Repair-Mode - Providing Blockchain
ssh admin@${localip}
Use your Password A
" 7 41

elif [ "${eventID}" == "copystation" ] && [ "${mode}" == "lcd" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Copy-Station Mode
ssh admin@${localip}
Use your Password A
" 7 41


elif [ "${eventID}" == "walletlocked" ] && [ "${mode}" == "lcd" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Lightning Wallet Locked
ssh admin@${localip}
Use your Password A
" 7 41

elif [ "${eventID}" == "copytarget" ] && [ "${mode}" == "lcd" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Receiving Blockchain over LAN
ssh admin@${localip}
Use your Password A
" 7 41

elif [ "${eventID}" == "inconsistentsystem" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
PLEASE START WITH A FRESH SD CARD IMAGE
---------------------------------------
Cut power & remove sd card and then
flash a fresh RaspiBlitz image on it.
" 8 45

elif [ "${eventID}" == "waitsetup" ] && [ "${mode}" == "lcd" ]; then

    if [ "${setupPhase}" == "setup" ] || [ "${setupPhase}" == "update" ] || [ "${setupPhase}" == "recovery" ] || [ "${setupPhase}" == "migration" ]; then

        # custom backtitle for this dialog
        backtitle="RaspiBlitz ${codeVersion} / ${setupPhase}"

        # display if HDD conatains blockhain or not
        if [ "${hddBlocksBitcoin}" == "1" ] || [ "${hddBlocksLitecoin}" == "1" ]; then
            backtitle="${backtitle} / (pre-synced)"
        fi

        # custom welcomeline for this dialog
        welcomeline="Your RaspiBlitz is ready for Setup"
        if [ "${setupPhase}" == "update" ]; then
            welcomeline="RaspiBlitz is ready for Update"
        fi
        if [ "${setupPhase}" == "recovery" ]; then
            welcomeline="RaspiBlitz is ready for Recovery"
        fi
        if [ "${setupPhase}" == "migration" ]; then
            welcomeline="Ready for migration to RaspiBlitz"
        fi

        # show default login help info
        dialog --backtitle "${backtitle}" --cr-wrap --infobox "
${welcomeline}
------------------------------------
Use terminal command to login:
ssh admin@${localip}
password: raspiblitz
" 9 41

    else

        # custom backtitle for this dialog
        backtitle="RaspiBlitz ${codeVersion} / ${setupPhase}"

        # on all other cases (add info message)
        dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Login for Maintenance:
---> ${contentString}
ssh admin@${localip}
Use password: raspiblitz
" 8 41
    fi

elif [ "${eventID}" == "waitfinal" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Setup-Done - Login for Details:
ssh admin@${localip}
Use your Password A
" 7 41

elif [ "${eventID}" == "shutdown" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Shutting down - please wait.
" 5 35

elif [ "${eventID}" == "noDHCP" ]; then

    # this event is mostly for LCD/HDMI display
    # because if device gets no local IP
    # SSH & WEBUI would not have connected yet
    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Waiting for local IP address ...
If this takes too long please check
your connection to internet router.
" 7 41

elif [ "${eventID}" == "waitsetup" ] && [ "${mode}" == "ssh" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Please wait ...
" 5 22

elif [ "${eventID}" == "waitprovision" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Preparing Provision
Please wait ...
" 6 24

elif [ "${eventID}" = "noIP-LAN" ] || [ "${eventID}" = "noIP-WIFI" ]; then

    # this event is mostly for LCD/HDMI display
    # because if device gets no local IP
    # SSH & WEBUI would not have connected yet
    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Waiting for Network ...
Not able to get local IP.
LAN cable connected? WIFI lost?
" 7 41

elif [ "${eventID}" = "noInternet" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Waiting for Internet ...
Local Network seems OK but no Internet.
Is your router still online?
" 7 43

elif [ "${eventID}" == "inspect-hdd" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Checking HDD/SSD ...
Please wait.
" 6 26

elif [ "${eventID}" == "noHDD" ]; then

    # contentWords[0] --> size string (for example '1TB')
    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
Waiting for HDD/SSD ...
Please connect a ${contentWords[0]}
HDD or SSD to the device.
" 7 35

elif [ "${eventID}" == "errorHDD" ]; then

    # contentString --> detail error message
    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
PROBLEM: FAILED HDD/SSD
Detailed Error Message:
${contentString}
" 7 35

elif [ "${eventID}" == "errorNetwork" ]; then

    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
PROBLEM: LOST NETWORK
Shutting down ... 
Manual restart needed.
" 7 35

elif [ "${eventID}" == "sdtoosmall" ]; then

    # contentWords[0] --> size string (for example '16GB')
    dialog --backtitle "${backtitle}" --cr-wrap --infobox "
PROBLEM: SD CARD IS TOO SMALL 
Minimum of ${contentWords[0]} needed
Cut power & create fresh sd card
" 7 40

################################################
# 2) GENERIC EVENT
# may get better defined in the future
################################################

else

    # a generic info box for not further defined events
    dialog --title "${eventid}" --backtitle "${backtitle}" --cr-wrap --infobox "\n${contentString}" 7 50

fi