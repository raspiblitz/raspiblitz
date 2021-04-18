#!/bin/bash

# https://github.com/lightninglabs/lightning-terminal/releases
LITVERSION="0.4.1-alpha"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Lightning Terminal Service on or off"
 echo "installs the version $LITVERSION"
 echo "bonus.lit.sh [on|off|menu]"
 exit 1
fi

# check who signed the release in https://github.com/lightninglabs/lightning-terminal/releases
PGPsigner="guggero" 
if [ $PGPsigner=guggero ];then
  PGPpkeys="https://keybase.io/guggero/pgp_keys.asc"
  PGPcheck="03DB6322267C373B"
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
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Lightning Terminal " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:8443\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for the Tor Browser (see LCD for QR):
https://${toraddress}\n
For the command line switch to 'lit' user with: 'sudo su - lit'
use the commands: 'lncli', 'lit-loop', 'lit-pool' and 'lit-frcli'.
" 19 74
    /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " Lightning Terminal " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:8443\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.\n
For the command line switch to 'lit' user with: 'sudo su - lit'
use the commands: 'lncli', 'lit-loop', 'lit-pool' and 'lit-frcli'.
" 19 63
  fi
  echo "please wait ..."
  exit 0
fi

# stop services
echo "making sure the lit service is not running"
sudo systemctl stop litd 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# INSTALL LIGHTNING TERMINAL"

  # switching off single installs of pool, loop or faraday if installed
  if [ "${loop}" = "on" ]; then
      echo "# Replacing single install of: LOOP"
      /home/admin/config.scripts/bonus.loop.sh off
  fi
  if [ "${pool}" = "on" ]; then
      echo "# Replacing single install of: POOL"
      /home/admin/config.scripts/bonus.pool.sh off
  fi
  if [ "${faraday}" = "on" ]; then
      echo "# Replacing single install of: FARADAY"
      /home/admin/config.scripts/bonus.faraday.sh off
  fi
  
  isInstalled=$(sudo ls /etc/systemd/system/litd.service 2>/dev/null | grep -c 'litd.service')
  if [ ${isInstalled} -eq 0 ]; then
 
    # create dedicated user
    sudo adduser --disabled-password --gecos "" lit || exit 1

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
    # move old data if present
    sudo mv /home/lit/.lit /mnt/hdd/app-data/ 2>/dev/null
    echo "# make sure the data directory exists"
    sudo mkdir -p /mnt/hdd/app-data/.lit
    echo "# symlink"
    sudo rm -rf /home/lit/.lit # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/.lit/ /home/lit/.lit
    sudo chown lit:lit -R /mnt/hdd/app-data/.lit

    echo "# move the standalone Loop and Pool data to LiT"
    echo "# Loop"
    # move old data if present
    sudo mv /home/loop/.loop /mnt/hdd/app-data/ 2>/dev/null
    echo "# remove so can't be used parallel with LiT"
    config.scripts/bonus.loop.sh off
    echo "# make sure the data directory exists"
    sudo mkdir -p /mnt/hdd/app-data/.loop
    echo "# symlink"
    sudo rm -rf /home/lit/.loop # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/.loop/ /home/lit/.loop
    sudo chown lit:lit -R /mnt/hdd/app-data/.loop
    
    echo "# Pool"
    echo "# remove so can't be used parallel with LiT"
    config.scripts/bonus.pool.sh off
    echo "# make sure the data directory exists"
    sudo mkdir -p /mnt/hdd/app-data/.pool
    echo "# symlink"
    sudo rm -rf /home/lit/.pool # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/.pool/ /home/lit/.pool
    sudo chown lit:lit -R /mnt/hdd/app-data/.pool

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

    downloadDir="/home/admin/download/lit"  # edit your download directory
    rm -rf "${downloadDir}"
    mkdir -p "${downloadDir}"
    cd "${downloadDir}" || exit 1

    # extract the SHA256 hash from the manifest file for the corresponding platform
    wget -N https://github.com/lightninglabs/lightning-terminal/releases/download/v${LITVERSION}/manifest-v${LITVERSION}.txt
    if [ ${isARM} -eq 1 ] ; then
      OSversion="armv7"
    elif [ ${isAARCH64} -eq 1 ] ; then
      OSversion="arm64"
    elif [ ${isX86_64} -eq 1 ] ; then
      OSversion="amd64"
    fi 
    SHA256=$(grep -i "linux-$OSversion" manifest-v$LITVERSION.txt | cut -d " " -f1)

    echo
    echo "# LiT v${LITVERSION} for ${OSversion}"
    echo "# SHA256 hash: $SHA256"
    echo
    echo "# get LiT binary"
    binaryName="lightning-terminal-linux-${OSversion}-v${LITVERSION}.tar.gz"
    wget -N https://github.com/lightninglabs/lightning-terminal/releases/download/v${LITVERSION}/${binaryName}

    echo "# check binary was not manipulated (checksum test)"
    wget -N https://github.com/lightninglabs/lightning-terminal/releases/download/v${LITVERSION}/manifest-${PGPsigner}-v${LITVERSION}.sig
    wget --no-check-certificate ${PGPpkeys}
    binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
    if [ "${binaryChecksum}" != "${SHA256}" ]; then
      echo "!!! FAIL !!! Downloaded LiT BINARY not matching SHA256 checksum: ${SHA256}"
      exit 1
    fi

    echo "# check gpg finger print"
    gpg --keyid-format LONG ./pgp_keys.asc
    fingerprint=$(gpg --keyid-format LONG "./pgp_keys.asc" 2>/dev/null \
    | grep "${PGPcheck}" -c)
    if [ ${fingerprint} -lt 1 ]; then
      echo ""
      echo "!!! BUILD WARNING --> LiT PGP author not as expected"
      echo "Should contain PGP: ${PGPcheck}"
      echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
      read key
    fi
    gpg --import ./pgp_keys.asc
    sleep 3
    verifyResult=$(gpg --verify manifest-${PGPsigner}-v${LITVERSION}.sig manifest-v${LITVERSION}.txt 2>&1)
    goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
    echo "goodSignature(${goodSignature})"
    correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
    echo "correctKey(${correctKey})"
    if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
      echo ""
      echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
      exit 1
    fi
    ###########
    # install #
    ###########
    tar -xzf ${binaryName}
    sudo install -m 0755 -o root -g root -t /usr/local/bin lightning-terminal-linux-${OSversion}-v${LITVERSION}/*

    ###########
    # config  #
    ###########
    if [ "${runBehindTor}" = "on" ]; then
      echo "# Connect to the Pool server through Tor"
      LOOPPROXY="loop.server.proxy=127.0.0.1:9050"
      POOLPROXY="pool.proxy=127.0.0.1:9050"
    else
      echo "# Connect to Pool and Loop server through clearnet"
      LOOPPROXY=""
      POOLPROXY=""
    fi
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    echo "
# Application Options
httplisten=0.0.0.0:8442
httpslisten=0.0.0.0:8443
uipassword=$PASSWORD_B
#letsencrypt=true
#letsencrypthost=loop.merchant.com
lit-dir=/home/lit/.lit

# Remote options
remote.lit-debuglevel=debug

# Remote lnd options
remote.lnd.rpcserver=127.0.0.1:10009
remote.lnd.macaroonpath=/home/lit/.lnd/data/chain/${network}/${chain}net/admin.macaroon
remote.lnd.tlscertpath=/home/lit/.lnd/tls.cert

# Loop
loop.loopoutmaxparts=5
$LOOPPROXY

# Pool
pool.newnodesonly=true
$POOLPROXY

# Faraday
faraday.min_monitored=48h

# Faraday - bitcoin
faraday.connect_bitcoin=true
faraday.bitcoin.host=localhost
faraday.bitcoin.user=raspibolt
faraday.bitcoin.password=$PASSWORD_B
" | sudo tee /mnt/hdd/app-data/.lit/lit.conf

    # secure
    sudo chown lit:lit /mnt/hdd/app-data/.lit/lit.conf
    sudo chmod 600 /mnt/hdd/app-data/.lit/lit.conf | exit 1

    ############
    # service  #
    ############
    # sudo nano /etc/systemd/system/litd.service
    echo "
[Unit]
Description=litd Service
After=lnd.service

[Service]
ExecStart=/usr/local/bin/litd
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
    echo "# The Lightning Terminal is already installed."
  fi

  # aliases
  echo "
alias lit-loop=\"loop --rpcserver=localhost:8443 \
  --tlscertpath=/home/lit/.lit/tls.cert \
  --macaroonpath=/home/lit/.loop/${chain}net/loop.macaroon\"
alias lit-pool=\"pool --rpcserver=localhost:8443 \
  --tlscertpath=/home/lit/.lit/tls.cert \
  --macaroonpath=/home/lit/.pool/${chain}net/pool.macaroon\"
alias lit-frcli=\"frcli --rpcserver=localhost:8443 \
  --tlscertpath=/home/lit/.lit/tls.cert \
  --macaroonpath=/home/lit/.faraday/${chain}net/faraday.macaroon\"
" | sudo tee -a /home/lit/.bashrc

  # open ports on firewall
  sudo ufw allow 8443 comment "Lightning Terminal"

  # setting value in raspi blitz config
  sudo sed -i "s/^lit=.*/lit=on/g" /mnt/hdd/raspiblitz.conf
  
  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh lit 443 8443
  fi

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the litd.service is enabled, system is ready so starting service"
    sudo systemctl start litd
  else
    echo "# OK - the litd.service is enabled, to start manually use: 'sudo systemctl start litd'"
  fi

  # make Loop work with RTL if installed (update will run configRTL)
  if [ ${#rtlWebinterface} -gt 0 ]&&[ ${rtlWebinterface} = on ];then
    /home/admin/config.scripts/bonus.rtl.sh update
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
    # delete Go package
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
  