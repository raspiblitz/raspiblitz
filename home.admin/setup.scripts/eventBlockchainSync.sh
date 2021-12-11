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
if [ "${btc_default_ready}" == "0" ] || [ "${btc_default_peers}" == "" ]; then
    if [ ${system_count_start_blockchain} -gt 1 ]; then
        syncProgress="${system_count_start_blockchain} restarts"
    else
        syncProgress="waiting for start"
    fi
elif [ "${btc_default_peers}" == "0" ]; then
    syncProgress="waiting for peers"
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
    hostname \
    network \
)

# set admin string
if [ ${PRAMETER_LCD} -eq 1 ]; then
    adminStr="ssh admin@${internet_localip} -> Password A"
else
    adminStr="open 2nd SSH session -> terminal access"
fi

# display info to user
time=$(date '+%H:%M:%S')
dialog --title " Node is Syncing (${time}) " --backtitle "RaspiBlitz ${codeVersion} / ${system_temp_celsius}°C / ${system_temp_fahrenheit}°F / ${hostname}" --infobox "${infoStr}\n ${adminStr}" ${height} ${width}
