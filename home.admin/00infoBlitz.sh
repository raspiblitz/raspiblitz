#!/bin/bash

source /home/admin/raspiblitz.info

source <(/home/admin/_cache.sh get \
  state \
  setupPhase \
  network \
  chain \
  lightning \
  codeVersion \
  codeRelease \
  codeCommit \
  hostname \
  undervoltageReports \
  hdd_used_info \
  internet_localip \
  internet_public_ip_clean \
  internet_rx \
  internet_tx \
  system_ram_available_mb \
  system_ram_mb \
  system_ups_status \
  system_ups_battery \
  system_cpu_load \
  system_up_text \
  system_temp_celsius \
  system_temp_fahrenheit \
  runBehindTor \
  ups \
  ElectRS \
  BTCRPCexplorer \
  joinmarket \
  blitzapi \
)

# PARAMETER 1: forcing view on a given network
PARAMETER_CHAIN=$2
if [ "${PARAMETER_CHAIN}" == "mainnet" ]; then
  chain="main"
fi
if [ "${PARAMETER_CHAIN}" == "testnet" ]; then
  chain="test"
fi
if [ "${PARAMETER_CHAIN}" == "signet" ]; then
  chain="sig"
fi

# PARAMETER 2: forcing view on a lightning implementation
PARAMETER_LIGHTNING=$1
if [ "${PARAMETER_LIGHTNING}" == "lnd" ]; then
  lightning="lnd"
fi
if [ "${PARAMETER_LIGHTNING}" == "cl" ]; then
  lightning="cl"
fi
if [ "${PARAMETER_LIGHTNING}" == "none" ]; then
  lightning=""
fi

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_amber='\033[0;33m'
color_yellow='\033[1;93m'
color_gray='\033[0;37m'

# generate netprefix
netprefix=${chain:0:1}
if [ "${netprefix}" == "m" ]; then
  netprefix=""
fi

## get UPS info
upsInfo=""
if [ "${system_ups_status}" = "ONLINE" ]; then
  upsInfo="${color_gray}${system_ups_battery}"
fi
if [ "${system_ups_status}" = "ONBATT" ]; then
  upsInfo="${color_red}${system_ups_battery}"
fi
if [ "${system_ups_status}" = "SHUTTING DOWN" ]; then
  upsInfo="${color_red}DOWN"
fi

