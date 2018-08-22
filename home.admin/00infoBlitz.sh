#!/bin/sh
# RaspiBolt LND Mainnet: systemd unit for getpublicip.sh script
# /etc/systemd/system/20-raspibolt-welcome.sh

# make executable and copy script to /etc/update-motd.d/
# root must be able to execute network cli and lncli

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[0;33m'
color_gray='\033[0;37m'

# load network
network=`sudo cat /home/admin/.network`

# set datadir
bitcoin_dir="/home/bitcoin/.${network}"
lnd_dir="/home/bitcoin/.lnd"

# get uptime & load
load=$(w | grep "load average:" | cut -c11-)

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

# get storage
sd_free_ratio=$(printf "%d" "$(df -h | grep "/$" | awk '{ print $4/$2*100 }')") 2>/dev/null
sd=$(printf "%s (%s%%)" "$(df -h | grep '/$' | awk '{ print $4 }')" "${sd_free_ratio}")
if [ ${sd_free_ratio} -lt 10 ]; then
  color_sd="${color_red}"
else
  color_sd=${color_green}
fi

hdd_free_ratio=$(printf "%d" "$(df -h | grep '/mnt/hdd$' | awk '{ print $4/$2*100 }')") 2>/dev/null
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
  chain="$(${network}-cli -datadir=${bitcoin_dir} getblockchaininfo | jq -r '.chain')"
  if [ -n $chain ]; then
    btc_title="${btc_title} (${chain}net)"

    # get sync status
    block_chain="$(${network}-cli -datadir=${bitcoin_dir} getblockcount)"
    block_verified="$(${network}-cli -datadir=${bitcoin_dir} getblockchaininfo | jq -r '.blocks')"
    block_diff=$(expr ${block_chain} - ${block_verified})

    progress="$(${network}-cli -datadir=${bitcoin_dir} getblockchaininfo | jq -r '.verificationprogress')"
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
    last_block="$(${network}-cli -datadir=${bitcoin_dir} getblockcount)"
    if [ ! -z "${last_block}" ]; then
      btc_line2="${btc_line2} ${color_gray}(block ${last_block})"
    fi

    # get mem pool transactions
    mempool="$(${network}-cli -datadir=${bitcoin_dir} getmempoolinfo | jq -r '.size')"

  else
    btc_line2="${color_red}NOT RUNNING\t\t"
  fi
fi

# get IP address & port
local_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
public_ip=$(curl -s http://v4.ipv6-test.com/api/myip.php)
public_port=$(cat ${bitcoin_dir}/${network}.conf 2>/dev/null | grep port= | awk -F"=" '{print $2}')
if [ "${public_port}" = "" ]; then
  if [ "${network}" = "litecoin" ]; then
    if [ "${chain}"  = "test" ]; then
      public_port=19333
    else
      public_port=9333
    fi
  else
    if [ "${chain}"  = "test" ]; then
      public_port=18333
    else
      public_port=8333
    fi
  fi
fi

# CHAIN NETWORK
public_addr="??"
torInfo=""
# Version
networkVersion=$(${network}-cli -datadir=${bitcoin_dir} -version | cut -d ' ' -f6)
# TOR or IP
onionAddress=$(${network}-cli -datadir=${bitcoin_dir} getnetworkinfo | grep '"address"' | cut -d '"' -f4)
if [ ${#onionAddress} -gt 0 ]; then
  # TOR address
  public_addr="${onionAddress}:${public_port}"
  public=""
  public_color="${color_green}"
  torInfo="+ TOR"
else
  # IP address
  public_addr="${public_ip}:${public_port}"
  public_check=$(timeout 2s nc -z ${public_ip} ${public_port}; echo $?)
  if [ $public_check = "0" ]; then
    public="Yes"
    public_color="${color_green}"
  else
    public="Not reachable"
    public_color="${color_red}"
  fi
fi

#IP


# LIGHTNING NETWORK
ln_getInfo=$(/usr/local/bin/lncli --macaroonpath=${lnd_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert getinfo)

ln_sync=$(echo "${ln_getInfo}" | grep "synced_to_chain" | grep "true" -c)
ln_external=$(echo "${ln_getInfo}" | grep "uris" -A 2 | tr -d '\n' | cut -d '"' -f4)

# get LND info
wallet_unlocked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
if [ "$wallet_unlocked" -gt 0 ] ; then
 alias_color="${color_red}"
 ln_alias="Wallet Locked"
else
 alias_color="${color_grey}"
 ln_alias=$(echo "${ln_getInfo}" | grep "alias" | cut -d '"' -f4)
 ln_walletbalance="$(/usr/local/bin/lncli --macaroonpath=${lnd_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert walletbalance | jq -r '.confirmed_balance')" 2>/dev/null
 ln_channelbalance="$(/usr/local/bin/lncli --macaroonpath=${lnd_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert channelbalance | jq -r '.balance')" 2>/dev/null

fi
ln_channels_online="$(echo "${ln_getInfo}" | jq -r '.num_active_channels')" 2>/dev/null
ln_channels_total="$(/usr/local/bin/lncli --macaroonpath=${lnd_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert listchannels | jq '.[] | length')" 2>/dev/null
ln_external_ip="$(echo $ln_external | tr ":" " " | awk '{ print $1 }' )" 2>/dev/null
if [ "$ln_external_ip" = "$public_ip" ]; then
  external_color="${color_grey}"
else
  external_color="${color_red}"
fi

ln_baseInfo="${color_gray}wallet ${ln_walletbalance} sat"
ln_channelInfo="${ln_channels_online}/${ln_channels_total} Channels ${ln_channelbalance} sat"
if [ ${ln_sync} -eq 0 ]; then
  ln_baseInfo="${color_red} waiting for chain sync"
  ln_channelInfo=""
fi

sleep 5
printf "
${color_yellow}
${color_yellow}
${color_yellow}
${color_yellow}               ${color_yellow}%s ${color_green} ${ln_alias}
${color_yellow}               ${color_gray}${network} Fullnode + Lightning Network ${torInfo}
${color_yellow}               ${color_yellow}%s
${color_yellow}        ,/     ${color_gray}%s, CPU %s°C
${color_yellow}      ,'/      ${color_gray}Free Mem ${color_ram}${ram} ${color_gray} Free HDD ${color_hdd}%s
${color_yellow}    ,' /       ${color_gray}Local  ${color_green}${local_ip}${color_gray}  ▼ ${network_rx} ▲ ${network_tx}
${color_yellow}  ,'  /_____,  ${color_gray}
${color_yellow} .'____    ,'  ${color_gray}${network} ${color_green}${networkVersion} ${chain}net ${color_gray}Sync ${sync_color}${sync} (%s)
${color_yellow}      /  ,'    ${color_gray}Public ${public_color}${public_addr} ${public}
${color_yellow}     / ,'      ${color_gray}
${color_yellow}    /,'        ${color_gray}LND ${color_green}v0.4.2 ${ln_baseInfo}
${color_yellow}   /'          ${color_gray}${ln_channelInfo}
${color_yellow}               
${color_yellow}${ln_external}
" \
"RaspiBlitz v0.8" \
"-------------------------------------------" \
"${load##up*,  }" "${temp}" \
"${hdd}" "${sync_percentage}"

echo "$(tput -T xterm sgr0)"
