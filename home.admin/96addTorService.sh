#!/bin/bash

# https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
# will output: "Codename: stretch" -.- always...
# codename="$(lsb_release -c)" |  cut -c11-
torrc="/etc/tor/torrc"

function uncommentTorrcRelayBitcoinOnly {
	echo "uncommenting #RunAsDaemon 1"
	sudo sed -i "s/^#RunAsDaemon 1/RunAsDaemon 1/g" $torrc
	echo "adding PortForward 1 & ControlPort 9051 after RunAsDaemon 1"
	sudo sed -i '\|RunAsDaemon 1| {N;s|\n$|\nPortForwarding 1\nControlPort 9051\n|}' $torrc
	echo "uncommenting #CookieAuthentication 1"
	sudo sed -i "s/^#CookieAuthentication 1/CookieAuthentication 1/g" $torrc 
	echo "adding CookieAuthFileGroupReadable 1 after CookieAuthentication 1"
	sudo sed -i '\|CookieAuthentication 1| {N;s|\n$|\nCookieAuthFileGroupReadable 1\n|}' $torrc
	echo "*** enabling logs of tor to /var/log/tor/notices.log ***"
	sudo sed -i "s/^#Log notice file/Log notice file/g" $torrc 

	echo "configured tor"
}

function torOnlyToBitcoinConf {
	sudo echo "onlynet=onion" >> /home/bitcoin/.bitcoin/bitcoin.conf
}

echo "adding Tor sources to sources.list"
echo "deb http://deb.torproject.org/torproject.org stretch main" | sudo tee -a /etc/apt/sources.list
echo "deb-src http://deb.torproject.org/torproject.org stretch main" | sudo tee -a /etc/apt/sources.list

echo "installing dirmngr"
sudo apt install dirmngr
## lopp: gpg --keyserver keys.gnupg.net --recv 886DDD89
echo "Fetching GPG key"
gpg --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -
sudo apt-get update
echo "install Tor"
sudo apt install tor tor-arm -y
uncommentTorrcRelayBitcoinOnly

# todo: ask to act as relay

# ask: only connect via tor?

dialog --title "Tor outgoing only" \
--backtitle "Raspiblitz - Tor Setup Script" \
--yesno "Do you want to serve Bitcoin data ONLY to Tor nodes (.onion)?" 7 60

# Get exit status
response=$?
case $response in
   0) torOnlyToBitcoinConf && echo "serving onion nodes only";;
   1) echo "serving clear and onion nodes";;
   255) echo "[ESC] key pressed.";;
esac


sudo systemctl restart tor@default

# so that Bitcoind can create Tor hidden service
echo "setting bitcoind permissions"
sudo usermod -a -G debian-tor bitcoin

# so that you can run `arm` as user 
sudo usermod -a -G debian-tor pi

# restarting bitcoind to start with tor
echo "restarting bitcoind, wait 60 seconds"
sudo systemctl restart bitcoind
sleep 60