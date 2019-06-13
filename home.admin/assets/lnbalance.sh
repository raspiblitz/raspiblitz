#!/bin/bash
# RaspiBolt channel balance display, by robclark56

# make executable & copy to 
# /usr/local/bin/lnbalance
# current user must be able to execute bitcoin-cli and lncli

# Usage
# $ lnbalance            to display lnd mainnet status
# $ lnbalance --testnet  to display lnd testnet status
# $ lnbalance litecoin   to display lnd litecoin status

# Set default (mainnet)
lncli='/usr/local/bin/lncli'
lnd_pid=$(systemctl show -p MainPID lnd | awk -F"=" '{print $2}')
chain='main'

# read cli args
for i in "$@"
do
case $i in
  --testnet*)
    lncli="${lncli} --network=testnet"
    lnd_pid=$(systemctl show -p MainPID lnd | awk -F"=" '{print $2}')
    chain='test'
    shift # past argument=value
    ;;
  *)
    lncli="/usr/local/bin/lncli --chain=$i"
    ;;
esac
done

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[0;33m'
color_gray='\033[0;37m'

# get LND info
wallet_color="${color_yellow}"
if [ "$lnd_pid" -ne "0" ]; then
 ${lncli} getinfo 2>&1 | grep "Please unlock" >/dev/null
 wallet_unlocked=$?
 if [ "$wallet_unlocked" -eq 0 ] ; then
  wallet_color="${color_red}"
  ln_walletbalance="Locked"
 else
  ln_walletbalance="$(${lncli} walletbalance | jq -r '.confirmed_balance')" 2>/dev/null
  ln_channelbalance="$(${lncli} channelbalance | jq -r '.balance')" 2>/dev/null
  ln_channels_active="$(${lncli} listchannels --active_only| jq '.[] | length')" 2>/dev/null
  ln_channels_inactive="$(${lncli} listchannels --inactive_only| jq '.[] | length')" 2>/dev/null
  active_remote="$(${lncli} listchannels --active_only | jq -r '.channels |.[] | .remote_balance ' | jq -s 'add')"
  active_local="$(${lncli} listchannels --active_only | jq -r '.channels |.[] | .local_balance ' | jq -s 'add')"
  inactive_remote="$(${lncli} listchannels --inactive_only | jq -r '.channels |.[] | .remote_balance ' | jq -s 'add')"
  active_fees="$(${lncli} listchannels --active_only | jq -r '.channels |.[] | .commit_fee ' | jq -s 'add')"
  inactive_fees="$(${lncli} listchannels --inactive_only | jq -r '.channels |.[] | .commit_fee ' | jq -s 'add')"
  inactive_local="$(${lncli} listchannels --inactive_only | jq -r '.channels |.[] | .local_balance ' | jq -s 'add')"
 if [ "${active_local}" = 'null' ];then active_local=0;fi
 if [ "${active_remote}" = 'null' ];then active_remote=0;fi
 if [ "${inactive_local}" = 'null' ];then inactive_local=0;fi
 if [ "${active_fees}" = 'null' ];then active_fees=0;fi
 if [ "${inactive_fees}" = 'null' ];then inactive_fees=0;fi
 if [ "${inactive_remote}" = 'null' ];then inactive_remote=0;fi
 if [ "${ln_walletbalance}" = 'null' ];then ln_walletbalance=0;fi
 if [ "${ln_walletbalance}" = 'Locked' ];then ln_walletbalance=0;fi
 total_local=$(( ${ln_walletbalance} + ${active_local} + ${inactive_local} ))
 total_remote=$(( ${active_remote} + ${inactive_remote} ))
 total_fees=$(( ${active_fees} + ${inactive_fees} ))
 ln_channels=$(( ${ln_channels_active} + ${ln_channels_inactive} ))
 fi
else
 wallet_color="${color_red}"
 ln_walletbalance="Not Running"
fi

margin=''
printf "
${margin}${color_yellow}%-21s${color_gray}|       ${color_yellow}Local${color_gray}|      ${color_yellow}Remote${color_gray}|${color_yellow}Commitment Fees${color_gray}|
${margin}${color_gray}%-21s|${color_green}%12s${color_gray}|%12s|%15s|
${margin}${color_gray}%-18s%3s|${color_green}%12s${color_gray}|${color_yellow}%12s${color_gray}|${color_red}%15s${color_gray}|
${margin}${color_gray}%-18s%3s|${color_red}%12s${color_gray}|${color_red}%12s${color_gray}|${color_red}%15s${color_gray}|
${margin}${color_gray}%-18s%3s|%12s|%12s|${color_red}%15s${color_gray}|
" \
"${chain}net (sat)" \
"Wallet" "${ln_walletbalance}" "" "" \
"Active Channels" "${ln_channels_active}" "${active_local}" "${active_remote}" "${active_fees}" \
"Inactive Channels" "${ln_channels_inactive}" "${inactive_local}"  "${inactive_remote}" "${inactive_fees}" \
"Total" "${ln_channels}" "${total_local}" "${total_remote}" "${total_fees}"

echo "$(tput -T xterm sgr0)"
