#!/bin/bash

# SOURCE: https://github.com/gcomte/ln-gems/blob/master/showTotalLightningBalance.sh

##############################################################################
# COLORING
##############################################################################

YELLOW=`tput setaf 3`
RESET=`tput sgr0`
GREEN=`tput setaf 2`
RED=`tput setaf 1`

##############################################################################
# CALCULATIONS
##############################################################################

LN_REMOTE_BALANCE=$(lncli listchannels | jq -r '.[][].remote_balance' | awk '{s+=$1} END {print s}')
LN_LOCAL_BALANCE=$(lncli listchannels | jq -r '.[][].local_balance' | awk '{s+=$1} END {print s}')
LN_TOTAL_BALANCE=$((LN_REMOTE_BALANCE + LN_LOCAL_BALANCE))
LN_COMMIT_FEES=$(lncli listchannels | jq -r '.[][] | select(.initiator==true) | .commit_fee' | awk '{s+=$1} END {print s}')
LN_INVOICES=$(lncli listinvoices | jq -r '.invoices[] | select(.settled==true) | .value' | awk '{s+=$1} END {print s}')
LN_PAYMENTS=$(lncli listpayments | jq -r '.payments[] | select(.status=="SUCCEEDED") | .value' | awk '{s+=$1} END {print s}')
LN_PAYMENTS_FEES=$(lncli listpayments | jq -r '.payments[] | select(.status=="SUCCEEDED") | .fee' | awk '{s+=$1} END {print s}')
LN_EARNED_FEES_IN_MSATS=$(lncli fwdinghistory 0 | jq -r '.forwarding_events[] | .fee_msat' | awk '{s+=$1} END {print s}')
LN_EARNED_FEES_IN_SATS=$((LN_EARNED_FEES_IN_MSATS / 1000))

ONCHAIN_FUNDS_CONFIRMED=$(lncli walletbalance | jq -r '.confirmed_balance')
ONCHAIN_FUNDS_UNCONFIRMED=$(lncli walletbalance | jq -r '.unconfirmed_balance')
ONCHAIN_FUNDS_TOTAL=$(lncli walletbalance | jq -r '.total_balance')


ONCHAIN_FUNDS_CONFIRMED_BTC=$(printf %.3f\\n "$((ONCHAIN_FUNDS_CONFIRMED))e-8")
ONCHAIN_FUNDS_UNCONFIRMED_BTC=$(printf %.3f\\n "$((ONCHAIN_FUNDS_UNCONFIRMED))e-8")
ONCHAIN_FUNDS_TOTAL_BTC=$(printf %.3f\\n "$((ONCHAIN_FUNDS_TOTAL))e-8")
ONCHAIN_TX=$(lncli listchaintxns | jq -r '.transactions[] | .amount' | awk '{s+=$1} END {print s}')
ONCHAIN_TX_FEES=$(lncli listchaintxns | jq -r '.transactions[] | .total_fees' | awk '{s+=$1} END {print s}')

LN_LOCAL_BALANCE_PERCENTAGE=$((100 * LN_LOCAL_BALANCE / LN_TOTAL_BALANCE))
LN_REMOTE_BALANCE_PERCENTAGE=$((100 * LN_REMOTE_BALANCE / LN_TOTAL_BALANCE))
TOTAL_BALANCE_PERCENTAGE=100

ONCHAIN_FUNDS_CONFIRMED_PERCENTAGE=$((100 * ONCHAIN_FUNDS_CONFIRMED / ONCHAIN_FUNDS_TOTAL))
ONCHAIN_FUNDS_UNCONFIRMED_PERCENTAGE=$((100 * ONCHAIN_FUNDS_UNCONFIRMED / ONCHAIN_FUNDS_TOTAL))

TOTAL_BALANCE=$((ONCHAIN_FUNDS_TOTAL + LN_LOCAL_BALANCE))

CONTROL_SUM=$((\
  ONCHAIN_FUNDS_CONFIRMED\
  + ONCHAIN_FUNDS_UNCONFIRMED\
  + ONCHAIN_TX_FEES
  + LN_LOCAL_BALANCE\
  + LN_COMMIT_FEES\
  - LN_INVOICES\
  + LN_PAYMENTS\
  + LN_PAYMENTS_FEES
  - LN_EARNED_FEES_IN_SATS
))

PROFIT_AND_LOSS=$((LN_EARNED_FEES_IN_SATS - ONCHAIN_TX_FEES))
LN_SPEND=$((LN_PAYMENTS + LN_PAYMENTS_FEES))

##############################################################################
# Sats to BTC 
##############################################################################

TOTAL_BALANCE_BTC=$(printf %.3f\\n "$(($TOTAL_BALANCE))e-8")
LN_LOCAL_BALANCE_BTC=$(printf %.3f\\n "$(($LN_LOCAL_BALANCE))e-8")
LN_REMOTE_BALANCE_BTC=$(printf %.3f\\n "$(($LN_REMOTE_BALANCE))e-8")
LN_TOTAL_BALANCE_BTC=$(printf %.3f\\n "$(($LN_TOTAL_BALANCE))e-8")
LN_INVOICES_BTC=$(printf %.3f\\n "$(($LN_INVOICES))e-8")
LN_COMMIT_FEES_BTC=$(printf %.3f\\n "$(($LN_COMMIT_FEES))e-8")
LN_PAYMENTS_BTC=$(printf %.3f\\n "$(($LN_PAYMENTS))e-8")
LN_PAYMENTS_FEES_BTC=$(printf %.3f\\n "$(($LN_PAYMENTS_FEES))e-8")

