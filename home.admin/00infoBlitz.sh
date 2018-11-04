#!/bin/bash

# load code software version
source /home/admin/_version.info

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[0;33m'
color_gray='\033[0;37m'

# load network
network=`sudo cat /home/admin/.network`

# get chain
chain="test"
isMainChain=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep "#testnet=1" -c)
if [ ${isMainChain} -gt 0 ];then
  chain="main"
fi

# set datadir
bitcoin_dir="/home/bitcoin/.${network}"
lnd_dir="/home/bitcoin/.lnd"
lnd_macaroon_dir="/home/bitcoin/.lnd/data/chain/${network}/${chain}net"

# get uptime & load
load=$(w | head -n 1 | cut -d 'v' -f2 | cut -d ':' -f2)

# get CPU temp
cpu=$(cat /sys/class/thermal/thermal_zone0/temp)
temp=$((cpu/1000))

# get memory
ram_avail=$(free -m | grep Mem | awk '{ print $7 }')
ram=$(printf "%sM / %sM" "${ram_avail}" "$(free -m | grep Mem | awk '{ print $2 }')")

if [ ${ram_avail} -lt 100 ]; then
  color_ram="${color_red}\e[7m"
else
  color_ram=${color_green}
fi

# get free HDD ratio
hdd_free_ratio=$(printf "%d" "$(df -h | grep '/mnt/hdd$' | awk '{ print $4/$2*100 }')" 2>/dev/null)
hdd=$(printf "%s (%s%%)" "$(df -h | grep '/mnt/hdd$' | awk '{ print $4 }')" "${hdd_free_ratio}")

if [ ${hdd_free_ratio} -lt 10 ]; then
  color_hdd="${color_red}\e[7m"
else
  color_hdd=${color_green}
fi

# get network traffic
network_rx=$(ifconfig eth0 | grep 'RX packets' | awk '{ print $6$7 }' | sed 's/[()]//g')
network_tx=$(ifconfig eth0 | grep 'TX packets' | awk '{ print $6$7 }' | sed 's/[()]//g')

