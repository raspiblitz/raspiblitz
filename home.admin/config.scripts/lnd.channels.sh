#!/bin/bash
# RaspiBolt channel overview display, by robclark56

# make executable & copy to 
# /usr/local/bin/lnchannels
# current user must be able to execute bitcoin-cli and lncli

# Usage
# $ lnchannels            to display lnd mainnet channels
# $ lnchannels --testnet  to display lnd testnet channels
# $ lnchannels litecoin   to display lnd litecoin channels

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

if [ "$lnd_pid" -eq "0" ]; then
 echo lnd not runnning.
 exit
fi

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[0;33m'
color_gray='\033[0;37m'

# gather values
a_active=( $(${lncli} listchannels | jq -r ' .channels[].active'))
a_remote_pubkey=( $(${lncli} listchannels | jq -r ' .channels[].remote_pubkey'))
a_capacity=( $(${lncli} listchannels | jq -r ' .channels[].capacity'))
a_local_balance=( $(${lncli} listchannels | jq -r ' .channels[].local_balance'))
a_remote_balance=( $(${lncli} listchannels | jq -r ' .channels[].remote_balance'))
a_commit_fee=( $(${lncli} listchannels | jq -r ' .channels[].commit_fee'))
a_channel_point=( $(${lncli} listchannels | jq -r ' .channels[].channel_point'))

total=${#a_active[*]}
total_capacity=0
total_fee=0
total_local=0
total_remote=0

#display
printf "\n${color_yellow}%-7s%60s %11s\n" "${chain}net" 'Commit ------- Balance ---------' '--- Fee ----'
printf "%-21s %12s %5s %12s %12s %6s %5s\n" 'Alias or Pubkey' 'Capacity' 'Fee' 'Local' 'Remote' 'Base' 'PerMil'
horiz_line="-------------------- ------------- ------ ------------ ------------ ----- ------"
echo $horiz_line
for (( i=0; i<=$(( $total -1 )); i++ ));do
 addr_port=$(${lncli} getnodeinfo ${a_remote_pubkey[$i]} | jq -r .node.addresses[0].addr)
 addr=${addr_port/:/ }
 if [ ${a_active[$i]} == 'true' ];  then
  color_line=${color_gray}
  public_check=''
 else
  color_line=${color_red}
  public_check='0';
  if [ "$addr" != 'null' ]; then public_check=$(timeout 2s nc -z ${addr}; echo $?);fi
  if [ "${public_check}" == '0' ];then public_check='';else public_check='X';fi
 fi
 alias=$(${lncli} getnodeinfo ${a_remote_pubkey[$i]} | jq -r .node.alias)
 if [ "${alias}" == "" ] ; then
  alias_short=$(echo ${a_remote_pubkey[$i]} | cut -c-17)...
 else
  alias_short=$(echo ${alias} | cut -c-20)
 fi
 active_short=$(echo ${a_active[$i]} | cut -c1)
 # get fee report details
 base_fee_msat=$(${lncli} feereport | jq -r ".channel_fees[] | select(.channel_point | test(\"${a_channel_point[$i]}\")) | .base_fee_msat")
 fee_per_mil=$(${lncli} feereport | jq -r ".channel_fees[] | select(.channel_point | 
 test(\"${a_channel_point[$i]}\")) | .fee_per_mil")
 # Display line 
 printf "${color_line}%-21s %12s %6s %12s %12s %5s %6s\r%-21s\n" \
        "" "${a_capacity[$i]}" "${a_commit_fee[$i]}" "${a_local_balance[$i]}" \
        "${a_remote_balance[$i]}" "${base_fee_msat}" "${fee_per_mil}"  "${alias_short}"
 total_capacity=$(( ${total_capacity} + ${a_capacity[$i]} ))
 total_fee=$(( ${total_fee} + ${a_commit_fee[$i]} ))
 total_local=$(( ${total_local} + ${a_local_balance[$i]} ))
 total_remote=$(( ${total_remote} + ${a_remote_balance[$i]} ))
 if [ ${#public_check} != 0 ] ; then echo " > No response from Addr:Port ${addr_port}";fi
done
printf "${color_yellow}%s\n" "${horiz_line}"
printf "Totals%14s %13s %6s %12s %12s Day: %7s\n" \
       "${total} ch" "${total_capacity}" "${total_fee}" \
       "${total_local}" "${total_remote}" \
       "$(${lncli} feereport |jq -r ".day_fee_sum" )"
printf "%74s %5s\n" 'Week: ' "$(${lncli} feereport |jq -r ".week_fee_sum" )"
printf "%74s %5s\n" 'Month:' "$(${lncli} feereport |jq -r ".month_fee_sum" )"
echo "$(tput -T xterm sgr0)"

