#!/bin/bash
#

###############################################################################
#   File:   getraspiblitzipinfo.sh
#   Date:   2020-09-30
###############################################################################

# set the "debugLevel"
debugLevel=0
writeMemoryfile=1


# get the seconds since UNIX epoch
unixTimestamp=$(date +"%s")

# get active network device (eth0 or wlan0)
networkDevice=$(ip addr | grep -v "lo:" | grep 'state UP' | tr -d " " | cut -d ":" -f2 | head -n 1)

# create the indexed array "origin" an fill it
# this also creates the "Enumeration"
#   0       <=>     publicIP
#   1       <=>     bitcoind
#   2       <=>     lnd
#   3       <=>     IPv6
#   4       <=>     IPv4
#
declare -a origin
origin=(publicIP bitcoind lnd IPv6 IPv4)
##

#
# further we need the arrays
declare -a ip_addr_curr
declare -a ip_addr_prev
declare -a creation_ts_curr
declare -a creation_ts_prev
declare -a has_changed


# load local config (but should also work if not available)
source /mnt/hdd/raspiblitz.conf 2>/dev/null



# get the "public IP addresses" from various sources/origins
#   [0]     ->   publicIP    (remove square barckets in case of IPv6)
#   [1]     ->   bitcoind
#   [2]     ->   lnd
#   [3]     ->   IPv6 at local network interface (eth0 or wlan0)
#   [4]     ->   IPv4 at local network interface (eth0 or wlan0)
ip_addr_curr[0]=$(echo "${publicIP}" | tr -d '[]')
ip_addr_curr[1]=$(/usr/local/bin/bitcoin-cli  -conf=/mnt/hdd/bitcoin/bitcoin.conf  getnetworkinfo | jq -r ".localaddresses[0].address" 2>/dev/null)
ip_addr_curr[2]=$(/usr/local/bin/lncli  --lnddir=/mnt/hdd/app-data/lnd  getinfo | jq -r ".uris[0]" 2>/dev/null | cut -d'@' -f2 | rev | cut -d':' -f2- | rev | tr -d '[]')
ip_addr_curr[3]=$(ip -o -6 address show scope global up dev ${networkDevice} 2>/dev/null | cut -d'/' -f1 | awk '/inet6/{print $4}' | head -n 1)
ip_addr_curr[4]=$(ip -o -4 address show scope global up dev ${networkDevice} 2>/dev/null | cut -d'/' -f1 | awk '/inet/{print $4}' | head -n 1)
#
if [ ${debugLevel} -gt 10 ]; then

    for i in $( seq 0 4 ); do
        printf "  %2d: %-10s  = %s\n" "$i" "${origin[ $i ]}" "${ip_addr_curr[ $i ]}" ;
    done
fi


# get the values from a prior run, that file will not be changes as long as all the values stay the same
memoryFile=/mnt/hdd/temp/raspiblitzipinfo.out
source ${memoryFile} 2>/dev/null

# prepare to count the changes
changes=0

# initialize the array of the previous IP addresses from the memory file
for i in $( seq 0 4 ); do

    # compose the name of the memory variable
    s="${origin[ $i ]}_old"

    # assign the prev address array emement with content of that variable
    ip_addr_prev[ $i ]=${!s}

    # if the variable is still empty, fill it with "N/A"
    if [ "ip_addr_prev[ $i ]" == "" ]; then ip_addr_prev[ $i ]="N/A" ; fi 

    if [ ${debugLevel} -gt 10 ]; then printf "  %2d: read into          ip_addr_prev[%d] from memoryfile variable %30s = %s\n" "$i" "$i" "$s" "${ip_addr_prev[ $i ]}" ; fi
done


# initialize the Creation TimeStamps with their old values from the memory file
# so it is guaranteed that they contain a proper value if that IP does not change
# otherwise the "unixTimestamp" will be written if a change is detected
for i in $( seq 0 4 ); do

    # compose the name of the memory variable
    s="${origin[ $i ]}_CreationTS_old"

    # get the content of that variable
    # and sanitzie if necessary
    val=${!s}
    if [ "${val}" == "" ]; then val=-1 ; fi

    # assign the current and prev timestamp array emements with content of that variable
    creation_ts_curr[ $i ]=${val}
    creation_ts_prev[ $i ]=${val}

    if [ ${debugLevel} -gt 10 ]; then printf "  %2d: read into creation_ts_curr/prev[%d] from memoryfile variable %30s = %s\n" "$i" "$i" "$s" "${creation_ts_curr[ $i ]}" ; fi
