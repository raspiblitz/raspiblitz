#!/bin/bash

# script to create a self-signed SSL certificate

sudo -u bitcoin mkdir /mnt/hdd/app-data/selfsignedcert
cd /mnt/hdd/app-data/selfsignedcert || exit 1

echo "# Create a self signed SSL certificate"
localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

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
