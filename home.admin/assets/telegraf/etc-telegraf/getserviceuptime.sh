#!/bin/bash
#

###############################################################################
#   File:   getserviceuptime.sh
#   Date:   2020-10-02
###############################################################################

# collect the service uptimes into variables
# some of the variables may contain "" as the pidof/pgrep may fail due to non-existens of that process
#
 bitcoind_uptime=$(ps -p `pidof bitcoind`                   -o etimes='' 2>/dev/null | tr -d '[:space:]')
      lnd_uptime=$(ps -p `pidof lnd`                        -o etimes='' 2>/dev/null | tr -d '[:space:]')
  electrs_uptime=$(ps -p `pidof electrs`                    -o etimes='' 2>/dev/null | tr -d '[:space:]')
 telegraf_uptime=$(ps -p `pidof telegraf`                   -o etimes='' 2>/dev/null | tr -d '[:space:]')
     sshd_uptime=$(ps -p `pgrep -f /usr/sbin/sshd`          -o etimes='' 2>/dev/null | tr -d '[:space:]')
      rtl_uptime=$(ps -p `pgrep -f RTL`                     -o etimes='' 2>/dev/null | tr -d '[:space:]')
 btcrpexp_uptime=$(ps -p `pgrep -f "sh -c node ./bin/www"`  -o etimes='' 2>/dev/null | tr -d '[:space:]')

# whenever a variable contains a valid integer...spit out a line in influx-line-format
# (see https://stackoverflow.com/a/19116862 for details "Test whether string is a valid integer")
#
if [ "$bitcoind_uptime" -eq "$bitcoind_uptime" ] 2>/dev/null; then echo "service_uptime,service=bitcoind uptime=${bitcoind_uptime}i";           fi
if [      "$lnd_uptime" -eq      "$lnd_uptime" ] 2>/dev/null; then echo "service_uptime,service=lnd uptime=${lnd_uptime}i";                     fi
if [  "$electrs_uptime" -eq  "$electrs_uptime" ] 2>/dev/null; then echo "service_uptime,service=electrs uptime=${electrs_uptime}i";             fi
if [ "$telegraf_uptime" -eq "$telegraf_uptime" ] 2>/dev/null; then echo "service_uptime,service=telegraf uptime=${telegraf_uptime}i";           fi
if [     "$sshd_uptime" -eq     "$sshd_uptime" ] 2>/dev/null; then echo "service_uptime,service=sshd uptime=${sshd_uptime}i";                   fi
if [      "$rtl_uptime" -eq      "$rtl_uptime" ] 2>/dev/null; then echo "service_uptime,service=RTL uptime=${rtl_uptime}i";                     fi
if [ "$btcrpexp_uptime" -eq "$btcrpexp_uptime" ] 2>/dev/null; then echo "service_uptime,service=btcrpcexplorer uptime=${btcrpexp_uptime}i";     fi

# -eof-
