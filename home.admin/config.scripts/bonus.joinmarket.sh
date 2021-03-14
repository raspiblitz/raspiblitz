#!/bin/bash

# links:
# https://github.com/JoinMarket-Org/joinmarket-clientserver#quickstart---recommended-installation-method-linux-only
# https://github.com/openoms/bitcoin-tutorials/tree/master/joinmarket
# https://github.com/openoms/joininbox

JMVERSION="v0.8.2"
JBVERSION="v0.3.1"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "JoinMarket install script to switch JoinMarket on or off"
 echo "sudo /home/admin/config.scrips/bonus.joinmarket.sh on|off"
 echo "Installs JoinMarket $pinnedVersion with JoininBox $JBVERSION"
 exit 1
fi

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^joinmarket=" /mnt/hdd/raspiblitz.conf; then
  echo "joinmarket=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  whiptail --title " JoinMarket info " --msgbox "
Type: 'jm' in the command line to switch to the dedicated user and start the JoininBox menu.
Notes on usage:
https://github.com/openoms/bitcoin-tutorials/blob/master/joinmarket/README.md
Can log in directly with the 'joinmarket' user via ssh.
The user password is the PASSWORD_B.
" 13 81
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL JOINMARKET ***"

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

    # install joinmarket
    cd /home/joinmarket
    # PySide2 for armf: https://packages.debian.org/buster/python3-pyside2.qtcore
    echo "# installing ARM specific dependencies to run the QT GUI"
    sudo apt install -y python3-pyside2.qtcore python3-pyside2.qtgui \
    python3-pyside2.qtwidgets zlib1g-dev libjpeg-dev python3-pyqt5 libltdl-dev
    # https://github.com/JoinMarket-Org/joinmarket-clientserver/issues/668#issuecomment-717815719
    sudo apt install -y build-essential automake pkg-config libffi-dev python3-dev libgmp-dev 
    sudo -u joinmarket pip install libtool asn1crypto cffi pycparser coincurve
    echo "# installing JoinMarket"
    sudo -u joinmarket git clone https://github.com/Joinmarket-Org/joinmarket-clientserver
    cd joinmarket-clientserver
    sudo -u joinmarket git reset --hard $JMVERSION
    # make install.sh set up jmvenv with -- system-site-packages
    # and import the PySide2 armf package from the system
    sudo -u joinmarket sed -i \
    "s#^    virtualenv -p \"\${python}\" \"\${jm_source}/jmvenv\" || return 1#\
    virtualenv --system-site-packages -p \"\${python}\" \"\${jm_source}/jmvenv\" || return 1 ;\
    /home/joinmarket/joinmarket-clientserver/jmvenv/bin/python -c \'import PySide2\'\
    #g" install.sh
    # do not stop at installing debian dependencies
    sudo -u joinmarket sed -i \
    "s#^        if ! sudo apt-get install \${deb_deps\[@\]}; then#\
        if ! sudo apt-get install -y \${deb_deps\[@\]}; then#g" install.sh
    # don't install PySide2 - using the system-site-package instead 
    sudo -u joinmarket sed -i "s#^PySide2##g" requirements/gui.txt
    # don't install PyQt5 - using the system package instead 
    sudo -u joinmarket sed -i "s#^PyQt5==5.14.2##g" requirements/gui.txt
    sudo -u joinmarket ./install.sh --with-qt
    echo "# installed JoinMarket $JMVERSION"

    echo "# adding the joininbox menu"
    sudo rm -rf /home/joinmarket/joininbox
    sudo -u joinmarket git clone https://github.com/openoms/joininbox.git /home/joinmarket/joininbox
    # check the latest at:
    # https://github.com/openoms/joininbox/releases/
    sudo -u joinmarket git reset --hard $JBVERSION
    sudo -u joinmarket cp /home/joinmarket/joininbox/scripts/* /home/joinmarket/
    sudo -u joinmarket cp /home/joinmarket/joininbox/scripts/.* /home/joinmarket/ 2>/dev/null
    sudo chmod +x /home/joinmarket/*.sh

    # Tor config
    # add the joinmarket user to the Tor group
    usermod -a -G debian-tor joinmarket
    # fix Tor config
    sudo sed -i "s:^CookieAuthFile*:#CookieAuthFile:g" /etc/tor/torrc
    if ! grep -Eq "^CookieAuthentication 1" /etc/tor/torrc; then
      echo "CookieAuthentication 1" | sudo tee -a /etc/tor/torrc
      sudo systemctl restart tor
    fi
    if ! grep -Eq "^AllowOutboundLocalhost 1" /etc/tor/torsocks.conf; then          
      echo "AllowOutboundLocalhost 1" | sudo tee -a /etc/tor/torsocks.conf
      sudo systemctl restart tor
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

    echo "# setting the autostart script for joinmarket"
    echo "
# automatically start startup.sh for joinmarket unless
# when running in a tmux session
if [ -z \"\$TMUX\" ]; then
  /home/joinmarket/startup.sh
fi
# always activate jmvenv with PySide2 and cd to scripts'
. /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate
/home/joinmarket/joinmarket-clientserver/jmvenv/bin/python -c \"import PySide2\"
cd /home/joinmarket/joinmarket-clientserver/scripts/
# shortcut commands
source /home/joinmarket/_commands.sh
# automatically start main menu for joinmarket unless
# when running in a tmux session
if [ -z \"\$TMUX\" ]; then
  /home/joinmarket/menu.sh
fi
" | sudo -u joinmarket tee -a /home/joinmarket/.bashrc

    cat > /home/admin/startup.sh <<EOF
# check for joinmarket.cfg
if [ ! -f "/home/joinmarket/.joinmarket/joinmarket.cfg" ] ; then
  echo "# generating the joinmarket.cfg"
  echo ""
  . /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate &&\
  cd /home/joinmarket/joinmarket-clientserver/scripts/
  python wallet-tool.py generate --datadir=/home/joinmarket/.joinmarket
  sudo chmod 600 /home/joinmarket/.joinmarket/joinmarket.cfg || exit 1
  echo ""
  echo "# editing the joinmarket.cfg"
  sed -i "s/^rpc_user =.*/rpc_user = raspibolt/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  PASSWORD_B=\$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  sed -i "s/^rpc_password =.*/rpc_password = \$PASSWORD_B/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  echo "Filled the bitcoin RPC password (PASSWORD_B)"
  sed -i "s/^rpc_wallet_file =.*/rpc_wallet_file = wallet.dat/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  echo "Using the bitcoind wallet: wallet.dat"
  #communicate with IRC servers via Tor
  sed -i "s/^host = irc.darkscience.net/#host = irc.darkscience.net/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sed -i "s/^#host = darksci3bfoka7tw.onion/host = darksci3bfoka7tw.onion/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sed -i "s/^host = irc.hackint.org/#host = irc.hackint.org/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sed -i "s/^#host = ncwkrwxpq2ikcngxq3dy2xctuheniggtqeibvgofixpzvrwpa77tozqd.onion/host = ncwkrwxpq2ikcngxq3dy2xctuheniggtqeibvgofixpzvrwpa77tozqd.onion/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sed -i "s/^socks5 = false/#socks5 = false/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sed -i "s/^#socks5 = true/socks5 = true/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sed -i "s/^#port = 6667/port = 6667/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sed -i "s/^#usessl = false/usessl = false/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  echo "# edited the joinmarket.cfg to communicate over Tor only."
fi
EOF
    mv /home/admin/startup.sh /home/joinmarket/startup.sh
    chown joinmarket:joinmarket /home/joinmarket/startup.sh
    chmod +x /home/joinmarket/startup.sh
  else
    echo "JoinMarket is already installed"
    echo ""
  fi    
  
  if [ -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ] ; then
    # setting value in raspi blitz config
    sudo sed -i "s/^joinmarket=.*/joinmarket=on/g" /mnt/hdd/raspiblitz.conf
    # starting info
    echo ""
    echo "Start to use by logging in to the 'joinmarket' user with:"
    echo "sudo su joinmarket"
    echo ""
    echo "If logging in directly via ssh the password is the PASSWORD_B"
    echo ""   
  else
    echo " Failed to install JoinMarket"
    exit 1
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^joinmarket=.*/joinmarket=off/g" /mnt/hdd/raspiblitz.conf

  if [ -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ] ; then
    echo "*** REMOVING JOINMARKET ***"
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