done


# initialize the "has_changed" flag array
for i in $( seq 0 4 ); do
    has_changed[ $i ]=0
done


# check for changes...
# whenever a change is detected the current time will be written into the respective Creation TimeStamp variable
# Additionally the "changes" counter will be incremented
for i in $( seq 0 4 ); do
    if [ "${ip_addr_curr[$i]}" != "${ip_addr_prev[$i]}" ]; then
        ((changes++))
        has_changed[ $i ]=1
        creation_ts_curr[ $i ]=${unixTimestamp}

        if [ ${debugLevel} -gt  0 ]; then printf "  %2d: IP addr change detected for %10s: %40s (new) != %40s (old)\n" "$i" "${origin[ $i ]}" "${ip_addr_curr[$i]}" "${ip_addr_prev[$i]}" ; fi
    else

        if [ ${debugLevel} -gt 10 ]; then printf "  %2d: IP addr --NOT changed-- for %10s: %40s (new) == %40s (old)\n" "$i" "${origin[ $i ]}" "${ip_addr_curr[$i]}" "${ip_addr_prev[$i]}" ; fi
    fi
done


# IF at least one value of the memory file needs to be updated, the whole file will be rewritten.
# the "..._CreationTS" variables will contain their "..._CreationTS_old" counter part (if nothing has changed)
# or "${unixTimestamp}" if that particular IP address has been changed
#
if [ ${changes} -gt 0 ]; then

    if [ ${debugLevel} -gt  0 ]; then  echo "*** IP change detected, writing memoryfile ${memoryFile} ***" ; fi

    if [ ${writeMemoryfile} -eq 1 ]; then
        # truncate file and write header
        echo "#############################################################"        >   ${memoryFile}
        echo "# RaspiBlitz IP address memory file."                                 >>  ${memoryFile}
        echo "# created by script %{$0}"                                            >>  ${memoryFile}
        echo "#############################################################"        >>  ${memoryFile}
        echo " "                                                                    >>  ${memoryFile}
        #
        # write a section for each entry in the "origin" array
        for i in $( seq 0 4 ); do
            echo "# section ${origin[ $i ]}"                                        >>  ${memoryFile}
            echo "${origin[ $i ]}_old=${ip_addr_curr[$i]}"                          >>  ${memoryFile}
            echo "${origin[ $i ]}_CreationTS_old=${creation_ts_curr[ $i ]}"         >>  ${memoryFile}
            echo " "                                                                >>  ${memoryFile}
        done
    else
        # display info on stdout
        echo ""
        echo "writeMemoryfile=off      =>  show changes"
        echo ""
        echo "#############################################################"
        echo "# RaspiBlitz IP address memory file."
        echo "# created by script %{$0}"
        echo "#############################################################"
        echo " "

        for i in $( seq 0 4 ); do
            echo "# section ${origin[ $i ]}"
            echo "${origin[ $i ]}_old=${ip_addr_curr[$i]}"
            echo "${origin[ $i ]}_CreationTS_old=${creation_ts_curr[ $i ]}"
            echo " "
        done
    fi
else
    if [ ${debugLevel} -gt  0 ]; then  echo "*** no IP change detected, do nothing... ***" ; fi
fi


# now create the output for the telegraf "[[inputs.exec]]" section in influx-line-format
#
# measurement:  raspiblitz_ip_info
#
# tags
#   *   host
#   *   origin
#   *   ipaddr
#   *   ipaddr_prev
#   *   ipaddr_changed
#
# fileds
#   *   created
#   *   uptime
#   *   changed
#
for i in $( seq 0 4 ); do

    ipaddr_online=$(( ${unixTimestamp} - ${creation_ts_curr[ $i ]}))
    echo "raspiblitz_ip_info,origin=${origin[ $i ]},ipaddr=${ip_addr_curr[$i]},ipaddr_prev=${ip_addr_prev[$i]},ipaddr_changed=${has_changed[ $i ]} created=${creation_ts_curr[ $i ]}i,uptime=${ipaddr_online}i,changed=${has_changed[ $i ]}i"
done

# -eof-
