#!/bin/bash
# this is an dialog that handles all UI events during setup that require a "info & wait" with no interaction

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/_version.info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# 1st PARAMETER: ssh|lcd
lcd=0
if [ "$1" == "lcd" ]; then
    lcd=1
fi

# 2nd PARAMETER (optional): -loop-until-synced
loopUntilSynced=0
if [ "$2" == "loop" ]; then
    loopUntilSynced=1
fi

loop=1
while [ ${loop} -eq 1 ]
do

    # get fresh data
    source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)

    # display blockchain sync
    height=6
    width=45
    actionString="Please wait - this can take some time"

    # formatting BLOCKCHAIN SYNC PROGRESS
    if [ "${syncProgress}" == "" ]; then
        if [ ${startcountBlockchain} -lt 2 ]; then
            syncProgress="waiting"
        else
            syncProgress="${startcountBlockchain} restarts"
        fi
    elif [ ${#syncProgress} -lt 6 ]; then
        syncProgress=" ${syncProgress} % ${blockchainPeers} peers"
    else
        syncProgress="${syncProgress} % ${blockchainPeers} peers"
    fi

    # formatting LIGHTNING SCAN PROGRESS  
    if [ "${lightning}" != ""  ] && [ "${scanProgress}" == "" ]; then
        # in case of LND RPC is not ready yet
        if [ ${scanTimestamp} -eq -2 ]; then
            scanProgress="prepare sync"
        # in case LND restarting >2  
        elif [ ${startcountLightning} -gt 2 ]; then
            scanProgress="${startcountLightning} restarts"
        # unkown cases
        else
            scanProgress="waiting"
        fi
    elif [ ${#scanProgress} -lt 6 ]; then
        scanProgress=" ${scanProgress} %"
    else
        scanProgress="${scanProgress} %"
    fi

    # setting info string
    infoStr=" Blockchain Progress : ${syncProgress}\n"
    
    if [ "${lightning}" == "lnd" ]; then
       # if LND is active 
       infoStr="${infoStr} Lightning Progress  : ${scanProgress}\n ${actionString}"
    elif [ "${lightning}" == "cln" ]; then
       # if CLN is active 
       # TODO: show a scan progress of C-Lightning
        infoStr="${infoStr} Lightning Progress  : TODO\n ${actionString}"
    else
       # if lightning is deactivated (leave line clear)
       infoStr="${infoStr} \n ${actionString}"
    fi
    
    # set admin string
    if [ ${lcd} -eq 1 ]; then
        adminStr="ssh admin@${localip} -> Password A"
    else
        adminStr="Use CTRL+c to EXIT to Terminal"
    fi

    # display info to user
    time=$(date '+%H:%M:%S')
    dialog --title " Node is Syncing (${time}) " --backtitle "RaspiBlitz ${codeVersion} ${tempCelsius}°C / ${hostname} / ${network} / ${chain}" --infobox "${infoStr}\n ${adminStr}" ${height} ${width}

    # determine to loop or not
    loop=0
    if [ ${loopUntilSynced} -eq 1 ] && [ "${syncedToChain}" == "0" ]; then
        # loop until synced to chain
        loop=1
        sleep 3
    fi
done