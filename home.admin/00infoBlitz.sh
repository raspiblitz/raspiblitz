#!/bin/bash

# load code software version
source /home/admin/_version.info

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_amber='\033[0;33m'
color_yellow='\033[1;93m'
color_gray='\033[0;37m'
color_purple='\033[0;35m'

## get basic info
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null

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
    network=`sudo cat /home/admin/.network 2>/dev/null`
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
bitcoin_dir="/home/bitcoin/.${network}"
lnd_dir="/home/bitcoin/.lnd"
lnd_macaroon_dir="/home/bitcoin/.lnd/data/chain/${network}/${chain}net"

# get uptime & load
load=$(w | head -n 1 | cut -d 'v' -f2 | cut -d ':' -f2)

# get CPU temp - no measurement in a VM
cpu=0
if [ -d "/sys/class/thermal/thermal_zone0/" ]; then
  cpu=$(cat /sys/class/thermal/thermal_zone0/temp)
fi
tempC=$((cpu/1000))
tempF=$(((tempC * 18 + 325) / 10))

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
runningRTL=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')
if [ ${runningRTL} -eq 1 ]; then
  webinterfaceInfo="Web admin --> ${color_green}http://${local_ip}:3000"
fi

# CHAIN NETWORK
public_addr_pre="Public "
public_addr="??"
torInfo=""
# Version
networkVersion=$(${network}-cli -datadir=${bitcoin_dir} -version 2>/dev/null | cut -d ' ' -f6)
# TOR or IP
networkInfo=$(${network}-cli -datadir=${bitcoin_dir} getnetworkinfo)
networkConnections=$(echo ${networkInfo} | jq -r '.connections')
networkConnectionsInfo="${color_purple}${networkConnections} ${color_gray}connections"

if [ "${runBehindTor}" = "on" ]; then

  # TOR address
  onionAddress=$(echo ${networkInfo} | jq -r '.localaddresses [0] .address')
  networkConnectionsInfo="${color_purple}${networkConnections} ${color_gray}peers"
  public_addr="${onionAddress}:${public_port}"
  public=""
  public_color="${color_green}"
  torInfo="+ Tor"

else

  # IP address
  networkConnectionsInfo="${color_purple}${networkConnections} ${color_gray}connections"
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

