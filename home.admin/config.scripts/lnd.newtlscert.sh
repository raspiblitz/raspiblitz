#!/bin/bash

# stop services
echo "making sure services are not running"
sudo systemctl stop lnd 2>/dev/null

echo "keep old tls data as backup"
sudo mv /mnt/hdd/lnd/tls.cert /mnt/hdd/lnd/tls.cert.old 
sudo mv /mnt/hdd/lnd/tls.key /mnt/hdd/lnd/tls.key.old 

echo "let lnd generate new TLSCert"
sudo -u bitcoin /usr/local/bin/lnd &>/dev/null &
echo "wait until generated"
newCertExists=0
count=0
while [ ${newCertExists} -eq 0 ]
do
  count=$(($count + 1))
  echo "(${count}/60) check for cert"
  if [ ${count} -gt 60 ]; then
    echo "FAIL - was not able to generate new LND certs"
    exit 1
  fi
  newCertExists=$(sudo ls /mnt/hdd/lnd/tls.cert 2>/dev/null | grep -c '.cert')
  sleep 2
done
sudo killall /usr/local/bin/lnd
sudo chmod 664 /mnt/hdd/lnd/tls.cert
sudo chown bitcoin:bitcoin "/mnt/hdd/lnd/tls.cert"
echo "symlink new cert to lnd app-data directory"
if ! [[ -L "/mnt/hdd/app-data/lnd/tls.cert" ]]; then
  sudo rm -rf "/mnt/hdd/app-data/lnd/tls.cert"               # not a symlink.. delete it silently
  sudo ln -s /mnt/hdd/lnd/tls.cert /home/admin/.lnd/tls.cert # and create symlink
fi
echo "OK TLS certs are fresh"

# ToDo(frennkie) why doesn't this start lnd again? - I assume as _background will start it anyway?!
# ToDo(frennkie) the way LND generates the x509 certificate is not ideal -
#   it may be better to simply run openssl and create a cert with ou settings...
