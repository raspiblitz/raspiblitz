#!/bin/bash

pinnedVersion="0.4.0-alpha"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Lightning Terminal Service on or off"
 echo "installs the version $pinnedVersion"
 echo "bonus.lit.sh [on|off|menu]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^lit=" /mnt/hdd/raspiblitz.conf; then
  echo "lit=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/lit/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /home/lit/.lit/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " Lightning Terminal " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:8443\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for the Tor Browser (see LCD for QR):\nhttps://${toraddress}
" 16 74
    /home/admin/config.scripts/blitz.lcd.sh hide
  else
    # Info without TOR
    whiptail --title " Lightning Terminal " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:8443\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 16 63
  fi
  echo "please wait ..."
  exit 0
fi

# stop services
echo "making sure the lit service is not running"
sudo systemctl stop litd 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# INSTALL LIGHTNING TERMINAL ***"
  
  isInstalled=$(sudo ls /etc/systemd/system/litd.service 2>/dev/null | grep -c 'litd.service')
  if [ ${isInstalled} -eq 0 ]; then
 
    # create dedicated user
    sudo adduser --disabled-password --gecos "" lit

    # make sure symlink to central app-data directory exists
    sudo rm -rf /home/lit/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/lit/.lnd"

    # sync all macaroons and unix groups for access
    /home/admin/config.scripts/lnd.credentials.sh sync
    # macaroons will be checked after install

    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin lit
    # add user to group with readonly access on lnd
    sudo /usr/sbin/usermod --append --groups lndreadonly lit
    # add user to group with invoice access on lnd
    sudo /usr/sbin/usermod --append --groups lndinvoice lit
    # add user to groups with all macaroons
    sudo /usr/sbin/usermod --append --groups lndinvoices lit
    sudo /usr/sbin/usermod --append --groups lndchainnotifier lit
    sudo /usr/sbin/usermod --append --groups lndsigner lit
    sudo /usr/sbin/usermod --append --groups lndwalletkit lit
    sudo /usr/sbin/usermod --append --groups lndrouter lit

    echo "# persist settings in app-data"
    echo "# make sure the data directory exists"
    sudo mkdir -p /mnt/hdd/app-data/.lit
    echo "# symlink"
    sudo rm -rf /home/lit/.lit # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/.lit/ /home/pool/.lit
    sudo chown lit:lit -R /mnt/hdd/app-data/.lit

    # check who signed the release in https://github.com/lightninglabs/lightning-terminal/releases
    # guggero
    PGPpkeys="https://keybase.io/guggero/pgp_keys.asc"
    PGPcheck="F4FC70F07310028424EFC20A8E4256593F177720"
    downloadDir="/home/admin/download/lit"  # edit your download directory

    echo "Detect CPU architecture ..." 
    isARM=$(uname -m | grep -c 'arm')
    isAARCH64=$(uname -m | grep -c 'aarch64')
    isX86_64=$(uname -m | grep -c 'x86_64')
    if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ]; then
      echo "!!! FAIL !!!"
      echo "Can only build on ARM, aarch64, x86_64 or i386 not on:"
      uname -m
      exit 1
    else
    echo "OK running on $(uname -m) architecture."
    fi

    rm -rf "${downloadDir}"
    mkdir -p "${downloadDir}"
    cd "${downloadDir}" || exit 1

    # extract the SHA256 hash from the manifest file for the corresponding platform
    wget -N https://github.com/lightninglabs/lightning-terminal/releases/download/v${pinnedVersion}/manifest-v${pinnedVersion}.txt
    if [ ${isARM} -eq 1 ] ; then
      OSversion="armv7"
    elif [ ${isAARCH64} -eq 1 ] ; then
      OSversion="arm64"
    elif [ ${isX86_64} -eq 1 ] ; then
      OSversion="amd64"
    fi 
    SHA256=$(grep -i "linux-$OSversion" manifest-v$pinnedVersion.txt | cut -d " " -f1)

    echo
    echo "*** LiT v${pinnedVersion} for ${OSversion} ***"
    echo "SHA256 hash: $SHA256"
    echo

    echo "# get LiT binary"
    binaryName="lightning-terminal-linux-${OSversion}-v${pinnedVersion}.tar.gz"
    wget -N https://github.com/lightninglabs/lightning-terminal/releases/download/v${pinnedVersion}/${binaryName}

    echo "# check binary was not manipulated (checksum test)"
    wget -N https://github.com/lightninglabs/lightning-terminal/releases/download/v${pinnedVersion}/manifest-v${pinnedVersion}.txt.asc
    sudo rm -rf pgp_keys.asc 
    wget --no-check-certificate ${PGPpkeys}
    binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
    if [ "${binaryChecksum}" != "${SHA256}" ]; then
      echo "!!! FAIL !!! Downloaded LiT BINARY not matching SHA256 checksum: ${SHA256}"
      exit 1
    fi

    echo "# check gpg finger print"
    gpg ./pgp_keys.asc
    fingerprint=$(sudo gpg "./pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
    if [ ${fingerprint} -lt 1 ]; then
      echo ""
      echo "!!! BUILD WARNING --> LiT PGP author not as expected"
      echo "Should contain PGP: ${PGPcheck}"
      echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
      read key
    fi
    gpg --import ./pgp_keys.asc
    sleep 3
    verifyResult=$(gpg --verify manifest-v${pinnedVersion}.txt.asc 2>&1)
    goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
    echo "goodSignature(${goodSignature})"
    correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
    echo "correctKey(${correctKey})"
    if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
      echo ""
      echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
      exit 1
    fi

    # install
    tar -xzf ${binaryName}
    sudo install -m 0755 -o root -g root -t /usr/local/bin lightning-terminal-linux-${OSversion}-v${pinnedVersion}/*

    # sudo nano /etc/systemd/system/litd.service
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-) 
    echo "
[Unit]
Description=litd Service
After=lnd.service

[Service]
ExecStart=/usr/local/bin/litd \
--httpslisten=0.0.0.0:8443 \
--uipassword=$PASSWORD_B \
--lnd.bitcoin.active \
--lnd.bitcoin.mainnet \
--lnd.bitcoin.node=bitcoind \
--lnd.bitcoind.rpchost=localhost \
--lnd.bitcoind.rpcuser=raspibolt \
--lnd.bitcoind.rpcpass=$PASSWORD_B \
--loop.loopoutmaxparts=5 \
--faraday.min_monitored=48h

User=lit
Group=lit
Type=simple
KillMode=process
TimeoutSec=60
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
" | sudo tee -a /etc/systemd/system/litd.service
    sudo systemctl enable litd
    echo "OK - the Lightning lit service is now enabled"

  else 
    echo "lit service already installed."
  fi

  # open ports on firewall
  sudo ufw allow 8443 comment "Lightning Terminal"

  # setting value in raspi blitz config
  sudo sed -i "s/^lit=.*/lit=on/g" /mnt/hdd/raspiblitz.conf
  
  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh lit 443 8443
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^lit=.*/lit=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/litd.service 2>/dev/null | grep -c 'litd.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING LIT ***"
    # remove the systemd service
    sudo systemctl stop litd
    sudo systemctl disable litd
    sudo rm /etc/systemd/system/litd.service
    # delete user 
    sudo userdel -rf lit
    # close ports on firewall
    sudo ufw deny 8443
    # delete Go packages
    sudo rm /usr/local/bin/lit
    sudo rm /usr/local/bin/litd
    echo "# OK, the lit.service is removed."
    # Hidden Service if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      /home/admin/config.scripts/internet.hiddenservice.sh off lit
    fi
  else 
    echo "# LiT is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run normal again"
exit 1
  