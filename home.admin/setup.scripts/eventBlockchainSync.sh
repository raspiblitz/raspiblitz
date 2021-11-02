#!/bin/bash
# this is an dialog that handles all UI events during setup that require a "info & wait" with no interaction

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/_version.info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# 1st PARAMETER: ssh|lcd
PRAMETER_LCD=0
if [ "$1" == "lcd" ]; then
    PRAMETER_LCD=1
fi

# 2nd PARAMETER (optional): -loop-until-synced
PARAMETER_LOOPUNTILSYNCED=0
if [ "$2" == "-loop-until-synced" ]; then
    PARAMETER_LOOPUNTILSYNCED=1
fi

while [ 1 ]
do

    # get data from cache
    source <(/home/admin/_cache.sh get \
      btc_default_ready \
      btc_default_sync_percentage \
      btc_default_peers \
      system_count_start_blockchain \
    )

    # display blockchain sync
    height=6
    width=45
    actionString="Please wait - this can take some time"

    # formatting BLOCKCHAIN SYNC PROGRESS
    if [ "${btc_default_sync_percentage}" == "" ]; then
        if [ ${system_count_start_blockchain} -lt 2 ]; then
            syncProgress="waiting"
        else
            syncProgress="${system_count_start_blockchain} restarts"
        fi
    elif [ ${#btc_default_sync_percentage} -lt 6 ]; then
        syncProgress=" ${btc_default_sync_percentage} % ${btc_default_peers} peers"
    else
        syncProgress="${btc_default_sync_percentage} % ${btc_default_peers} peers"
    fi

    # get data from cache
    source <(/home/admin/_cache.sh get \
      lightning \
      ln_default_ready \
      ln_default_sync_progress \
      system_count_start_lightning \
    )

    # formatting LIGHTNING SCAN PROGRESS  
    if [ "${lightning}" != ""  ] && [ "${ln_default_sync_progress}" == "" ]; then
        # in case of LND RPC is not ready yet
        if [ "${ln_default_ready}" != "" ]; then
            scanProgress="prepare sync"
        # in case LND restarting >2  
        elif [ "${system_count_start_lightning}" != "" ] && [ ${system_count_start_lightning} -gt 2 ]; then
            scanProgress="${system_count_start_lightning} restarts"
        # unkown cases
        else
            scanProgress="waiting"
        fi
    elif [ ${#ln_default_sync_progress} -lt 6 ]; then
        scanProgress=" ${ln_default_sync_progress} %"
    else
        scanProgress="${ln_default_sync_progress} %"
    fi

    # setting info string
    infoStr=" Blockchain Progress : ${syncProgress}\n"
    
    if [ "${lightning}" == "lnd" ] || [ "${lightning}" == "cl" ]; then
       infoStr="${infoStr} Lightning Progress  : ${scanProgress}\n ${actionString}"
    else
       # if lightning is deactivated (leave line clear)
       infoStr="${infoStr} \n ${actionString}"
    fi
    
    # get data from cache
    source <(/home/admin/_cache.sh get \
      internet_localip \
      codeVersion \
      system_temp_celsius \
      system_temp_fahrenheit \
      btc_default_sync_initialblockdownload \
      btc_default_blocks_behind \
      hostname \
      network \
    )

    # set admin string
    if [ ${PRAMETER_LCD} -eq 1 ]; then
        adminStr="ssh admin@${internet_localip} -> Password A"
    else
        adminStr="Use CTRL+c to EXIT to Terminal"
    fi

    # display info to user
    time=$(date '+%H:%M:%S')
    dialog --title " Node is Syncing (${time}) " --backtitle "RaspiBlitz ${codeVersion} ${system_temp_celsius}°C / ${system_temp_fahrenheit}°F / ${hostname}" --infobox "${infoStr}\n ${adminStr}" ${height} ${width}

    # break loop if set by parameter
    if [ ${PARAMETER_LOOPUNTILSYNCED} -eq 0 ]; then
        exit 0
    fi

    # otherwise break if chain is synced up
    if [ "${btc_default_sync_initialblockdownload}" == "0" ]; then
    
        # also check after initial blockdown load if synced up again
        if [ ${btc_default_blocks_behind} -lt 2 ]; then
            exit 0
        fi

    fi
done