#!/bin/bash

# links:
# https://github.com/JoinMarket-Org/joinmarket-clientserver#quickstart---recommended-installation-method-linux-only
# https://github.com/openoms/bitcoin-tutorials/tree/master/joinmarket
# https://github.com/openoms/joininbox

JBVERSION="v0.6.1" # with JoinMarket v0.9.2
PGPsigner="openoms"
PGPpkeys="https://keybase.io/oms/pgp_keys.asc"
PGPcheck="13C688DB5B9C745DE4D2E4545BFB77609B081B65"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "JoinMarket install script to switch JoinMarket on or off"
 echo "sudo /home/admin/config.scrips/bonus.joinmarket.sh on|off"
 echo "Installs JoininBox $JBVERSION"
 exit 1
fi

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then
  whiptail --title " JoinMarket info " --msgbox "
Type: 'jm' in the command line to switch to the dedicated user
and start the JoininBox menu.
Notes on usage:
https://github.com/openoms/bitcoin-tutorials/blob/master/joinmarket/README.md
" 11 81
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# INSTALL JOINMARKET"

  # check if running Tor
  if [ ${runBehindTor} = on ]; then
    echo "# OK, running behind Tor"
  else
    echo "# Not running Tor"
    echo "# Activate Tor from the SERVICES menu before installing JoinMarket."
    exit 1
  fi

  # make sure the Bitcoin Core wallet is on
  /home/admin/config.scripts/network.wallet.sh on

  if [ ! -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ] ; then

    echo "# cleaning before install"
    sudo userdel -rf joinmarket 2>/dev/null

    echo "# add the 'joinmarket' user"
    adduser --disabled-password --gecos "" joinmarket

    echo "# setting PASSWORD_B as the password for the 'joinmarket' user"
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    echo "joinmarket:$PASSWORD_B" | sudo chpasswd
    # add to sudo group (required for installation)
    adduser joinmarket sudo
    # configure sudo for usage without password entry for the joinmarket user
    echo 'joinmarket ALL=(ALL) NOPASSWD:ALL' | EDITOR='tee -a' visudo
    
    # make a folder for authorized keys 
    sudo -u joinmarket mkdir -p /home/joinmarket/.ssh
    chmod -R 700 /home/joinmarket/.ssh

    # install the command-line fuzzy finder (https://github.com/junegunn/fzf)
    bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/joinmarket/.bashrc"

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

    echo "# adding JoininBox"
    sudo rm -rf /home/joinmarket/joininbox
    sudo -u joinmarket git clone https://github.com/openoms/joininbox.git /home/joinmarket/joininbox
    # check the latest at:
    cd /home/joinmarket/joininbox || exit 1
    # https://github.com/openoms/joininbox/releases/
    sudo -u joinmarket git reset --hard $JBVERSION

    sudo -u joinmarket wget -O "pgp_keys.asc" ${PGPpkeys}
    gpg --import --import-options show-only ./pgp_keys.asc
    fingerprint=$(gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
    if [ ${fingerprint} -lt 1 ]; then
      echo
      echo "# !!! WARNING --> the PGP fingerprint is not as expected for ${PGPsigner}"
      echo "# Should contain PGP: ${PGPcheck}"
      echo "# PRESS ENTER to TAKE THE RISK if you think all is OK"
      read key
    fi
    gpg --import ./pgp_keys.asc
    
    verifyResult=$(git verify-commit $JBVERSION 2>&1)
    
    goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
    echo "# goodSignature(${goodSignature})"
    correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
    echo "# correctKey(${correctKey})"
    if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
      echo 
      echo "# !!! BUILD FAILED --> PGP verification not OK / signature(${goodSignature}) verify(${correctKey})"
      exit 1
    else
      echo 
      echo "########################################################################"
      echo "# OK --> the PGP signature of the checked out $JBVERSION commit is correct #"
      echo "########################################################################"
      echo 
    fi

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
    # add default Tor value to joinin.conf if needed
    if ! grep -Eq "^runBehindTor" /home/joinmarket/joinin.conf; then
      echo "runBehindTor=off" | sudo -u joinmarket tee -a /home/joinmarket/joinin.conf
    fi
    # setting Tor value in joinin config
    if grep -Eq "^runBehindTor=on" /mnt/hdd/raspiblitz.conf; then
      sudo -u joinmarket sed -i "s/^runBehindTor=.*/runBehindTor=on/g" /home/joinmarket/joinin.conf
    fi
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

    echo "######################"
    echo "# Install JoinMarket #"
    echo "######################"
    sudo -u joinmarket /home/joinmarket/install.joinmarket.sh install

  else
    echo "JoinMarket is already installed"
    echo
  fi    
  
  if [ -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ] ; then
    # setting value in raspi blitz config
    /home/admin/config.scripts/blitz.conf.sh set joinmarket "on"
    # starting info
    echo
    echo "# Start to use by logging in to the 'joinmarket' user with:"
    echo "# 'sudo su joinmarket' or use the shortcut 'jm'"
    echo
  
  else
    echo " Failed to install JoinMarket"
    exit 1
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set joinmarket "off"

  if [ -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ] ; then
    echo "# REMOVING JOINMARKET"
    sudo userdel -rf joinmarket 2>/dev/null
    echo "# OK JoinMarket is removed"
  else 
    echo "JoinMarket is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run"
exit 1
