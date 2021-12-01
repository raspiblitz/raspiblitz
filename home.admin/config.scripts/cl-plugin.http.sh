#!/bin/bash

# https://github.com/Start9Labs/c-lightning-http-plugin/commits/master
clHTTPpluginVersion="1dbb6537e0ec5fb9b8edde10db6b4cc613ccdb19"

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install, remove, connect the c-lightning-http-plugin"
  echo "version: $clHTTPpluginVersion"
  echo "Implemented for mainnet only."
  echo "Usage:"
  echo "cl-plugin.http.sh [on|off|connect] <norestart>"
  echo
  exit 1
fi

PGPsigner="web-flow"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="4AEE18F83AFDEB23"

# source <(/home/admin/config.scripts/network.aliases.sh getvars cl <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cl mainnet)

# add default value to raspi config if needed
configEntry="clHTTPplugin"
configEntryExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "${configEntry}")
if [ "${configEntryExists}" == "0" ]; then
  echo "# adding default config entry for '${configEntry}'"
  sudo /bin/sh -c "echo '${configEntry}=off' | tee -a  /mnt/hdd/raspiblitz.conf"
else
  echo "# default config entry for '${configEntry}' exists"
fi

if [ $1 = connect ];then
  toraddress=$(sudo cat /mnt/hdd/tor/clHTTPplugin/hostname)
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  # https://github.com/rootzoll/raspiblitz/issues/2579#issuecomment-936091256
  # http://rpcuser:rpcpassword@xxx.onion:9080
  url="http://lightning:${PASSWORD_B}@${toraddress}:9080"
  clear
  echo
  /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
  echo "
Connect Fully Noded

In Fully Noded go to 'Settings' > 'Node Manager' > +, from there you will be automatically prompted to add a node:

    add a label
    add the rpc user: lightning
    add the rpc password is your Password_B
    add the onion address (also shown on the display as a QR and below), ensure you add the port at the end: 
    ${toraddress}:9080"

    qrencode -t ANSIUTF8 "${toraddress}:9080"

    echo "
    ignore the macaroon and cert as that is for LND only

Thats it, Fully Noded will now automatically use those credentials for any lightning related functionality. 
You can only have one lightning node at a a time, to add a new one just overwrite the existing credentials.

In Fully Noded you will see lightning bolt zap buttons in a few places, tap them to see what they do.

Find the most up-to-date version of this info at:
https://github.com/Fonta1n3/FullyNoded/blob/master/Docs/Lightning.md#connect-fully-noded
"
  echo
  echo "# Press enter to continue to show the full connection URL with all the info above"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
  /home/admin/config.scripts/blitz.display.sh qr "${url}"
  clear
  echo "
C-lightning connection URL code for Fully Noded:
The string shown is:
$url
"
  qrencode -t ANSIUTF8 "${url}"
  echo
  echo "# Press enter to hide the QRcode from the LCD"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
  exit 0
fi

if [ "$1" = "on" ];then

  echo
  echo "# Installing Rust for the bitcoin user"
  echo
  sudo -u bitcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u bitcoin sh -s -- -y

  if [ ! -f /home/bitcoin/cl-plugins-available/c-lightning-http-plugin ];then
    sudo -u bitcoin mkdir /home/bitcoin/cl-plugins-available
    cd /home/bitcoin/cl-plugins-available || exit 1 
    sudo -u bitcoin git clone https://github.com/Start9Labs/c-lightning-http-plugin.git
    cd c-lightning-http-plugin || exit 1
    sudo -u bitcoin git reset --hard ${clHTTPpluginVersion} || exit 1

    sudo -u bitcoin /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

    echo
    echo "# change CL REST port to 9080"
    sudo sed -i "s/8080/9080/g" src/rpc.rs
    echo
    sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo build --release
    sudo chmod a+x /home/bitcoin/cl-plugins-available/c-lightning-http-plugin/target/release/c-lightning-http-plugin
  fi

  if [ ! -L /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ];then
    sudo ln -s /home/bitcoin/cl-plugins-available/c-lightning-http-plugin/target/release/c-lightning-http-plugin \
               /home/bitcoin/cl-plugins-enabled
  fi

  ##########
  # Config #
  ##########
  if ! grep -Eq "^http-pass=" ${CLCONF};then
    echo "# Editing ${CLCONF}"
    echo "# See: https://github.com/Fonta1n3/FullyNoded/blob/master/Docs/Lightning.md#setup-c-lightning-http-plugin"
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    echo "
http-pass=${PASSWORD_B}
" | sudo tee -a ${CLCONF}
  
  else
    echo "# clHTTPplugin is already configured in ${CLCONF}"
  fi

  # hidden service to https://xx.onion
  /home/admin/config.scripts/internet.hiddenservice.sh clHTTPplugin 9080 9080

  # setting value in raspi blitz config
  sudo sed -i "s/^clHTTPplugin=.*/clHTTPplugin=on/g" /mnt/hdd/raspiblitz.conf

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ] && [ "$2" != "norestart" ]; then
    echo "# Restart the lightningd.service to activate clHTTPplugin"
    sudo systemctl restart lightningd
  fi

  echo "# clHTTPplugin was installed"
  echo "# Monitor with:"
  echo "sudo journalctl | grep clHTTPplugin | tail -n5"
  echo "sudo tail -n 100 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log | grep clHTTPplugin"

fi

if [ "$1" = "off" ];then
  # delete symlink
  sudo rm -rf /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin

  echo "# Editing ${CLCONF}"
  sudo sed -i "/^http-pass/d" ${CLCONF}

  echo "# Restart the lightningd.service to deactivate clHTTPplugin"
  sudo systemctl restart lightningd

  /home/admin/config.scripts/internet.hiddenservice.sh off clHTTPplugin

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin"
    sudo rm -rf /home/bitcoin/cl-plugins-available/c-lightning-http-plugin
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^clHTTPplugin=.*/clHTTPplugin=off/g" /mnt/hdd/raspiblitz.conf
  echo "# clHTTPplugin was uninstalled"

fi
