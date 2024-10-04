#!/bin/bash

# script to create a self-signed SSL certificate

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to create a self-signed SSL certificate"
  echo "internet.selfsignedcert.sh [create|reset]"
  exit 1
fi

# make sure the HDD is mounted
mountpoint -q /mnt/hdd || { echo "# internet.selfsignedcert.sh - /mnt/hdd is not mounted. Exiting."; exit 1; }

CERT_DIR="/mnt/hdd/app-data/selfsignedcert"
CERT_FILE="${CERT_DIR}/selfsigned.cert"

create_self_signed_cert() {

  sudo mkdir -p "${CERT_DIR}"
  sudo chown -R bitcoin:bitcoin "${CERT_DIR}"
  cd /mnt/hdd/app-data/selfsignedcert || exit 1

  echo "# Create a self signed SSL certificate"
  localip=$(hostname -I | awk '{print $1}')

  sudo -u bitcoin openssl genrsa -out selfsigned.key 2048
  #https://www.humankode.com/ssl/create-a-selfsigned-certificate-for-nginx-in-5-minutes
  #https://stackoverflow.com/questions/8075274/is-it-possible-making-openssl-skipping-the-country-common-name-prompts

  echo "
[req]
prompt             = no
default_bits       = 2048
default_keyfile    = selfsigned.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca

[req_distinguished_name]
C = US
ST = Texas
L = Lightning Network
O = RaspiBlitz
#OU = Org Unit Name
CN = RaspiBlitz
#emailAddress = info@example.com

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1   = localhost
DNS.2   = 127.0.0.1
DNS.3   = $localip
" | sudo -u bitcoin tee localhost.conf

  sudo -u bitcoin openssl req -new -x509 -sha256 -key selfsigned.key \
    -out selfsigned.cert -days 3650 -config localhost.conf

  # set permissions on cert & key
  sudo chown -h admin:www-data $CERT_DIR/selfsigned.cert
  sudo chown -h admin:www-data $CERT_DIR/selfsigned.key 

  # reolad nginx
  sudo systemctl reload nginx 2>/dev/null
}

check_certificate_validity() {
  if openssl x509 -checkend 86400 -noout -in "${CERT_FILE}"; then
    echo "# The certificate is valid for more than one day, keeping it."
    return 0
  else
    echo "# The certificate is invalid, expired or will expire within a day. Regenerating."
    return 1
  fi
}

if [ "$1" = create ]; then
  if [[ -f "${CERT_DIR}/selfsigned.cert" && -f "${CERT_DIR}/selfsigned.key" ]]; then
    # if certificate exists, check if it is still valid
    if ! check_certificate_validity; then
      create_self_signed_cert
    fi
  else
    # the certificate doesn't exist, so create it
    create_self_signed_cert
  fi
  exit 0
fi

if [ "$1" = reset ]; then
  echo "# Make sure the old certificate is not present"
  sudo rm -f "${CERT_DIR}/selfsigned.cert"
  sudo rm -f "${CERT_DIR}/selfsigned.key"
  create_self_signed_cert
  /home/admin/config.scripts/internet.letsencrypt.sh refresh-nginx-certs
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
