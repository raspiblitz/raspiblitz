#!/bin/bash
# RaspiBolt LND Mainnet: script to get public ip address
# /usr/local/bin/getpublicip.sh

echo 'getpublicip.sh started, writing public IP address every 10 minutes into /run/publicip'
while [ 0 ];
    do
    torExists=$(sudo ls /mnt/hdd/tor/web80/hostname 2>/dev/null | grep hostname -c)
    if [ ${torExists} -eq 1 ]; then
      # use tor onion address
      # printf "PUBLICIP=$(sudo cat /mnt/hdd/tor/lnd9735/hostname)\n" > /run/publicip;
      # just leave /run/publicip
    else
      # get public IP
      printf "PUBLICIP=$(curl -vv ipinfo.io/ip 2> /run/publicip.log)\n" > /run/publicip;
    fi
    sleep 600
done;