#!/bin/bash

# set version (change if update is available)
# https://github.com/ElementsProject/elements/releases
VERSION="elements-23.2.1"
SIG_PUBKEY="BD0F3062F87842410B06A0432F656B0610604482" # Pablo Greco <pgreco@blockstream.com>

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "bonus.elements.sh install"
  echo "bonus.elements.sh [on|off]"
  echo "bonus.elements.sh addI2pSeedNodes"
  echo "Installs $VERSION by default"
  echo
  exit 1
fi

echo "# Running: bonus.elements.sh $*"

source /mnt/hdd/raspiblitz.conf
# elementslogpath
elementslogpath="/home/elements/.elements/liquidv1/debug.log"

function addAlias {
  echo "# Add aliases elements-cli, elementslog"
  sudo -u admin touch /home/admin/_aliases
  if ! grep "alias elements-cli" /home/admin/_aliases; then
    echo "alias elements-cli=\"sudo -u elements /usr/local/bin/elements-cli -conf=/home/elements/.elements/elements.conf\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias elementslog" /home/admin/_aliases; then
    echo "alias elementslog=\"sudo -u elements tail -n 30 -f ${elementslogpath}\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias elementsconf" /home/admin/_aliases; then
    echo "alias elementsconf=\"sudo nano /home/elements/.elements/elements.conf\"" |
      sudo tee -a /home/admin/_aliases
  fi
  sudo chown admin:admin /home/admin/_aliases
}

