#!/bin/bash

# Sweep a full CLN on-chain UTXO into Lightning via a Boltz submarine swap
# Requires: boltzcli service running, Core Lightning active
# Uses whiptail dialogs for interactive UTXO selection and confirmation

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ] || [ "$1" = "--help" ]; then
  echo "# Sweep a CLN UTXO to Lightning via Boltz submarine swap"
  echo "# cl.boltz-sweep.sh       (interactive whiptail mode)"
  echo "# cl.boltz-sweep.sh sweep (same as above)"
  exit 1
fi

source /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null
source <(/home/admin/config.scripts/network.aliases.sh getvars cl mainnet)

# check that CLN is active
if [ "${cl}" != "on" ] && [ "${lightning}" != "cl" ]; then
  whiptail --title " Boltz Sweep " --msgbox "Core Lightning is not active on this node." 8 50
  exit 1
fi

# check that boltzcli is installed and running
if ! command -v boltzcli &>/dev/null; then
  whiptail --title " Boltz Sweep " --msgbox "Boltz Client (boltzcli) is not installed.\nEnable it in Additional Services." 9 55
  exit 1
fi
isRunning=$(systemctl status boltzcli 2>/dev/null | grep -c 'active (running)')
if [ ${isRunning} -eq 0 ]; then
  whiptail --title " Boltz Sweep " --msgbox "Boltz Client service is not running.\nStart with: sudo systemctl start boltzcli" 9 55
  exit 1
fi

# cl alias - set by network.aliases.sh (lightningcli_alias)
CL="${lightningcli_alias}"
BOLTZCLI="sudo -u boltz boltzcli --datadir /mnt/hdd/app-data/boltzcli"

# === Step 1: List available confirmed UTXOs ===
UTXO_JSON=$(${CL} listfunds 2>&1)
if [ $? -ne 0 ]; then
  whiptail --title " Boltz Sweep " --msgbox "Could not list funds from CLN:\n${UTXO_JSON}" 12 65
  exit 1
fi

# filter for confirmed, unreserved outputs
UTXO_LIST=$(echo "${UTXO_JSON}" | jq -c '[.outputs[] | select(.status == "confirmed" and .reserved == false)]')
UTXO_COUNT=$(echo "${UTXO_LIST}" | jq 'length')

if [ "${UTXO_COUNT}" = "0" ] || [ "${UTXO_COUNT}" = "null" ]; then
  whiptail --title " Boltz Sweep " --msgbox "No confirmed, unreserved UTXOs available." 8 50
  exit 0
fi

# build whiptail radiolist
MENU_OPTIONS=()
idx=0
while IFS= read -r line; do
  txid=$(echo "${line}" | jq -r '.txid')
  vout=$(echo "${line}" | jq -r '.output')
  amount_msat=$(echo "${line}" | jq -r '.amount_msat' | sed 's/msat$//')
  amount_sat=$((amount_msat / 1000))
  short_txid="${txid:0:12}...${txid: -4}"
  MENU_OPTIONS+=("${idx}" "${short_txid}:${vout}  ${amount_sat} sats" "OFF")
  idx=$((idx + 1))
done < <(echo "${UTXO_LIST}" | jq -c '.[]')

# auto-select if only one
if [ ${UTXO_COUNT} -eq 1 ]; then
  MENU_OPTIONS[2]="ON"
fi

SELECTED=$(whiptail --title " Boltz Sweep [1/4] - Select UTXO " \
  --radiolist "Select which on-chain UTXO to sweep into Lightning.\nThe entire UTXO (minus miner fee) will be swapped.\n\nUse SPACE to select, ENTER to confirm:" \
  $((UTXO_COUNT + 10)) 65 ${UTXO_COUNT} \
  --ok-button "Next" --cancel-button "Exit" \
  "${MENU_OPTIONS[@]}" \
  3>&1 1>&2 2>&3)

if [ $? -ne 0 ] || [ -z "${SELECTED}" ]; then
  exit 0
fi

# extract selected UTXO details
UTXO_DATA=$(echo "${UTXO_LIST}" | jq -c ".[${SELECTED}]")
UTXO_TXID=$(echo "${UTXO_DATA}" | jq -r '.txid')
UTXO_VOUT=$(echo "${UTXO_DATA}" | jq -r '.output')
UTXO_AMTMSAT=$(echo "${UTXO_DATA}" | jq -r '.amount_msat' | sed 's/msat$//')
UTXO_AMTSAT=$((UTXO_AMTMSAT / 1000))

# === Step 2: Calculate fee using utxopsbt ===
FEERATE="normal"
START_WEIGHT=112  # ~112 WU for 1-in/1-out taproot tx