# Bitcoin blockchain
btc_path=$(command -v ${network}-cli)
if [ -n ${btc_path} ]; then
  btc_title=$network
  blockchaininfo="$(${network}-cli -datadir=${bitcoin_dir} getblockchaininfo 2>/dev/null)"
  if [ ${#blockchaininfo} -gt 0 ]; then
    btc_title="${btc_title} (${chain}net)"

    # get sync status
    block_chain="$(${network}-cli -datadir=${bitcoin_dir} getblockcount 2>/dev/null)"
    block_verified="$(echo "${blockchaininfo}" | jq -r '.blocks')"
    block_diff=$(expr ${block_chain} - ${block_verified})

    progress="$(echo "${blockchaininfo}" | jq -r '.verificationprogress')"
    sync_percentage=$(printf "%.2f%%" "$(echo $progress | awk '{print 100 * $1}')")

    if [ ${block_diff} -eq 0 ]; then    # fully synced
      sync="OK"
      sync_color="${color_green}"
      sync_behind=" "
    elif [ ${block_diff} -eq 1 ]; then          # fully synced
      sync="OK"
      sync_color="${color_green}"
      sync_behind="-1 block"
    elif [ ${block_diff} -le 10 ]; then    # <= 2 blocks behind
      sync="catchup"
      sync_color="${color_red}"
      sync_behind="-${block_diff} blocks"
    else
      sync="progress"
      sync_color="${color_red}"
      sync_behind="${sync_percentage}"
    fi

    # get last known block
    last_block="$(${network}-cli -datadir=${bitcoin_dir} getblockcount 2>/dev/null)"
    if [ ! -z "${last_block}" ]; then
      btc_line2="${btc_line2} ${color_gray}(block ${last_block})"
    fi

    # get mem pool transactions
    mempool="$(${network}-cli -datadir=${bitcoin_dir} getmempoolinfo 2>/dev/null | jq -r '.size')"

  else
    btc_line2="${color_red}NOT RUNNING\t\t"
  fi
fi

# get IP address & port
networkInfo=$(${network}-cli -datadir=${bitcoin_dir} getnetworkinfo 2>/dev/null)
local_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
public_ip=$(curl -s http://v4.ipv6-test.com/api/myip.php)
public_port="$(echo ${networkInfo} | jq -r '.localaddresses [0] .port')"
if [ "${public_port}" = "null" ]; then
  public_port="8333"
fi

# check if RTL web interface is installed
webinterfaceInfo=""
runningRTL=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')
if [ ${runningRTL} -eq 1 ]; then
  webinterfaceInfo="web admin --> ${color_green}http://${local_ip}:3000"
fi

# CHAIN NETWORK
public_addr="??"
torInfo=""
# Version
networkVersion=$(${network}-cli -datadir=${bitcoin_dir} -version 2>/dev/null | cut -d ' ' -f6)
# TOR or IP
onionAddress=$(echo ${networkInfo} | jq -r '.localaddresses [0] .address')
if [ "${onionAddress}" != "null" ]; then
  # TOR address
  public_addr="${onionAddress}:${public_port}"
  public=""
  public_color="${color_green}"
  torInfo="+ TOR"
else
  # IP address
  public_addr="${public_ip}:${public_port}"
  public_check=$(timeout 2s nc -z ${public_ip} ${public_port} 2>/dev/null; echo $?)
  if [ $public_check = "0" ]; then
    public="Yes"
    public_color="${color_green}"
  else
    public="Not reachable"
    public_color="${color_red}"
  fi
fi

# LIGHTNING NETWORK

ln_baseInfo="-"
ln_channelInfo="\n"
ln_external="\n"

wallet_unlocked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2> /dev/null | grep -c unlock)
if [ "$wallet_unlocked" -gt 0 ] ; then
 alias_color="${color_red}"
 ln_alias="Wallet Locked"
else
 ln_getInfo=$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert getinfo 2>/dev/null)
 ln_external=$(echo "${ln_getInfo}" | grep "uris" -A 1 | tr -d '\n' | cut -d '"' -f4)
 alias_color="${color_grey}"
 ln_alias=$(echo "${ln_getInfo}" | grep "alias" | cut -d '"' -f4)
 ln_sync=$(echo "${ln_getInfo}" | grep "synced_to_chain" | grep "true" -c)
 if [ ${ln_sync} -eq 0 ]; then
    if [ ${#ln_getInfo} -eq 0 ]; then
      ln_baseInfo="${color_red} Not Started | Not Ready Yet"
    else
      item=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2> /dev/null | grep "(height" | tail -n1 | awk '{print $10} {print $11} {print $12}' | tr -dc '0-9')  
      total=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 2>/dev/null | jq -r '.blocks')
      ln_baseInfo="${color_red} waiting for chain sync"
      if [ ${#item} -gt 0 ]; then
        ln_channelInfo="scanning ${item}/${total}"
      fi  
    fi
  else 
    ln_walletbalance="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert walletbalance | jq -r '.confirmed_balance')" 2>/dev/null
    ln_channelbalance="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert channelbalance | jq -r '.balance')" 2>/dev/null
    ln_channels_online="$(echo "${ln_getInfo}" | jq -r '.num_active_channels')" 2>/dev/null
    ln_channels_total="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert listchannels | jq '.[] | length')" 2>/dev/null
    ln_baseInfo="${color_gray}wallet ${ln_walletbalance} sat"
    ln_channelInfo="${ln_channels_online}/${ln_channels_total} Channels ${ln_channelbalance} sat"
  fi
fi

sleep 5
printf "
${color_yellow}
${color_yellow}
${color_yellow}
${color_yellow}               ${color_yellow}%s ${color_green} ${ln_alias}
${color_yellow}               ${color_gray}${network} Fullnode + Lightning Network ${torInfo}
${color_yellow}        ,/     ${color_yellow}%s
${color_yellow}      ,'/      ${color_gray}%s, CPU %s°C
${color_yellow}    ,' /       ${color_gray}Free Mem ${color_ram}${ram} ${color_gray} Free HDD ${color_hdd}%s
${color_yellow}  ,'  /_____,  ${color_gray}ssh admin@${color_green}${local_ip}${color_gray} ▼${network_rx} ▲${network_tx}
${color_yellow} .'____    ,'  ${color_gray}${webinterfaceInfo}
${color_yellow}      /  ,'    ${color_gray}${network} ${color_green}${networkVersion} ${chain}net ${color_gray}Sync ${sync_color}${sync} (%s)
${color_yellow}     / ,'      ${color_gray}Public ${public_color}${public_addr} ${public}
${color_yellow}    /,'        ${color_gray}
${color_yellow}   /'          ${color_gray}LND ${color_green}v0.5-beta ${ln_baseInfo}
${color_yellow}               ${color_gray}${ln_channelInfo}
${color_yellow}
${color_yellow}${ln_external}
" \
"RaspiBlitz v${codeVersion}" \
"-------------------------------------------" \
"load average:${load##up*,  }" "${temp}" \
"${hdd}" "${sync_percentage}"
if [ ${#onionAddress} -eq 0 ]; then
  # one extra space line at the end if nodeaddress is not TOR
  echo ""
fi
