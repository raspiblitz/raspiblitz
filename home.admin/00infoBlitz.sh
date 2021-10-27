#!/bin/bash

# 00infoBlitz.sh <cl|lnd> <testnet|mainnet|signet>
source <(/home/admin/config.scripts/network.aliases.sh getvars $1 $2)

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_amber='\033[0;33m'
color_yellow='\033[1;93m'
color_gray='\033[0;37m'

## get basic info
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# get values from cache
source <(/home/admin/config.scripts/blitz.cache.sh get codeVersion undervoltageReports)

## get HDD/SSD info
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
hdd="${hddUsedInfo}"

## get internet info
source <(sudo /home/admin/config.scripts/internet.sh status)
cleanip=$(echo "${publicIP}" | tr -d '[]')

## get UPS info
source <(/home/admin/config.scripts/blitz.ups.sh status)
upsInfo=""
if [ "${upsStatus}" = "ONLINE" ]; then
  upsInfo="${color_gray}${upsBattery}"
fi
if [ "${upsStatus}" = "ONBATT" ]; then
  upsInfo="${color_red}${upsBattery}"
fi
if [ "${upsStatus}" = "SHUTTING DOWN" ]; then
  upsInfo="${color_red}DOWN"
fi

# check hostname
if [ ${#hostname} -eq 0 ]; then hostname="raspiblitz"; fi

# for oldnodes
if [ ${#network} -eq 0 ]; then
  network="bitcoin"
  litecoinActive=$(sudo ls /mnt/hdd/litecoin/litecoin.conf 2>/dev/null | grep -c 'litecoin.conf')
  if [ ${litecoinActive} -eq 1 ]; then
    network="litecoin"
  else
    network=$(sudo cat /home/admin/.network 2>/dev/null)
  fi
  if [ ${#network} -eq 0 ]; then
    network="bitcoin"
  fi
fi

# for oldnodes
if [ ${#chain} -eq 0 ]; then
  chain="test"
  isMainChain=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep "#testnet=1" -c)
  if [ ${isMainChain} -gt 0 ];then
    chain="main"
  fi
fi

# set datadir
lnd_dir="/home/bitcoin/.lnd"
lnd_macaroon_dir="/home/bitcoin/.lnd/data/chain/${network}/${chain}net"

# get uptime & load
load=$(w | head -n 1 | cut -d 'v' -f2 | cut -d ':' -f2)

# get CPU temp - no measurement in a VM
cpu=0
if [ -d "/sys/class/thermal/thermal_zone0/" ]; then
  cpu=$(cat /sys/class/thermal/thermal_zone0/temp)
fi
if [ $cpu = 0 ];then
  tempC=""
  tempF=""
else
  tempC=$((cpu/1000))
  tempF=$(((tempC * 18 + 325) / 10))
fi
# get memory
ram_avail=$(free -m | grep Mem | awk '{ print $7 }')
ram=$(printf "%sM / %sM" "${ram_avail}" "$(free -m | grep Mem | awk '{ print $2 }')")

if [ ${ram_avail} -lt 50 ]; then
  color_ram="${color_red}\e[7m"
else
  color_ram=${color_green}
fi

# Bitcoin blockchain
btc_path=$(command -v ${network}-cli)
blockInfo="-"
if [ -n "${btc_path}" ]; then
  btc_title=$network
  blockchaininfo="$($bitcoincli_alias getblockchaininfo 2>/dev/null)"
  if [ ${#blockchaininfo} -gt 0 ]; then
    btc_title="${btc_title} (${chain}net)"

    # get sync status
    headers="$(echo "${blockchaininfo}" | jq -r '.headers')"
    block_verified="$(echo "${blockchaininfo}" | jq -r '.blocks')"
    block_diff=$(expr ${headers} - ${block_verified})
    blockInfo="${block_verified}/${headers}"

    progress="$(echo "${blockchaininfo}" | jq -r '.verificationprogress')"
    sync_percentage=$(echo $progress | awk '{printf( "%.2f%%", 100 * $1)}')

    if [ ${block_diff} -eq 0 ]; then    # fully synced
      sync="OK"
      sync_color="${color_green}"
      sync_behind=" "
    elif [ ${block_diff} -eq 1 ]; then   # fully synced
      sync="OK"
      sync_color="${color_green}"
      sync_behind="-1 block"
    elif [ ${block_diff} -le 10 ]; then   # <= 2 blocks behind
      sync=""
      sync_color="${color_red}"
      sync_behind="-${block_diff} blocks"
    else
      sync=""
      sync_color="${color_red}"
      sync_behind="${sync_percentage}"
    fi

    # get last known block
    if [ ! -z "${last_block}" ]; then
      btc_line2="${btc_line2} ${color_gray}(block ${last_block})"
    fi

    # get mem pool transactions
    mempool="$($bitcoincli_alias getmempoolinfo 2>/dev/null | jq -r '.size')"

  else
    btc_line2="${color_red}NOT RUNNING\t\t"
  fi
fi

# get IP address & port
networkInfo=$($bitcoincli_alias getnetworkinfo 2>/dev/null)
local_ip="${localip}" # from internet.sh
public_ip="${cleanip}"
public_port="$(echo ${networkInfo} | jq -r '.localaddresses [0] .port')"
if [ "${public_port}" = "null" ]; then
  if [ "${chain}" = "test" ]; then
    public_port="18333"
  else
    public_port="8333"
  fi
fi

# check if RTL web interface is installed
webinterfaceInfo=""
runningRTL=$(systemctl status ${netprefix}${typeprefix}RTL.service 2>/dev/null | grep -c active)
if [ ${runningRTL} -eq 1 ]; then
  if [ "${lightning}" == "cl" ]; then
    RTLHTTP=${portprefix}7000
  elif [ "${lightning}" == "lnd" ];then
    RTLHTTP=${portprefix}3000
  fi
  webinterfaceInfo="Web admin --> ${color_green}http://${local_ip}:${RTLHTTP}"
fi

# CHAIN NETWORK
public_addr_pre="Public "
public_addr="??"
torInfo=""
# Version
networkVersion=$($bitcoincli_alias -version 2>/dev/null | cut -d ' ' -f6)
# TOR or IP
networkConnections=$(echo ${networkInfo} | jq -r '.connections')
networkConnectionsInfo="${color_green}${networkConnections} ${color_gray}connections"

if [ "${runBehindTor}" = "on" ]; then

  # TOR address
  onionAddress=$(echo ${networkInfo} | jq -r '.localaddresses [0] .address')
  networkConnectionsInfo="${color_green}${networkConnections} ${color_gray}peers"
  public_addr="${onionAddress}:${public_port}"
  public=""
  public_color="${color_green}"
  torInfo="+ Tor"

else

  # IP address
  networkConnectionsInfo="${color_green}${networkConnections} ${color_gray}connections"
  public_addr="${publicIP}:${public_port}"
  public_check=$(nc -z -w6 ${cleanip} ${public_port} 2>/dev/null; echo $?)
  if [ $public_check = "0" ] || [ "${ipv6}" == "on" ] ; then
    public=""
    # only set yellow/normal because netcat can only say that the port is open - not that it points to this device for sure
    public_color="${color_amber}"
  else
    public=""
    public_color="${color_red}"
  fi

  # DynDomain
  if [ ${#dynDomain} -gt 0 ]; then

    #check if dynamic domain resolves to correct IP
    ipOfDynDNS=$(getent hosts ${dynDomain} | awk '{ print $1 }')
    if [ "${ipOfDynDNS}:${public_port}" != "${public_addr}" ]; then
      public_color="${color_red}"
    else
      public_color="${color_amber}"
    fi

    # replace IP display with dynDN
    public_addr_pre="DynDN "
    public_addr="${dynDomain}"
  fi

  if [ ${#public_addr} -gt 25 ]; then
    # if a IPv6 address dont show peers to save space
    networkConnectionsInfo=""
  fi

  if [ ${#public_addr} -gt 35 ]; then
    # if a LONG IPv6 address dont show "Public" in front to save space
    public_addr_pre=""
  fi

fi

# LIGHTNING NETWORK
if [ "${lightning}" == "cl" ]; then
 ln_getInfo=$($lightningcli_alias getinfo 2>/dev/null)
 ln_baseInfo="-"
 ln_channelInfo="\n"
 ln_external="\n"
 ln_alias="$(sudo cat "${CLCONF}" | grep "^alias=*" | cut -f2 -d=)"
 if [ ${#ln_alias} -eq 0 ];then
  ln_alias=$(echo "${ln_getInfo}" | grep '"alias":' | cut -d '"' -f4)
 fi
 if [ ${#ln_alias} -eq 0 ];then
  ln_alias=${hostname}
 fi
 ln_publicColor=""
 ln_port=$(sudo cat "${CLCONF}" | grep "^bind-addr=*" | cut -f2 -d':')
 if [ ${#ln_port} -eq 0 ]; then
   ln_port=$(echo "${ln_getInfo}" | grep '"port":' | cut -d: -f2 | tail -1 | bc)
 fi
 wallet_unlocked=0 #TODO
 if [ "$wallet_unlocked" -gt 0 ] ; then
  ln_alias="Wallet Locked"
 else
  pubkey=$(echo "${ln_getInfo}" | grep '"id":' | cut -d '"' -f4)
  address=$(echo "${ln_getInfo}" | grep '.onion' | cut -d '"' -f4)
 if [ ${#address} -eq 0 ];then
  address=$(echo "${ln_getInfo}" | grep '"ipv4"' -A 1 | tail -1 | cut -d '"' -f4)
 fi
  ln_external="${pubkey}@${address}:${ln_port}"
  ln_tor=$(echo "${ln_external}" | grep -c ".onion")
  if [ ${ln_tor} -eq 1 ]; then
    ln_publicColor="${color_green}"
  else
    public_check=$(nc -z -w6 ${public_ip} ${ln_port} 2>/dev/null; echo $?)
   if [ $public_check = "0" ] || [ "${ipv6}" == "on" ]; then
     # only set yellow/normal because netcat can only say that the port is open - not that it points to this device for sure
     ln_publicColor="${color_amber}"
   else
     ln_publicColor="${color_red}"
   fi
  fi
  BLOCKHEIGHT=$(echo "$blockchaininfo"|grep blocks|awk '{print $2}'|cut -d, -f1)
  CLHEIGHT=$(echo "${ln_getInfo}" | jq .blockheight)
  if [ "$BLOCKHEIGHT" == "$CLHEIGHT" ];then
    ln_sync=1
  else
    ln_sync=0
  fi
  ln_version=$($lightningcli_alias -V)
  if [ ${ln_sync} -eq 0 ]; then
     if [ ${#ln_getInfo} -eq 0 ]; then
       ln_baseInfo="${color_red} Not Started | Not Ready Yet"
     else
       ln_baseInfo="
               ${color_amber}Scanning blocks: ${CLHEIGHT}/${BLOCKHEIGHT}"
     fi
   else
     ln_walletbalance=0
     cl_listfunds=$($lightningcli_alias listfunds 2>/dev/null)
     for i in $(echo "$cl_listfunds" \
      |jq .outputs[]|jq 'select(.status=="confirmed")'|grep value|awk '{print $2}'|cut -d, -f1);do
       ln_walletbalance=$((ln_walletbalance+i))
     done
     for i in $(echo "$cl_listfunds" \
      |jq .outputs[]|jq 'select(.status=="unconfirmed")'|grep value|awk '{print $2}'|cut -d, -f1);do
       ln_walletbalance_wait=$((ln_walletbalance_wait+i))
     done
     # ln_closedchannelbalance: "state": "ONCHAIN" funds in channels
     for i in $(echo "$cl_listfunds" \
      |jq .channels[]|jq 'select(.state=="ONCHAIN")'|grep channel_sat|awk '{print $2}'|cut -d, -f1);do
       ln_closedchannelbalance=$((ln_closedchannelbalance+i))
     done
     # ln_pendingonchain: waiting onchain + waiting closed channel funds
     ln_pendingonchain=$((ln_walletbalance_wait+ln_closedchannelbalance))
     if [ "${ln_pendingonchain}" = "0" ]; then ln_pendingonchain=""; fi
     if [ ${#ln_pendingonchain} -gt 0 ]; then ln_pendingonchain="(+${ln_pendingonchain})"; fi
     # ln_channelbalance: "state": "CHANNELD_NORMAL" funds in channels
     for i in $(echo "$cl_listfunds" \
      |jq .channels[]|jq 'select(.state=="CHANNELD_NORMAL")'|grep channel_sat|awk '{print $2}'|cut -d, -f1);do
       ln_channelbalance=$((ln_channelbalance+i))
     done
     if [ ${#ln_channelbalance} -eq 0 ];then
      ln_channelbalance=0
     fi
     # ln_channelbalance_all: all funds in channels
     for i in $(echo "$cl_listfunds" \
      |jq .channels[]|grep channel_sat|awk '{print $2}'|cut -d, -f1);do
       ln_channelbalance_all=$((ln_channelbalance_all+i))
     done
     ln_channelbalance_pending=$((ln_channelbalance_all-ln_channelbalance-ln_closedchannelbalance))
     if [ "${ln_channelbalance_pending}" = "0" ]; then ln_channelbalance_pending=""; fi
     if [ ${#ln_channelbalance_pending} -gt 0 ]; then ln_channelbalance_pending=" (+${ln_channelbalance_pending})"; fi
     # - **num_peers** (u32): The total count of peers, connected or with channels
     # - **num_pending_channels** (u32): The total count of channels being opened
     # - **num_active_channels** (u32): The total count of channels in normal state
     # - **num_inactive_channels** (u32): The total count of channels waiting for opening or closing 
     ln_channels_online="$(echo "${ln_getInfo}" | jq -r '.num_active_channels')" 2>/dev/null
     cl_num_pending_channels="$(echo "${ln_getInfo}" | jq -r '.num_pending_channels')" 2>/dev/null
     cl_num_inactive_channels="$(echo "${ln_getInfo}" | jq -r '.num_inactive_channels')" 2>/dev/null
     ln_channels_total=$((ln_channels_online+cl_num_pending_channels+cl_num_inactive_channels))
     ln_baseInfo="${color_gray}Wallet ${ln_walletbalance} ${netprefix}sat ${ln_pendingonchain}"
     ln_peers="$(echo "${ln_getInfo}" | jq -r '.num_peers')" 2>/dev/null
     ln_channelInfo="${ln_channels_online}/${ln_channels_total} Channels ${ln_channelbalance} ${netprefix}sat${ln_channelbalance_pending}"
     ln_peersInfo="${color_green}${ln_peers} ${color_gray}peers"
     # - **fees_collected_msat** (msat): Total routing fees collected by this node
     #ln_dailyfees="$($lncli_alias  feereport | jq -r '.day_fee_sum')" 2>/dev/null
     #ln_weeklyfees="$($lncli_alias  feereport | jq -r '.week_fee_sum')" 2>/dev/null
     #ln_monthlyfees="$($lncli_alias  feereport | jq -r '.month_fee_sum')" 2>/dev/null
     #ln_feeReport="Fee Report (D-W-M): ${color_green}${ln_dailyfees}-${ln_weeklyfees}-${ln_monthlyfees} ${color_gray}sat"
     ln_feeReport="Fees collected: $(echo "${ln_getInfo}" |  jq -r '.fees_collected_msat')"
   fi
 fi
 
elif [ "${lightning}" == "lnd" ];then
 ln_baseInfo="-"
 ln_channelInfo="\n"
 ln_external="\n"
 ln_alias="$(sudo cat /mnt/hdd/lnd/${netprefix}lnd.conf | grep "^alias=*" | cut -f2 -d=)"
 if [ ${#ln_alias} -eq 0 ];then
  ln_alias=${hostname}
 fi
 ln_publicColor=""
 ln_port=$(sudo cat /mnt/hdd/lnd/${netprefix}lnd.conf | grep "^listen=*" | cut -f2 -d':')
 if [ ${#ln_port} -eq 0 ]; then
   ln_port="9735"
 fi
 wallet_unlocked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2> /dev/null | grep -c unlock)
 if [ "$wallet_unlocked" -gt 0 ] ; then
   ln_alias="Wallet Locked"
 else
  ln_getInfo=$($lncli_alias --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert getinfo 2>/dev/null)
  ln_external=$(echo "${ln_getInfo}" | grep "uris" -A 1 | tr -d '\n' | cut -d '"' -f4)
  ln_tor=$(echo "${ln_external}" | grep -c ".onion")
  if [ ${ln_tor} -eq 1 ]; then
    ln_publicColor="${color_green}"
  else
    public_check=$(nc -z -w6 ${public_ip} ${ln_port} 2>/dev/null; echo $?)
   if [ $public_check = "0" ] || [ "${ipv6}" == "on" ]; then
     # only set yellow/normal because netcat can only say that the port is open - not that it points to this device for sure
     ln_publicColor="${color_amber}"
   else
     ln_publicColor="${color_red}"
   fi
  fi
  ln_sync=$(echo "${ln_getInfo}" | grep "synced_to_chain" | grep "true" -c)
  ln_version=$(echo "${ln_getInfo}" | jq -r '.version' | cut -d' ' -f1)
  if [ ${ln_sync} -eq 0 ]; then
     if [ ${#ln_getInfo} -eq 0 ]; then
       ln_baseInfo="${color_red} Not Started | Not Ready Yet"
     else
       ln_baseInfo="${color_amber} Waiting for Chain Sync"
     fi
   else
     lnd_walletbalance=$($lncli_alias --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert walletbalance 2>/dev/null)
     ln_walletbalance="$(echo "$lnd_walletbalance" | jq -r '.confirmed_balance')" 2>/dev/null
     ln_walletbalance_wait="$(echo "$lnd_walletbalance" | jq -r '.unconfirmed_balance')" 2>/dev/null
     if [ "${ln_walletbalance_wait}" = "0" ]; then ln_walletbalance_wait=""; fi
     if [ ${#ln_walletbalance_wait} -gt 0 ]; then ln_walletbalance_wait="(+${ln_walletbalance_wait})"; fi
     lnd_channelbalance=$($lncli_alias --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert channelbalance 2>/dev/null)
     ln_channelbalance="$(echo "$lnd_channelbalance" | jq -r '.balance')" 2>/dev/null
     ln_channelbalance_pending="$(echo "$lnd_channelbalance" | jq -r '.pending_open_balance')" 2>/dev/null
     if [ "${ln_channelbalance_pending}" = "0" ]; then ln_channelbalance_pending=""; fi
     if [ ${#ln_channelbalance_pending} -gt 0 ]; then ln_channelbalance_pending=" (+${ln_channelbalance_pending})"; fi
     ln_channels_online="$(echo "${ln_getInfo}" | jq -r '.num_active_channels')" 2>/dev/null
     ln_channels_total="$($lncli_alias --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert listchannels | jq '.[] | length')" 2>/dev/null
     ln_baseInfo="${color_gray}wallet ${ln_walletbalance} ${netprefix}sat ${ln_walletbalance_wait}"
     ln_peers="$(echo "${ln_getInfo}" | jq -r '.num_peers')" 2>/dev/null
     ln_channelInfo="${ln_channels_online}/${ln_channels_total} Channels ${ln_channelbalance} ${netprefix}sat${ln_channelbalance_pending}"
     ln_peersInfo="${color_green}${ln_peers} ${color_gray}peers"
     lnd_feereport=$($lncli_alias --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert feereport 2>/dev/null)
     ln_dailyfees="$(echo "$lnd_feereport" | jq -r '.day_fee_sum')" 2>/dev/null
     ln_weeklyfees="$(echo "$lnd_feereport" | jq -r '.week_fee_sum')" 2>/dev/null
     ln_monthlyfees="$(echo "$lnd_feereport" | jq -r '.month_fee_sum')" 2>/dev/null
     ln_feeReport="Fee Report (D-W-M): ${color_green}${ln_dailyfees}-${ln_weeklyfees}-${ln_monthlyfees} ${color_gray}sat"
   fi
 fi
fi

# show JoinMarket stats in place of the LND URI only if the Yield Generator is running
source /home/joinmarket/joinin.conf 2>/dev/null
if [ "${joinmarket}" = "on" ] && [ $(sudo -u joinmarket pgrep -f "python yg-privacyenhanced.py $YGwallet --wallet-password-stdin" 2>/dev/null | wc -l) -gt 2 ]; then
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
else
    lastLine="\
${color_yellow}
${color_yellow}${ln_publicColor}${ln_external}${color_gray}"
  fi

if [ "${lightning}" == "cl" ];then
  LNline="C-LIGHTNING ${color_green}${ln_version}\n               ${ln_baseInfo}"
elif [ "${lightning}"  == "lnd" ];then
  LNline="LND ${color_green}${ln_version} ${ln_baseInfo}"
fi

if [ $cpu = 0 ];then
  templine="on $(uname -m) VM%s%s"
else
  templine="temp %s°C %s°F"
fi
sleep 5

LNinfo=" + Lightning Network"
if [ "${lightning}" == "" ]; then
  LNinfo=""  
fi

## get uptime and current date & time
uptime=$(uptime --pretty)
datetime=$(date -R)

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
${color_yellow}    ,' /       ${color_gray}%s, temp %s°C %s°F
${color_yellow}  ,'  /_____   ${color_gray}Free Mem ${color_ram}${ram} ${color_gray} HDDuse ${color_hdd}%s${color_gray}
${color_yellow},'_____    ,'  ${color_gray}SSH admin@${color_green}${local_ip}${color_gray} d${network_rx} u${network_tx}
${color_yellow}      /  ,'    ${color_gray}${webinterfaceInfo}
${color_yellow}     / ,'      ${color_gray}${network} ${color_green}${networkVersion} ${color_gray}${chain}net ${networkConnectionsInfo}
${color_yellow}    /,'        ${color_gray}Blocks ${blockInfo} ${color_gray}Sync ${sync_color}${sync} %s
${color_yellow}   /'          ${color_gray}
${color_yellow}               ${color_gray}${LNline}
${color_yellow}               ${color_gray}${ln_channelInfo} ${ln_peersInfo}
${color_yellow}               ${color_gray}${ln_feeReport}
$lastLine
" \
"RaspiBlitz v${codeVersion}" \
"-------------------------------------------" \
"Refreshed: ${datetime}" \
"CPU load${load##up*,  }" "${tempC}" "${tempF}" \
"${hdd}" "${sync_percentage}"

if [ ${#undervoltageReports} -gt 0 ] && [ "${undervoltageReports}" != "0" ]; then
  echo "${undervoltageReports} undervoltage reports - run 'Hardware Test' in menu"
elif [ ${#ups} -gt 1 ] && [ "${upsStatus}" = "n/a" ]; then
  echo "UPS service activated but not running"
else

  # checking status of apps and display if in sync or problems
  appInfoLine=""

  # Electrum Server - electrs
  if [ "${ElectRS}" = "on" ]; then
    error=""
    source <(sudo /home/admin/config.scripts/bonus.electrs.sh status 2>/dev/null)
    if [ ${#infoSync} -gt 0 ]; then
      appInfoLine="Electrum: ${infoSync}"
    fi
  fi

  # BTC RPC EXPLORER
  if [ "${BTCRPCexplorer}" = "on" ]; then
    error=""
    source <(sudo /home/admin/config.scripts/bonus.btc-rpc-explorer.sh status 2>/dev/null)
    if [ ${#error} -gt 0 ]; then
      appInfoLine="ERROR BTC-RPC-Explorer: ${error} (try restart)"
    elif [ "${isIndexed}" = "0" ]; then
      appInfoLine="BTC-RPC-Explorer: ${indexInfo}"
    fi
  fi

  if [ ${#appInfoLine} -gt 0 ]; then
    echo "${appInfoLine}"
  fi

fi

# EOF