##############################################################################
# PRINT 
##############################################################################

# turn '0 sats' into '0.000 sats' to keep table nicely formatted
if [ $LN_LOCAL_BALANCE -eq 0 ]; then
    LN_LOCAL_BALANCE="0.000"
fi
if [ $LN_REMOTE_BALANCE -eq 0 ]; then
    LN_REMOTE_BALANCE="0.000"
fi
if [ $LN_COMMIT_FEES -eq 0 ]; then
    LN_COMMIT_FEES="0.000"
fi
if [ $LN_INVOICES -eq 0 ]; then
    LN_INVOICES="0.000"
fi
if [ $LN_PAYMENTS -eq 0 ]; then
    LN_PAYMENTS="0.000"
fi
if [ $LN_PAYMENTS_FEES -eq 0 ]; then
    LN_PAYMENTS_FEES="0.000"
fi
if [ $ONCHAIN_FUNDS_CONFIRMED -eq 0 ]; then
    ONCHAIN_FUNDS_CONFIRMED="0.000"
fi
if [ $ONCHAIN_FUNDS_UNCONFIRMED -eq 0 ]; then
    ONCHAIN_FUNDS_UNCONFIRMED="0.000"
fi

echo -e "\n${YELLOW}LN BALANCE${RESET}"
echo -e "LOCAL\t\tREMOTE\t\tTOTAL"
echo -e "--------------\t---------------\t---------------"
echo -e "$LN_LOCAL_BALANCE sats\t$LN_REMOTE_BALANCE sats\t$LN_TOTAL_BALANCE sats"
echo -e "$LN_LOCAL_BALANCE_BTC BTC\t$LN_REMOTE_BALANCE_BTC BTC\t$LN_TOTAL_BALANCE_BTC BTC"
echo -e "$LN_LOCAL_BALANCE_PERCENTAGE%\t\t$LN_REMOTE_BALANCE_PERCENTAGE%\t\t$TOTAL_BALANCE_PERCENTAGE%"

echo -e "\n${YELLOW}ON-CHAIN BALANCE${RESET}"
echo -e "CONFIRMED\tUNCONFIRMED\tTOTAL"
echo -e "--------------\t---------------\t---------------"
echo -e "$ONCHAIN_FUNDS_CONFIRMED sats\t$ONCHAIN_FUNDS_UNCONFIRMED sats\t$ONCHAIN_FUNDS_TOTAL sats"
echo -e "$ONCHAIN_FUNDS_CONFIRMED_BTC BTC\t$ONCHAIN_FUNDS_UNCONFIRMED_BTC BTC\t$ONCHAIN_FUNDS_TOTAL_BTC BTC"
echo -e "$ONCHAIN_FUNDS_CONFIRMED_PERCENTAGE%\t\t$ONCHAIN_FUNDS_UNCONFIRMED_PERCENTAGE%\t\t$TOTAL_BALANCE_PERCENTAGE%"

echo -e "\n${YELLOW}OWNED BALANCE [LN + ON-CHAIN]${RESET}"
echo -e "$TOTAL_BALANCE sats | $TOTAL_BALANCE_BTC BTC\n"

echo -e "---------------------------------------------"
echo -e "ON-CHAIN CONFIRMED           $(printf %10s $ONCHAIN_FUNDS_CONFIRMED) sats"
echo -e "ON-CHAIN UNCONFIRMED         $(printf %10s $ONCHAIN_FUNDS_UNCONFIRMED) sats"
echo -e "ON-CHAIN FEES                ${RED}$(printf %10s "-$ONCHAIN_TX_FEES")${RESET} sats"
echo -e "---------------------------------------------"
echo -e "LN LOCAL BALANCE             $(printf %10s $LN_LOCAL_BALANCE) sats"
echo -e "LN LOCKED IN COMMIT FEES     $(printf %10s $LN_COMMIT_FEES) sats"
echo -e "LN INVOICES (RECEIVED)       $(printf %10s $LN_INVOICES) sats"
echo -e "LN PAYMENTS (PAID)           $(printf %10s "-$LN_PAYMENTS") sats"
echo -e "LN PAYMENTS FEES             $(printf %10s "-$LN_PAYMENTS_FEES") sats"
echo -e "LN EARNED (FORWARD) FEES     ${GREEN}$(printf %10s $LN_EARNED_FEES_IN_SATS)${RESET} sats"
echo -e "---------------------------------------------"

if [ $PROFIT_AND_LOSS -gt 0 ]; then
  COLORED_PNL=${GREEN}$(printf %10s "$PROFIT_AND_LOSS")${RESET}
else
  COLORED_PNL=${RED}$(printf %10s "$PROFIT_AND_LOSS")${RESET}
fi

echo -e "${YELLOW}PROFIT AND LOSS${RESET}              $COLORED_PNL sats"
echo -e "---------------------------------------------"
echo -e "CONTROL SUM                  $(printf %10s $CONTROL_SUM) sats"
echo -e "LN SPEND                     $(printf %10s $LN_SPEND) sats"
echo -e ""