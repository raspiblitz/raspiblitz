#!/bin/bash

# links:
# https://github.com/JoinMarket-Org/joinmarket-clientserver#quickstart---recommended-installation-method-linux-only
# https://github.com/openoms/bitcoin-tutorials/tree/master/joinmarket
# https://github.com/openoms/joininbox

# https://github.com/openoms/joininbox/tags
JBTAG="v0.7.4" # installs JoinMarket v0.9.8

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "JoinMarket install script to install and switch JoinMarket on or off"
  echo "sudo /home/admin/config.scrips/bonus.joinmarket.sh install"
  echo "sudo /home/admin/config.scrips/bonus.joinmarket.sh on|off"
  echo "Installs JoininBox $JBTAG with JoinMarket v0.9.5"
  exit 1
fi

# show info menu
if [ "$1" = "menu" ]; then
  whiptail --title " JoinMarket info " \
  --yes-button "Start Joininbox" \
  --no-button "Cancel" \
  --yesno "Usage notes:
https://github.com/openoms/bitcoin-tutorials/blob/master/joinmarket/README.md

Can also type: 'jm' in the command line to switch to the dedicated user,
and start the JoininBox menu.
" 11 81
  if [ $? -eq 0 ]; then
    sudo su - joinmarket
  fi
  exit 0
fi

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit
fi

PGPsigner="openoms"
PGPpubkeyLink="https://github.com/openoms.gpg"
PGPpubkeyFingerprint="13C688DB5B9C745DE4D2E4545BFB77609B081B65"

source /mnt/hdd/raspiblitz.conf 2>/dev/null