ln_baseInfo="-"
ln_channelInfo="\n"
ln_external="\n"
ln_alias="${hostname}"
ln_publicColor=""
ln_port=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep "^listen=*" | cut -f2 -d':')
if [ ${#ln_port} -eq 0 ]; then
  ln_port="9735"
fi

wallet_unlocked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2> /dev/null | grep -c unlock)
if [ "$wallet_unlocked" -gt 0 ] ; then
 alias_color="${color_red}"
 ln_alias="Wallet Locked"
else
 ln_getInfo=$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert getinfo 2>/dev/null)
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
 alias_color="${color_grey}"
 ln_sync=$(echo "${ln_getInfo}" | grep "synced_to_chain" | grep "true" -c)
 ln_version=$(echo "${ln_getInfo}" | jq -r '.version' | cut -d' ' -f1)
 if [ ${ln_sync} -eq 0 ]; then
    if [ ${#ln_getInfo} -eq 0 ]; then
      ln_baseInfo="${color_red} Not Started | Not Ready Yet"
    else
      ln_baseInfo="${color_amber} Waiting for Chain Sync"
    fi
  else
    ln_walletbalance="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert walletbalance | jq -r '.confirmed_balance')" 2>/dev/null
    ln_walletbalance_wait="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert walletbalance | jq -r '.unconfirmed_balance')" 2>/dev/null
    if [ "${ln_walletbalance_wait}" = "0" ]; then ln_walletbalance_wait=""; fi
    if [ ${#ln_walletbalance_wait} -gt 0 ]; then ln_walletbalance_wait="(+${ln_walletbalance_wait})"; fi
    ln_channelbalance="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert channelbalance | jq -r '.balance')" 2>/dev/null
    ln_channelbalance_pending="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert channelbalance | jq -r '.pending_open_balance')" 2>/dev/null
    if [ "${ln_channelbalance_pending}" = "0" ]; then ln_channelbalance_pending=""; fi
    if [ ${#ln_channelbalance_pending} -gt 0 ]; then ln_channelbalance_pending=" (+${ln_channelbalance_pending})"; fi
    ln_channels_online="$(echo "${ln_getInfo}" | jq -r '.num_active_channels')" 2>/dev/null
    ln_channels_total="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert listchannels | jq '.[] | length')" 2>/dev/null
    ln_baseInfo="${color_gray}wallet ${ln_walletbalance} sat ${ln_walletbalance_wait}"
    ln_peers="$(echo "${ln_getInfo}" | jq -r '.num_peers')" 2>/dev/null
    ln_channelInfo="${ln_channels_online}/${ln_channels_total} Channels ${ln_channelbalance} sat${ln_channelbalance_pending}"
    ln_peersInfo="${color_purple}${ln_peers} ${color_gray}peers"
    ln_dailyfees="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert feereport | jq -r '.day_fee_sum')" 2>/dev/null
    ln_weeklyfees="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert feereport | jq -r '.week_fee_sum')" 2>/dev/null
    ln_monthlyfees="$(sudo -u bitcoin /usr/local/bin/lncli --macaroonpath=${lnd_macaroon_dir}/readonly.macaroon --tlscertpath=${lnd_dir}/tls.cert feereport | jq -r '.month_fee_sum')" 2>/dev/null
    ln_feeReport="Fee Report: ${color_green}${ln_dailyfees}-${ln_weeklyfees}-${ln_monthlyfees} ${color_gray}sat (D-W-M)"
  fi
fi

# show JoinMarket stats in place of the LND URI only if the Yield Generator is running

source /home/joinmarket/joinin.conf 2>/dev/null
if [ "${joinmarket}" = "on" ] && [ $(sudo -u joinmarket pgrep -f "python yg-privacyenhanced.py $YGwallet --wallet-password-stdin" 2>/dev/null | wc -l) -gt 2 ]; then
  JMstats=$(mktemp 2>/dev/null)
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

sleep 5

## get uptime and current date & time
uptime=$(uptime --pretty)
datetime=$(date -R)

clear
printf "
${color_yellow}
${color_yellow}
${color_yellow}
${color_yellow}               ${color_amber}%s ${color_green} ${ln_alias} ${upsInfo}
${color_yellow}               ${color_gray}${network^} Fullnode + Lightning Network ${torInfo}
${color_yellow}        ,/     ${color_yellow}%s
${color_yellow}      ,'/      ${color_gray}%s
${color_yellow}    ,' /       ${color_gray}%s, temp %s°C %s°F
${color_yellow}  ,'  /_____,  ${color_gray}Free Mem ${color_ram}${ram} ${color_gray} HDDuse ${color_hdd}%s${color_gray}
${color_yellow} .'____    ,'  ${color_gray}SSH admin@${color_green}${local_ip}${color_gray} d${network_rx} u${network_tx}
${color_yellow}      /  ,'    ${color_gray}${webinterfaceInfo}
${color_yellow}     / ,'      ${color_gray}${network} ${color_green}${networkVersion} ${chain}net ${color_gray}Sync ${sync_color}${sync} %s
${color_yellow}    /,'        ${color_gray}${public_addr_pre}${public_color}${public_addr} ${public}${networkConnectionsInfo}
${color_yellow}   /'          ${color_gray}
${color_yellow}               ${color_gray}LND ${color_green}${ln_version} ${ln_baseInfo}
${color_yellow}               ${color_gray}${ln_channelInfo} ${ln_peersInfo}
${color_yellow}               ${color_gray}${ln_feeReport}
$lastLine
" \
"RaspiBlitz v${codeVersion}" \
"-------------------------------------------" \
"Refreshed: ${datetime}" \
"CPU load${load##up*,  }" "${tempC}" "${tempF}" \
"${hdd}" "${sync_percentage}"

source /home/admin/stresstest.report 2>/dev/null
if [ ${#undervoltageReports} -gt 0 ] && [ "${undervoltageReports}" != "0" ]; then
  echo "${undervoltageReports} undervoltage reports - run 'Hardware Test' in menu"
elif [ ${#powerFAIL} -gt 0 ] && [ ${powerFAIL} -gt 0 ]; then
  echo "Weak power supply detected - run 'Hardware Test' in menu"
elif [ ${#ups} -gt 1 ] && [ "${upsStatus}" = "n/a" ]; then
  echo "UPS service activated but not running"
else

  # cheching status of apps and display if in sync or problems
  appInfoLine=""

  # Electrum Server - electrs
  if [ "${ElectRS}" = "on" ]; then
    source <(sudo /home/admin/config.scripts/bonus.electrs.sh status)
    if [ ${#infoSync} -gt 0 ]; then
      appInfoLine="Electrum: ${infoSync}"
    fi
  fi

  # BTC RPC EXPLORER
  if [ "${BTCRPCexplorer}" = "on" ]; then
    source <(sudo /home/admin/config.scripts/bonus.btc-rpc-explorer.sh status)
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

# if running as user "pi":
#  - write results to a JSON file on RAM disk
#  - update info.html file
if [ "${EUID}" = "$(id -u pi)" ]; then

    json_ln_baseInfo=$(echo "${ln_baseInfo}" | cut -c 11-)

    cat <<EOF > /var/cache/raspiblitz/info.json
{
    "uptime": "${uptime}",
    "datetime": "${datetime}",
    "codeVersion": "${codeVersion}",
    "hostname": "${hostname}",
    "network": "${network}",
    "torInfo": "${torInfo}",
    "load": "${load}",
    "tempC": "${tempC}",
    "tempF": "${tempF}",
    "ram": "${ram}",
    "hddUsedInfo": "${hddUsedInfo}",
    "local_ip": "${local_ip}",
    "network_rx": "${network_rx}",
    "network_tx": "${network_tx}",
    "runningRTL": "${runningRTL}",
    "networkVersion": "${networkVersion}",
    "chain": "${chain}",
    "progress": "${progress}",
    "sync_percentage": "${sync_percentage}",
    "public_addr_pre": "${public_addr_pre}",
    "public_addr": "${public_addr}",
    "public": "${public}",
    "networkConnections": "${networkConnections}",
    "mempool": "${mempool}",
    "ln_sync": "${ln_sync}",
    "ln_version": "${ln_version}",
    "ln_baseInfo": "${json_ln_baseInfo}",
    "ln_peers": "${ln_peers}",
    "ln_channelInfo": "${ln_channelInfo}",
    "ln_external": "${ln_external}"
}
EOF

  # use Jinja2 and apply json data to template to produce static html file
  templateExists=$(sudo ls /var/cache/raspiblitz/info.json 2>/dev/null | grep -c 'info.json')
  if [ ${templateExists} -gt 0 ]; then
    res=$(/usr/local/bin/j2 /var/www/blitzweb/info/info.j2 /var/cache/raspiblitz/info.json -o /var/cache/raspiblitz/info.html)
    if ! [ $? -eq 0 ]; then
      echo "an error occured.. maybe JSON syntax is wrong..!"
      echo "${res}"
    fi
  fi

fi
# EOF
