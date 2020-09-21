#!/bin/bash

if [ $# -eq 0 ]; then
 echo "script to set and config TLS Cert for LND"
 echo "lnd.tlscert.sh refresh"
 echo "lnd.tlscert.sh ip-add [ip]"
 echo "lnd.tlscert.sh ip-remove [ip|ALL]"
 echo "lnd.tlscert.sh domain-add [domain]"
 echo "lnd.tlscert.sh domain-remove [domain|ALL]"
 exit 1
fi

TLSPATH="/mnt/hdd/lnd"
LNDCONF="/mnt/hdd/lnd/lnd.conf"

### ADD IP

if [ "$1" = "ip-add" ]; then 

  echo "# lnd.tlscert.sh $1"
  
  # 2. parameter: ip
  ip=$2
  if [ ${#ip} -eq 0 ]; then
    echo "error='missing parameter'"
    exit
  fi

  # check if IP is already added
  found=$(sudo cat ${LNDCONF} | grep -c "tlsextraip=${ip}")
  if [ ${found} -gt 0 ]; then
    echo "# OK the IP was already added lnd.conf"
    exit
  fi

  # simply add the line to the LND conf
  sudo sed -i "10itlsextraip=${ip}" ${LNDCONF}

  # check if line is added
  found=$(sudo cat ${LNDCONF} | grep -c "tlsextraip=${ip}")
  if [ ${found} -eq 0 ]; then
    echo "error='failed adding tlsextraip'"
    exit
  fi

  echo "# OK added tlsextraip to lnd.conf - refresh of TLS cert is needed"
  exit
fi

### REMOVE IP

if [ "$1" = "ip-remove" ]; then 

  echo "# lnd.tlscert.sh $1"

  # 2. parameter: ip
  ip=$2
  if [ ${#ip} -eq 0 ]; then
    echo "error='missing parameter'"
    exit
  fi

  if [ "${ip}" == "ALL" ]; then
    echo "# removing all tlsextraip entries"
    sudo sed -i "/tlsextraip=*/d" ${LNDCONF}
    ip=""
  else
    echo "# removing tlsextraip=${ip}"
    sudo sed -i "/tlsextraip=${ip}/d" ${LNDCONF}
  fi

  # check if line is removed
  found=$(sudo cat ${LNDCONF} | grep -c "tlsextraip=${ip}")
  if [ ${found} -gt 0 ]; then
    echo "error='failed removing tlsextraip'"
    exit
  fi

  echo "# OK removed tlsextraip from lnd.conf - refresh of TLS cert is needed"
  exit
fi

### ADD DOMAIN

if [ "$1" = "domain-add" ]; then 

  echo "# lnd.tlscert.sh $1"

  # 2. parameter: domain
  domain=$2
  if [ ${#domain} -eq 0 ]; then
    echo "error='missing parameter'"
    exit
  fi

  # check if IP is already added
  found=$(sudo cat ${LNDCONF} | grep -c "tlsextradomain=${domain}")
  if [ ${found} -gt 0 ]; then
    echo "# OK the domain was already added lnd.conf"
    exit
  fi

  # simply add the line to the LND conf
  sudo sed -i "10itlsextradomain=${domain}" ${LNDCONF}

  # check if line is added
  found=$(sudo cat ${LNDCONF} | grep -c "tlsextradomain=${domain}")
  if [ ${found} -eq 0 ]; then
    echo "error='failed adding tlsextradomain'"
    exit
  fi

  echo "# OK added tlsextradomain to lnd.conf - refresh of TLS cert is needed"
  exit
fi

### REMOVE DOMAIN

if [ "$1" = "domain-remove" ]; then 

  echo "# lnd.tlscert.sh $1"

  # 2. parameter: domain
  domain=$2
  if [ ${#domain} -eq 0 ]; then
    echo "error='missing parameter'"
    exit
  fi

  if [ "${domain}" == "ALL" ]; then
    echo "# removing all tlsextradomain entries"
    sudo sed -i "/tlsextradomain=*/d" ${LNDCONF}
    ip=""
  else
    echo "# removing tlsextradomain=${domain}"
    sudo sed -i "/tlsextradomain=${domain}/d" ${LNDCONF}
  fi

  # check if line is removed
  found=$(sudo cat ${LNDCONF} | grep -c "tlsextradomain=${domain}")
  if [ ${found} -gt 0 ]; then
    echo "error='failed removing tlsextradomain'"
    exit
  fi

  echo "# OK removed tlsextradomain from lnd.conf - refresh of TLS cert is needed"
  exit
fi

### REFRESH

if [ "$1" = "refresh" ]; then 

  echo "# checking if LND is running"
  lndInactive=$(sudo systemctl is-active lnd | grep -c "inactive")
  if [ ${lndInactive} -eq 1 ]; then
    echo "# FAIL: lnd.tlscert.sh refresh"
    echo "error='LND systemd service not activated'"
    exit 1
  fi

  echo "# making sure services are not running"
  sudo systemctl stop lnd 2>/dev/null

  echo "# keep old tls data as backup"
  sudo rm ${TLSPATH}/tls.cert.old 2>/dev/null
  sudo rm ${TLSPATH}/tls.key.old 2>/dev/null
  sudo mv ${TLSPATH}/tls.cert ${TLSPATH}/tls.cert.old 
  sudo mv ${TLSPATH}/tls.key ${TLSPATH}/tls.key.old 

  echo "# start to create new generate new TLSCert"
  sudo systemctl start lnd
  echo "# wait until generated"
  newCertExists=0
  count=0
  while [ ${newCertExists} -eq 0 ]
  do
    count=$(($count + 1))
    echo "# (${count}/60) check for cert"
    if [ ${count} -gt 60 ]; then
      sudo systemctl stop lnd
      echo "error='failed to generate new LND cert'"
      exit 1
    fi
    newCertExists=$(sudo ls /mnt/hdd/lnd/tls.cert 2>/dev/null | grep -c '.cert')
    sleep 2
  done

  # stop lnd and let outside decide to restart or not
  sudo systemctl stop lnd
  sudo chmod 664 ${TLSPATH}/tls.cert
  sudo chown bitcoin:bitcoin "/mnt/hdd/lnd/tls.cert"

  echo "# symlink new cert to lnd app-data directory"
  if ! [[ -L "/mnt/hdd/app-data/lnd/tls.cert" ]]; then
    sudo rm -rf "/mnt/hdd/app-data/lnd/tls.cert"               # not a symlink.. delete it silently
    sudo ln -s ${TLSPATH}/tls.cert /home/admin/.lnd/tls.cert   # and create symlink
  fi
  echo "# OK TLS certs are fresh - start of LND service needed"
  exit
fi