# check hostname
if [ ${#hostname} -eq 0 ]; then hostname="raspiblitz"; fi

# for oldnodes
if [ ${#chain} -eq 0 ]; then
  network="bitcoin"
  chain="main"
fi

# ram info string
ram=$(printf "%sM / %sM" "${system_ram_available_mb}" "${system_ram_mb}")
if [ "${system_ram_available_mb}" != "" ] && [ ${system_ram_available_mb} -lt 50 ]; then
  color_ram="${color_red}\e[7m"
else
  color_ram=${color_green}
fi

# Tor info string
torInfo=""
if [ "${runBehindTor}" = "on" ]; then
  torInfo="+ Tor"
fi

#######################
# BITCOIN INFO

# get block data - use meta on cache to call dynamic variable name
source <(/home/admin/_cache.sh meta btc_${chain}net_blocks_headers)
btc_blocks_headers="${value}"
source <(/home/admin/_cache.sh meta btc_${chain}net_blocks_verified)
btc_blocks_verified="${value}"
source <(/home/admin/_cache.sh meta btc_${chain}net_blocks_behind)
btc_blocks_behind="${value}"
source <(/home/admin/_cache.sh meta btc_${chain}net_sync_percentage)
if [ "${value}" != "" ]; then
  sync_percentage="${value}%"
fi

# construct blockinfo string
if [ "${btc_blocks_behind}" == "" ]; then 
  sync="WAIT"
  sync_color="${color_yellow}"
elif [ ${btc_blocks_behind} -lt 2 ]; then 
  sync="OK"
  sync_color="${color_green}"
else
  sync=""
  sync_color="${color_red}"
fi
blockInfo="Blocks ${btc_blocks_verified}/${btc_blocks_headers} ${color_gray}Sync ${sync_color}${sync}"
if [ "${btc_blocks_headers}" == "" ]; then
  blockInfo="${color_red}Not Started | Not Ready Yet | No Data${color_gray}"
fi

# get address data - use meta on cache to call dynamic variable name
source <(/home/admin/_cache.sh meta btc_${chain}net_version)
networkVersion="${value} "
source <(/home/admin/_cache.sh meta btc_${chain}net_peers)
btc_peers=${value}
if [ "${btc_peers}" == "" ]; then
  networkConnectionsInfo=""
elif [ ${btc_peers} -gt 0 ]; then
  networkConnectionsInfo="${color_green}${btc_peers} ${color_gray}peers"
else
  networkConnectionsInfo="${color_red}${btc_peers} ${color_gray}peers"
fi

#######################
# LIGHTNING INFO

# default values
ln_alias=${hostname}
ln_baseInfo="-"
ln_channelInfo="\n"
ln_external="\n"
ln_feeReport=""
ln_peersInfo=""
ln_version=""
ln_publicColor="${color_green}"

if [ "${lightning}" != "" ]; then

  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_version)
  ln_version="${value}"

  # get alias
  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_alias)
  if [ "${value}" != "" ]; then
    ln_alias="${value}"
  fi

  # consider tor address green for public
  # when not Tor use yellow because not sure if public
  if [ "${runBehindTor}" != "on" ]; then
    ln_publicColor="${color_yellow}"
  fi

  # get the public address/URI
  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_address)
  ln_external="${value}"

  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_peers)
  if [ "${value}" != "" ]; then
    ln_peersInfo="${color_green}${value} ${color_gray}peers"
  fi

  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_ready)
  ln_ready="${value}"
  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_sync_chain)
  ln_sync="${value}"
  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_locked)
  ln_locked="${value}"
  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_recovery_mode)
  ln_recovery_mode="${value}"
  source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_recovery_done)
  ln_recovery_done="${value}"

  # lightning is still starting
  if [ "${ln_ready}" != "1" ]; then

    ln_baseInfo="\n               ${color_red}Not Started | Not Ready Yet | No Data"
    ln_peersInfo=""

  # lightning is still syncing
  elif [ "${ln_locked}" == "1" ]; then

    ln_baseInfo="${color_amber}Wallet Locked"
    ln_peersInfo=""

  # lightning is still syncing
  elif [ "${ln_recovery_mode}" == "1" ] && [ "${ln_recovery_done}" == "0" ]; then

    ln_baseInfo="${color_amber}Rescanning transactions"
    ln_peersInfo=""

  # lightning is still syncing
  elif [ "${ln_sync}" != "1" ]; then

    source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_sync_progress)
    ln_syncprogress="${value}"
    ln_baseInfo="${color_amber}Scanning blocks: ${ln_syncprogress}"
    ln_peersInfo=""

  # OK lightning is ready - get more details
  else

    # create fee report
    if [ "${lightning}" == "lnd" ]; then
      source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_fees_daily)
      ln_dailyfees="${value}"
      source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_fees_weekly)
      ln_weeklyfees="${value}"
      source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_fees_month)
      ln_monthlyfees="${value}"
      ln_feeReport="Fee Report (D-W-M): ${color_green}${ln_dailyfees}-${ln_weeklyfees}-${ln_monthlyfees} ${color_gray}${netprefix}sat"
    else
      source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_fees_total)
      ln_totalfees="${value}"
      ln_feeReport="Fee Report: ${color_green}${ln_totalfees} ${color_gray}${netprefix}msat"
    fi

    # on-chain wallet info
    ln_pendingonchain=""
    source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_wallet_onchain_pending)
    ln_onchain_pending="${value}"
    if [ "${ln_onchain_pending}" != "" ] && [ ${ln_onchain_pending} -gt 0 ]; then ln_pendingonchain=" (+${ln_onchain_pending})"; fi
    source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_wallet_onchain_balance)
    ln_walletbalance=$(printf "%'d" "${value}")
    ln_baseInfo="${color_gray}Wallet ${ln_walletbalance} ${netprefix}sat ${ln_pendingonchain}"

    # channel pending info
    ln_channelbalance_pending=""
    source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_wallet_channels_pending)
    ln_channels_pending="${value}"
    if [ "${ln_channels_pending}" != "" ] && [ ${ln_channels_pending} -gt 0 ]; then ln_channelbalance_pending=" (+${ln_channels_pending})"; fi

    # get channel infos
    source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_wallet_channels_balance)
    ln_channels_balance=$(printf "%'d" "${value}")
    source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_channels_active)
    ln_channels_online="${value}"
    source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_channels_total)
    ln_channels_total="${value}"

    # construct channel info string
    ln_channelInfo="${ln_channels_online}/${ln_channels_total} Channels ${ln_channels_balance} ${netprefix}sat${ln_channelbalance_pending}"
  fi

fi


  lastLine="\
${color_yellow}
${color_yellow}${ln_publicColor}${ln_external}${color_gray}"

if [ "${joinmarket}" = "on" ];then
  # show JoinMarket stats in place of the LND URI only if the Yield Generator is running
  if [ "$(sudo -u joinmarket pgrep -f "yg-privacyenhanced.py" 2>/dev/null | wc -l)" -gt 2 ] || \
     [ "$(curl -ksX GET https://127.0.0.1:28183/api/v1/session | jq  .maker_running 2>/dev/null)" = true ]; then

    trap 'rm -f "$JMstats"' EXIT
    JMstats=$(mktemp -p /dev/shm)
    sudo -u joinmarket /home/joinmarket/info.stats.sh > $JMstats
    JMstatsL1=$(sed -n 1p < "$JMstats")
    JMstatsL2=$(sed -n 2p < "$JMstats")
    JMstatsL3=$(sed -n 3p < "$JMstats")
    JMstatsL4=$(sed -n 4p < "$JMstats")
    lastLine="\
${color_gray}
${color_gray}     ╦╔╦╗      ${color_gray}$JMstatsL1
${color_gray}     ║║║║      ${color_gray}$JMstatsL2
${color_gray}    ╚╝╩ ╩      ${color_gray}$JMstatsL3
${color_gray}  ◎=◎=◎=◎=◎    ${color_gray}$JMstatsL4"
  fi