# switch on
if [ "$1" = "install" ]; then
  echo "# INSTALL JOINMARKET"

  if [ -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ]; then
    echo "JoinMarket is already installed"
  else
    echo "# cleaning before install"
    sudo userdel -rf joinmarket 2>/dev/null

    echo "# add the 'joinmarket' user"
    adduser --disabled-password --gecos "" joinmarket

    # add to sudo group (required for installation)
    adduser joinmarket sudo || exit 1

    # configure sudo for usage without password entry for the joinmarket user
    echo 'joinmarket ALL=(ALL) NOPASSWD:ALL' | EDITOR='tee -a' visudo

    # make a folder for authorized keys
    sudo -u joinmarket mkdir -p /home/joinmarket/.ssh
    chmod -R 700 /home/joinmarket/.ssh

    # install the command-line fuzzy finder (https://github.com/junegunn/fzf)
    bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/joinmarket/.bashrc"

    echo "# adding JoininBox"
    sudo rm -rf /home/joinmarket/joininbox
    sudo -u joinmarket git clone https://github.com/openoms/joininbox.git /home/joinmarket/joininbox
    # check the latest at:
    cd /home/joinmarket/joininbox || exit 1
    # https://github.com/openoms/joininbox/releases/
    sudo -u joinmarket git reset --hard ${JBTAG}
    sudo -u joinmarket /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${JBTAG}" || exit 1

    # copy the scripts in place
    sudo -u joinmarket cp /home/joinmarket/joininbox/scripts/* /home/joinmarket/
    sudo -u joinmarket cp /home/joinmarket/joininbox/scripts/.* /home/joinmarket/ 2>/dev/null
    sudo chmod +x /home/joinmarket/*.sh

    echo "# Set ssh access off with the joinmarket user"
    sudo /home/joinmarket/set.ssh.sh off

    # Tor config
    # add the joinmarket user to the Tor group
    usermod -a -G debian-tor joinmarket
    # fix Tor config
    sudo sed -i "s:^CookieAuthFile*:#CookieAuthFile:g" /etc/tor/torrc
    if ! grep -Eq "^CookieAuthentication 1" /etc/tor/torrc; then
      echo "CookieAuthentication 1" | sudo tee -a /etc/tor/torrc
      sudo systemctl reload tor@default
    fi
    if ! grep -Eq "^AllowOutboundLocalhost 1" /etc/tor/torsocks.conf; then
      echo "AllowOutboundLocalhost 1" | sudo tee -a /etc/tor/torsocks.conf
      sudo systemctl reload tor@default
    fi
  
    # joinin.conf settings
    sudo -u joinmarket touch /home/joinmarket/joinin.conf
    sudo -u joinmarket sed -i "s/^runBehindTor=.*/runBehindTor=on/g" /home/joinmarket/joinin.conf

    echo
    echo "##########"
    echo "# Extras #"
    echo "##########"
    echo
    # install a command-line fuzzy finder (https://github.com/junegunn/fzf)
    apt -y install fzf
    bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> \
    /home/joinmarket/.bashrc"

    # install tmux
    apt -y install tmux

    echo "##############################################"
    echo "# Install JoinMarket and configure JoininBox #"
    echo "##############################################"
    echo
    if sudo -u joinmarket /home/joinmarket/install.joinmarket.sh -i install; then
      echo "# Installed JoinMarket"
      echo "# Run: 'sudo /home/admin/config.scrips/bonus.joinmarket.sh on' to configure and switch on"
    else
      echo " Failed to install JoinMarket"
      exit 1
    fi
  fi
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if running Tor
  if [ "${runBehindTor}" = "on" ]; then
    echo "# OK, running behind Tor"
  else
    echo "# Not running Tor"
    echo "# Activate Tor from the SERVICES menu before installing JoinMarket."
    exit 1
  fi

  # set password B
  echo "# setting PASSWORD_B as the password for the 'joinmarket' user"
  PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
  echo "joinmarket:$PASSWORD_B" | sudo chpasswd

  if [ -f /home/joinmarket/start.joininbox.sh ]; then
    echo "# Ok, Joininbox is present"
  else
    sudo /home/admin/config.scrips/bonus.joinmarket.sh install
  fi

  # make sure the Bitcoin Core wallet is on
  /home/admin/config.scripts/network.wallet.sh on
  if [ $(/usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf listwallets | grep -c wallet.dat) -eq 0 ];then
    echo "# Create a non-descriptor wallet.dat"
    /usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf -named createwallet wallet_name=wallet.dat descriptors=false
  else
    isDescriptor=$(/usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf -rpcwallet=wallet.dat getwalletinfo | grep -c '"descriptors": true,')
    if [ "$isDescriptor" -gt 0 ]; then
      # unload
      bitcoin-cli unloadwallet wallet.dat
      echo "# Move the wallet.dat with descriptors to /mnt/hdd/bitcoin/descriptors"
      sudo mv /mnt/hdd/bitcoin/wallet.dat /mnt/hdd/bitcoin/descriptors
      echo "# Create a non-descriptor wallet.dat"
      bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf -named createwallet wallet_name=wallet.dat descriptors=false
    else
      echo "# The non-descriptor wallet.dat is loaded in bitcoind."
    fi
  fi

  # store JoinMarket data on HDD
  mkdir /mnt/hdd/app-data/.joinmarket 2>/dev/null

  # copy old JoinMarket data to app-data
  cp -rf /home/admin/joinmarket-clientserver/scripts/wallets /mnt/hdd/app-data/.joinmarket/ 2>/dev/null
  chown -R joinmarket:joinmarket /mnt/hdd/app-data/.joinmarket
  ln -s /mnt/hdd/app-data/.joinmarket /home/joinmarket/ 2>/dev/null
  chown -R joinmarket:joinmarket /home/joinmarket/.joinmarket
  # specify wallet.dat in old config for multiwallet for multiwallet support
  if [ -f "/home/joinmarket/.joinmarket/joinmarket.cfg" ] ; then
    sudo -u joinmarket sed -i "s/^rpc_wallet_file =.*/rpc_wallet_file = wallet.dat/g" \
    /home/joinmarket/.joinmarket/joinmarket.cfg
    echo "# specified to use wallet.dat in the recovered joinmarket.cfg"
  fi

  echo
  echo "#############"
  echo "# Autostart #"
  echo "#############"
  echo "
if [ -f \"/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate\" ]; then
  . /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate
  /home/joinmarket/joinmarket-clientserver/jmvenv/bin/python -c \"import PySide2\"
  cd /home/joinmarket/joinmarket-clientserver/scripts/
fi
# shortcut commands
source /home/joinmarket/_commands.sh
# automatically start main menu for joinmarket unless
# when running in a tmux session
if [ -z \"\$TMUX\" ]; then
  /home/joinmarket/menu.sh
fi
"   | sudo -u joinmarket tee -a /home/joinmarket/.bashrc

  # configure joinmarket (includes a check if it is installed)
  if sudo -u joinmarket /home/joinmarket/start.joininbox.sh; then
    echo "# Start to use by logging in to the 'joinmarket' user with:"
    echo "# 'sudo su joinmarket' or use the shortcut 'jm'"
  else
    echo "# There was an error running 'bonus.joinmarket.sh on', see above"
    exit 1
  fi

  # set the raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set joinmarket "on"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set joinmarket "off"

  if [ -d /home/joinmarket ]; then
    echo "Removing the joinmarket user"
    sudo userdel -rf joinmarket 2>/dev/null
  else
    echo "JoinMarket is not installed."
  fi

  /home/admin/config.scripts/bonus.jam.sh off

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run"
exit 1