FEE_INFO=$(${CL} -k utxopsbt \
  satoshi="0sat" \
  feerate="${FEERATE}" \
  startweight=${START_WEIGHT} \
  utxos="[\"${UTXO_TXID}:${UTXO_VOUT}\"]" \
  reserve=0 \
  reservedok=true \
  locktime=0 \
  min_witness_weight=0 \
  excess_as_change=false 2>&1)

if [ $? -ne 0 ]; then
  whiptail --title " Boltz Sweep " --msgbox "Fee calculation failed (utxopsbt):\n${FEE_INFO}" 12 65
  exit 1
fi

# helper to unreserve on abort/failure
unreserve_utxo() {
  ${CL} -k unreserveinputs psbt="$(echo "${FEE_INFO}" | jq -r '.psbt')" 2>/dev/null
}

FEE_MSAT=$(echo "${FEE_INFO}" | jq -r '.excess_msat' | sed 's/msat$//')
if [ -z "${FEE_MSAT}" ] || [ "${FEE_MSAT}" = "null" ]; then
  whiptail --title " Boltz Sweep " --msgbox "Could not extract fee from utxopsbt result." 8 55
  unreserve_utxo
  exit 1
fi

# the "excess" from utxopsbt with satoshi=0 is: UTXO_value - fee
FEE_SAT=$(( (UTXO_AMTMSAT - FEE_MSAT) / 1000 ))
SEND_MSAT=${FEE_MSAT}
SEND_SAT=$((SEND_MSAT / 1000))

# === Step 3: Sanity checks ===
if [ ${SEND_SAT} -le 0 ]; then
  whiptail --title " Boltz Sweep " --msgbox "UTXO too small to cover the miner fee.\nCannot proceed." 8 50
  unreserve_utxo
  exit 1
fi

# Confirm the swap details
CONFIRM_TEXT="Sweep UTXO to Lightning via Boltz:\n\n"
CONFIRM_TEXT+="UTXO:         ${UTXO_TXID:0:16}...:${UTXO_VOUT}\n"
CONFIRM_TEXT+="UTXO amount:  ${UTXO_AMTSAT} sats\n"
CONFIRM_TEXT+="Miner fee:    ${FEE_SAT} sats (est.)\n"
CONFIRM_TEXT+="Swap amount:  ${SEND_SAT} sats\n"
CONFIRM_TEXT+="\nBoltz will charge a small service fee on top.\n"
CONFIRM_TEXT+="You will receive Lightning sats into your CLN wallet."

if [ ${SEND_SAT} -lt 1000000 ]; then
  CONFIRM_TEXT+="\n\nWARNING: Amount is below Boltz BTC submarine swap minimum (1,000,000 sats)."
fi

whiptail --title " Boltz Sweep [2/4] - Review Fees " --yesno "${CONFIRM_TEXT}" 18 65 \
  --yes-button "Next" --no-button "Exit"
if [ $? -ne 0 ]; then
  unreserve_utxo
  exit 0
fi

# === Step 3: Create Boltz submarine swap ===
clear
echo "# [3/4] Creating Boltz submarine swap for ${SEND_SAT} sats ..."

# get a refund address so Boltz can auto-refund if the swap fails
REFUND_ADDR=$(${CL} newaddr 2>/dev/null | jq -r '.bech32 // .p2tr // empty')

SWAP_RESULT=$(${BOLTZCLI} createswap --json --external-pay --refund "${REFUND_ADDR}" btc ${SEND_SAT} 2>&1)
if [ $? -ne 0 ]; then
  whiptail --title " Boltz Sweep " --msgbox "Swap creation failed:\n${SWAP_RESULT}" 14 70
  unreserve_utxo
  exit 1
fi

# extract swap details
SWAP_ID=$(echo "${SWAP_RESULT}" | jq -r '.id // .swapId // empty')
BOLTZ_ADDRESS=$(echo "${SWAP_RESULT}" | jq -r '.address // empty')
EXPECTED_AMOUNT=$(echo "${SWAP_RESULT}" | jq -r '.expectedAmount // empty')

if [ -z "${BOLTZ_ADDRESS}" ]; then
  whiptail --title " Boltz Sweep " --msgbox "Could not extract deposit address from swap.\n\nRaw result:\n${SWAP_RESULT}" 14 70
  unreserve_utxo
  exit 1
fi

# === Step 3 (cont): Prepare the transaction ===
echo "# [3/4] Preparing on-chain transaction ..."

REAL_RESP=$(${CL} -k txprepare \
  outputs="[{\"${BOLTZ_ADDRESS}\": \"all\"}]" \
  feerate="${FEERATE}" \
  minconf=1 \
  utxos="[\"${UTXO_TXID}:${UTXO_VOUT}\"]" 2>&1)

if [ $? -ne 0 ]; then
  whiptail --title " Boltz Sweep " --msgbox "txprepare failed:\n${REAL_RESP}" 12 70
  unreserve_utxo
  exit 1
