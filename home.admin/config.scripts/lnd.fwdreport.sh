#!/bin/bash

network=mainnet
chain=bitcoin

if [ "$1" = "-menu" ]; then
  _temp=$(mktemp -p /dev/shm/)
  _error=$(mktemp -p /dev/shm/)

  # load raspiblitz config data (with backup from old config)
  source /home/admin/raspiblitz.info
  source /mnt/hdd/raspiblitz.conf
  if [ ${#network} -eq 0 ]; then network=$(cat .network); fi
  if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
  if [ ${#chain} -eq 0 ]; then
    echo "gathering chain info ... please wait"
    chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
  fi

  # let user enter a <pubkey>@host
  l1="Enter the number of days to query:"
  l2="e.g. '7' will query the last 7 days"
  dialog --title "Create a forwarding event report" \
--backtitle "Lightning ( ${network} | ${chain} )" \
--inputbox "$l1\n$l2" 10 60 7 2>$_temp
_input=$(cat $_temp | xargs )
  shred -u $_temp
  if [ ${#_input} -eq 0 ]; then
    exit 1
  fi
  
  clear
  /home/admin/config.scripts/lnd.fwdreport.sh -n ${chain}net -c ${network} -- ${_input}
  exit
fi


if [ $# -gt 1 ]; then
        while [ -n "$1" ]; do # while loop starts
            case "$1" in
            -c) chain=$2
                shift
                ;;
            -n)
                network="$2"
                shift
                ;;
            --)
                shift # The double dash makes them parameters
                break
                ;;
            *) echo "Option $1 not recognized" ;;
            esac
            shift
        done
fi

days=${1:-1}
start_date=$(date -d "$date -$days days" +%s)

declare -A pubKeyAliasLookup 
while IFS= read -r pubKey
do
	alias=$(lncli --network $network --chain $chain getnodeinfo $pubKey | jq '.node.alias')
	alias=${alias:1:-1}
	pubKeyAliasLookup[$pubKey]=$alias
	# echo $pubKey : ${pubKeyAliasLookup[$pubKey]}
done < <(lncli --network $network --chain $chain listpeers | jq '.peers[].pub_key' | tr -d '"')

declare -A channelIdPubKeyLookup
while IFS=, read -r remotePubKey channelId
do
	channelIdPubKeyLookup[$channelId]=$remotePubKey
done < <(lncli --network $network --chain $chain listchannels \
	| jq --raw-output '.channels[] | [.remote_pubkey,.chan_id] | @csv' \
	| tr -d '"')

OUTPUT="Date,Channel In,Channel Out,Amount,Fee
----------------,----------,-----------,------,---"

declare -i index_offset=0
while :
do
	events=$(lncli --network $network --chain $chain fwdinghistory --start_time $start_date --index_offset $index_offset \
		| jq -r '(([.last_offset_index, (.forwarding_events | length)]) | @csv),
			   (.forwarding_events[] 
			   | [(.timestamp | tonumber | strftime("%a %d %h %H:%M")), .chan_id_in, .chan_id_out, .amt_out, .fee] 
			   | @csv)' \
		| tr -d '"')
 	IFS=, read last_offset_index event_count <<< "$events"

	while IFS=, read eventDate channelIdIn channelIdOut amountIn fee
	do
 		channelInPubKey=${channelIdPubKeyLookup[$channelIdIn]}
 		channelOutPubKey=${channelIdPubKeyLookup[$channelIdOut]}
 		OUTPUT="${OUTPUT}
${eventDate},${pubKeyAliasLookup[$channelInPubKey]},${pubKeyAliasLookup[$channelOutPubKey]},$amountIn,$fee" 

	done < <(tail -n +2 <<< $events)

	if [ $event_count -lt 100 ]; then break; fi
	index_offset=$last_offset_index

done 

column -t -s',' <<< "$OUTPUT"