fi

if [ "${lightning}" == "cl" ]; then
  LNline="CLN ${color_green}${ln_version} ${ln_baseInfo}"
elif [ "${lightning}"  == "lnd" ]; then
  LNline="LND ${color_green}${ln_version} ${ln_baseInfo}"
fi

LNinfo=" + Lightning Network"
if [ "${lightning}" == "" ] || [ "${lightning}" == "none" ]; then
  LNinfo=""
fi

webuiinfo=""
source <(/home/admin/_cache.sh meta ln_${lightning}_${chain}net_recovery_done)
if [ "${blitzapi}" == "on" ]; then
 webuiinfo="Web Admin --> http://${internet_localip}"
fi

datetime=$(date +"%d %b %T %z")
datetime="${datetime} up ${system_up_text}"

if [ "${vm}" == "1" ]; then
    temp_info="VM detected"
else
    temp_info="temp ${system_temp_celsius}°C ${system_temp_fahrenheit}°F"
fi

stty sane
sleep 1
clear

printf "
${color_yellow}
${color_yellow}
${color_yellow}
${color_yellow}               ${color_amber}%s ${color_green} ${ln_alias} ${upsInfo}
${color_yellow}               ${color_gray}${network^} Fullnode${LNinfo} ${torInfo}
${color_yellow}        ,/     ${color_yellow}%s
${color_yellow}      ,'/      ${color_gray}%s
${color_yellow}    ,' /       ${color_gray}%s ${temp_info}
${color_yellow}  ,'  /_____   ${color_gray}Free Mem ${color_ram}${ram} ${color_gray} HDD ${color_hdd}%s${color_gray}
${color_yellow},'_____    ,'  ${color_gray}SSH admin@${internet_localip}${color_gray} d${internet_rx} u${internet_tx}
${color_yellow}      /  ,'    ${color_gray}${webuiinfo} 
${color_yellow}     / ,'      ${color_gray}${network} ${color_green}${networkVersion}${color_gray}${chain}net ${networkConnectionsInfo}
${color_yellow}    /,'        ${color_gray}${blockInfo} %s
${color_yellow}   /'          ${color_gray}
${color_yellow}               ${color_gray}${LNline}
${color_yellow}               ${color_gray}${ln_channelInfo} ${ln_peersInfo}
${color_yellow}               ${color_gray}${ln_feeReport}
$lastLine
" \
"RaspiBlitz ${codeVersion}-${codeRelease}" \
"-------------------------------------------" \
"Refreshed: ${datetime}" \
"CPU load${system_cpu_load##up*,  }" \
"${hdd_used_info}" "${sync_percentage}"

if [ ${#undervoltageReports} -gt 0 ] && [ "${undervoltageReports}" != "0" ]; then
  echo "${undervoltageReports} undervoltage reports - run 'Hardware Test' in menu"
elif [ ${#ups} -gt 1 ] && [ "${upsStatus}" = "n/a" ]; then
  echo "UPS service activated but not running"
else

  # checking status of apps and display if in sync or problems
  appInfoLine=""

  # Electrum Server - electrs
  fileFlagExists=$(sudo ls /mnt/hdd/app-storage/electrs/initial-sync.done 2>/dev/null | grep -c 'initial-sync.done')
  if [ "${ElectRS}" == "on" ] && [ $fileFlagExists -eq 0 ]; then
    error=""
    source <(/home/admin/config.scripts/bonus.electrs.sh status-sync 2>/dev/null)
    if [ ${#infoSync} -gt 0 ]; then
      appInfoLine="Electrum: ${infoSync}"
    fi
  fi

  # Electrum Server - fulcrum
  fileFlagExists=$(sudo ls /mnt/hdd/app-storage/fulcrum/initial-sync.done 2>/dev/null | grep -c 'initial-sync.done')
  if [ "${fulcrum}" == "on" ] && [ $fileFlagExists -eq 0 ]; then
    error=""
    source <(/home/admin/config.scripts/bonus.fulcrum.sh status-sync 2>/dev/null)
    if [ ${#infoSync} -gt 0 ]; then
      appInfoLine="Fulcrum: ${infoSync}"
    fi
  fi

  # Transaction Index
  source <(/home/admin/config.scripts/network.txindex.sh status)
  if [ "${txindex}" == "1" ] && [ "${isIndexed}" != "1" ]; then
      appInfoLine="Transaction Index: ${indexInfo}"
  fi

  if [ ${#appInfoLine} -gt 0 ]; then
    echo "${appInfoLine}"
  fi

fi