function installBinary {
  echo "*** PREPARING ELEMENTS ***"
  sudo adduser --system --group --shell /bin/bash --home /home/elements elements
  # copy the skeleton files for login
  sudo -u elements cp -r /etc/skel/. /home/elements/

  # add to tor group
  sudo adduser elements debian-tor

  # prepare directories
  sudo rm -rf /home/admin/download
  sudo -u admin mkdir -p /home/admin/download/elements
  cd /home/admin/download/elements || exit 1

  echo "# Receive signer key"
  gpg --recv-key ${SIG_PUBKEY} || exit 1

  # download signed binary sha256 hash sum file
  sudo -u admin wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS https://github.com/ElementsProject/elements/releases/download/${VERSION}/SHA256SUMS
  # download the signed binary sha256 hash sum file and check
  sudo -u admin wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS.asc https://github.com/ElementsProject/elements/releases/download/${VERSION}/SHA256SUMS.asc

  if gpg --verify SHA256SUMS.asc; then
    echo
    echo "****************************************"
    echo "OK --> ELEMENTS MANIFEST IS CORRECT"
    echo "****************************************"
    echo
  else
    echo
    echo "# BUILD FAILED --> the PGP verification failed"
    exit 1
  fi

  # elementsOSversion
  if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
    elementsOSversion="arm-linux-gnueabihf"
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
    elementsOSversion="aarch64-linux-gnu"
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
    elementsOSversion="x86_64-linux-gnu"
  fi

  echo
  echo "*** ELEMENTS v${VERSION} for ${elementsOSversion} ***"

  # download resources
  binaryName="${VERSION}-${elementsOSversion}.tar.gz"
  if [ ! -f "./${binaryName}" ]; then
    echo "# Downloading https://github.com/ElementsProject/elements/releases/download/${VERSION}/${binaryName} ..."
    sudo -u admin wget --quiet https://github.com/ElementsProject/elements/releases/download/${VERSION}/${binaryName}
  fi
  if [ ! -f "./${binaryName}" ]; then
    echo "# FAIL # Could not download the ELEMENTS BINARY"
    exit 1
  else

    # check binary checksum test
    echo "- checksum test"
    # get the sha256 value for the corresponding platform from signed hash sum file
    elementsSHA256=$(grep -i "${binaryName}" SHA256SUMS | cut -d " " -f1)
    binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
    echo "Valid SHA256 checksum should be: ${elementsSHA256}"
    echo "Downloaded binary SHA256 checksum: ${binaryChecksum}"
    if [ "${binaryChecksum}" != "${elementsSHA256}" ]; then
      echo "# FAIL # Downloaded ELEMENTS BINARY not matching SHA256 checksum: ${elementsSHA256}"
      rm -v ./${binaryName}
      exit 1
    else
      echo
      echo "********************************************"
      echo "OK --> VERIFIED ELEMENTS BINARY CHECKSUM"
      echo "********************************************"
      echo
      sleep 10
      echo
    fi
  fi

  # install
  sudo -u admin tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ ${VERSION}/bin/*
  sleep 3
  if ! sudo /usr/local/bin/elementsd --version | grep "Elements Core version"; then
    echo
    echo "# BUILD FAILED --> Was not able to install ${VERSION}"
    exit 1
  fi

  addAlias

  echo "- Elements install OK"
}

function removeService() {
  if [ -f "/etc/systemd/system/elementsd.service" ]; then
    /usr/local/bin/elements-cli stop
    sudo systemctl stop elementsd
    sudo systemctl disable elementsd
    sudo rm /etc/systemd/system/elementsd.service 2>/dev/null
    echo "# Elements service is stopped and disabled"
  fi
}

function installService() {
  echo "# Prepare directories"
  # symlink to elements home
  sudo mkdir -p /mnt/hdd/app-data/.elements
  # symlink
  sudo rm -rf /home/elements/.elements # clean first
  sudo ln -s /mnt/hdd/app-data/.elements /home/elements/
  sudo chown -R elements:elements /mnt/hdd/app-data/.elements
  sudo chown -R elements:elements /home/elements/

  echo "# Installing Elements"
  # elements.conf
  if [ ! -f /home/elements/.elements/elements.conf ]; then
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    echo "
# Elementsd configuration
datadir=/mnt/hdd/app-data/.elements
walletdir=/mnt/hdd/app-data/.elements/liquidv1/wallets
rpcuser=raspiblitz
rpcpassword=$PASSWORD_B
rpcbind=127.0.0.1

# Bitcoin Core credentials
mainchainrpcuser=raspibolt
mainchainrpcpassword=$PASSWORD_B

# Peer connection settings
onlynet=onion
proxy=127.0.0.1:9050
debug=tor

onlynet=i2p
i2psam=127.0.0.1:7656
i2pacceptincoming=1
debug=i2p

# initial sync does not work without clearnet
# disable when synced
onlynet=ipv4
onlynet=ipv6
" | sudo -u elements tee /home/elements/.elements/elements.conf
  else
    echo "# /home/elements/.elements/elements.conf is present"
  fi

  removeService

  # /etc/systemd/system/elementsd.service
  # based on https://github.com/elements/elements/blob/master/contrib/init/elementsd.service
  echo "
[Unit]
Description=Elements daemon

[Service]
Environment='MALLOC_ARENA_MAX=1'
ExecStart=/usr/local/bin/elementsd -daemonwait -conf=/mnt/hdd/app-data/.elements/elements.conf
PermissionsStartOnly=true

# Process management
####################
Type=forking
Restart=on-failure
TimeoutStartSec=infinity
TimeoutStopSec=600

# Directory creation and permissions
####################################
# Run as elements:elements
User=elements
Group=elements

StandardOutput=null
StandardError=journal

# Hardening measures
####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Deny access to /home, /root and /run/user
ProtectHome=true
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/elementsd.service
  sudo systemctl daemon-reload
  sudo systemctl enable elementsd
  echo "# OK - the elementsd.service is now enabled"

  addAlias

  source <(/home/admin/_cache.sh get state)

  if [ "${state}" == "ready" ]; then
    echo "# OK - the elementsd.service is enabled, system is ready so starting service"
    sudo systemctl start elementsd
  else
    echo "# OK - the elementsdservice is enabled, to start manually use:"
    echo "sudo systemctl start elementsd"
  fi

  isInstalled=$(systemctl status elementsd | grep -c active)
  if [ $isInstalled -gt 0 ]; then
    echo "# Installed $(sudo -u elements elementsd --version | grep version)"
    echo
    echo "# Monitor the elementsd with:"
    echo "# sudo tail -f /home/elements/.elements/debug.log"
    echo
  else
    echo "# Installation failed"
    echo "# See:"
    echo "# sudo journalctl -fu elementsd"
    exit 1
  fi
}

# install
if [ "$1" = "install" ]; then

  installBinary

  exit 0

# switch on
elif [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ ! -f /usr/local/bin/elementsd ] || [ ! -d /home/elements ]; then

    installBinary

  fi

  installService

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set elements "on"
  exit 0

# switch off
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstall Elements"

  removeService

  sudo userdel -rf elements
  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set elements "off"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