fi

REAL_TXID=$(echo "${REAL_RESP}" | jq -r '.txid')
REAL_PSBT=$(echo "${REAL_RESP}" | jq -r '.psbt // empty')
if [ -z "${REAL_TXID}" ] || [ "${REAL_TXID}" = "null" ]; then
  whiptail --title " Boltz Sweep " --msgbox "Could not get txid from txprepare." 8 55
  unreserve_utxo
  exit 1
fi

# extract invoice/bip21 from swap result
SWAP_INVOICE=$(echo "${SWAP_RESULT}" | jq -r '.invoice // .bolt11 // .bolt12 // empty')
SWAP_BIP21=$(echo "${SWAP_RESULT}" | jq -r '.bip21 // empty')

# compute actual fee from the prepared transaction
TX_OUT_MSAT=$(echo "${REAL_RESP}" | jq -r '.txid' > /dev/null && echo "${UTXO_AMTMSAT}")
ACTUAL_SEND_SAT=$(echo "${REAL_RESP}" | jq -r '.amount_msat // empty' | sed 's/msat$//')
if [ -n "${ACTUAL_SEND_SAT}" ] && [ "${ACTUAL_SEND_SAT}" != "null" ]; then
  ACTUAL_SEND_SAT=$((ACTUAL_SEND_SAT / 1000))
  ACTUAL_FEE_SAT=$((UTXO_AMTSAT - ACTUAL_SEND_SAT))
else
  ACTUAL_SEND_SAT=${SEND_SAT}
  ACTUAL_FEE_SAT=${FEE_SAT}
fi

# === Step 4: Final summary - user must confirm to broadcast ===
SUMMARY="REVIEW ALL DETAILS BEFORE BROADCAST:\n\n"
SUMMARY+="UTXO:          ${UTXO_TXID}:${UTXO_VOUT}\n"
SUMMARY+="UTXO amount:   ${UTXO_AMTSAT} sats\n"
SUMMARY+="Miner fee:     ${ACTUAL_FEE_SAT} sats\n"
SUMMARY+="Send amount:   ${ACTUAL_SEND_SAT} sats\n\n"
SUMMARY+="Swap ID:       ${SWAP_ID}\n"
SUMMARY+="Deposit addr:  ${BOLTZ_ADDRESS}\n"
if [ -n "${SWAP_INVOICE}" ]; then
  SUMMARY+="Invoice:       ${SWAP_INVOICE:0:40}...\n"
fi
if [ -n "${SWAP_BIP21}" ]; then
  SUMMARY+="BIP21:         ${SWAP_BIP21:0:40}...\n"
fi
SUMMARY+="\nPrepared TXID: ${REAL_TXID}\n"
if [ -n "${REAL_PSBT}" ]; then
  SUMMARY+="PSBT:          ${REAL_PSBT:0:40}...\n"
fi
SUMMARY+="\n>>> Press YES to BROADCAST the transaction <<<\n"
SUMMARY+=">>> Press NO to CANCEL and roll back <<<"

whiptail --title " Boltz Sweep [4/4] - Confirm Broadcast " \
  --yesno "${SUMMARY}" 28 75 \
  --yes-button "BROADCAST" --no-button "CANCEL"

if [ $? -ne 0 ]; then
  echo "# User cancelled. Rolling back ..."
  ${CL} -k txdiscard txid="${REAL_TXID}" 2>/dev/null
  unreserve_utxo
  whiptail --title " Boltz Sweep " --msgbox "Cancelled. Transaction discarded and UTXO unreserved.\nThe Boltz swap will expire automatically." 9 65
  exit 0
fi

# === Broadcast ===
echo "# Broadcasting transaction ..."

SEND_RESP=$(${CL} -k txsend txid="${REAL_TXID}" 2>&1)
if [ $? -ne 0 ]; then
  ${CL} -k txdiscard txid="${REAL_TXID}" 2>/dev/null
  whiptail --title " Boltz Sweep " --msgbox "txsend failed:\n${SEND_RESP}" 12 70
  exit 1
fi

# === Success ===
SUCCESS_TEXT="Transaction broadcast successfully!\n\n"
SUCCESS_TEXT+="TX ID:\n${REAL_TXID}\n\n"
SUCCESS_TEXT+="Swap ID:  ${SWAP_ID}\n"
SUCCESS_TEXT+="Amount:   ${ACTUAL_SEND_SAT} sats\n\n"
SUCCESS_TEXT+="The swap will complete automatically once the\n"
SUCCESS_TEXT+="on-chain transaction confirms (usually 1 block).\n\n"
SUCCESS_TEXT+="Monitor with: boltzcli listswaps"

whiptail --title " Boltz Sweep - Done! " --msgbox "${SUCCESS_TEXT}" 18 76
exit 0
