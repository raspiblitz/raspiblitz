#!/bin/bash

# links:
# https://github.com/JoinMarket-Org/joinmarket-clientserver#quickstart---recommended-installation-method-linux-only
# https://github.com/openoms/bitcoin-tutorials/tree/master/joinmarket
# https://github.com/openoms/joininbox

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "JoinMarket install script to switch JoinMarket on or off"
 echo "sudo /home/admin/config.scrips/bonus.joinmarket.sh on|off"
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
  whiptail --title " JoinMarket info " --msgbox "Usage:
https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/USAGE.md\n
Start to use by logging in to the 'joinmarket' user with:
'sudo su - joinmarket' \n
Can log in directly with the 'joinmarket' user via ssh.
The user password is the PASSWORD_B.
" 14 87
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL JOINMARKET ***"

  # check if running Tor
  if [ ${runBehindTor} = on ]; then
    echo "OK, running behind Tor."
  else
    echo "Not running Tor"
    echo "Activate Tor from the SERVICES menu before installing JoinMarket."
    exit 1
  fi

  # make sure the Bitcoin Core wallet is on
  /home/admin/config.scripts/network.wallet.sh on

  if [ ! -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ] ; then
    echo "*** Add the 'joinmarket' user ***"
    adduser --disabled-password --gecos "" joinmarket

    echo "*** setting PASSWORD_B as the password for the 'joinmarket' user ***"
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

    # install joinmarket
    cd /home/joinmarket
    # PySide2 for armf: https://packages.debian.org/buster/python3-pyside2.qtcore
    sudo apt install -y python3-pyside2.qtcore python3-pyside2.qtgui python3-pyside2.qtwidgets zlib1g-dev libjpeg-dev
    # from https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/INSTALL.md 
    sudo apt install -y python3-dev python3-pip git build-essential automake pkg-config libtool libffi-dev libssl-dev libgmp-dev libsodium-dev

    sudo -u joinmarket git clone https://github.com/Joinmarket-Org/joinmarket-clientserver
    cd joinmarket-clientserver
    git reset --hard v0.6.2

    # set up jmvenv 
    sudo pip3 install virtualenv
    # use the PySide2 armf package from the system
    sudo -u joinmarket virtualenv --system-site-packages -p /usr/bin/python3.7 jmvenv
    source jmvenv/bin/activate || exit 1
    pip install -r requirements/base.txt
    # https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/requirements/gui.txt
    /home/joinmarket/joinmarket-clientserver/jmvenv/bin/python -c 'import PySide2'
    pip install qrcode[pil]
    pip install https://github.com/sunu/qt5reactor/archive/58410aaead2185e9917ae9cac9c50fe7b70e4a60.zip#egg=qt5reactor
        
    # autostart for joinmarket
    if [ $(sudo cat /home/joinmarket/.bashrc | grep -c "bash startup.sh") -eq 0 ]; then
      sudo bash -c "echo 'bash startup.sh' >> /home/joinmarket/.bashrc"
    fi
    if [ $(sudo cat /home/joinmarket/.bashrc | grep -c ". /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate") -eq 0 ]; then
      sudo bash -c "echo '. /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate' >> /home/joinmarket/.bashrc"
    fi
    if [ $(sudo cat /home/joinmarket/.bashrc | grep -c "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/python -c \"import PySide2\"") -eq 0 ]; then
      sudo bash -c "echo '/home/joinmarket/joinmarket-clientserver/jmvenv/bin/python -c \"import PySide2\"' >> /home/joinmarket/.bashrc"
    fi
    if [ $(sudo cat /home/joinmarket/.bashrc | grep -c "cd /home/joinmarket/joinmarket-clientserver/scripts/") -eq 0 ]; then
      sudo bash -c "echo 'cd /home/joinmarket/joinmarket-clientserver/scripts/' >> /home/joinmarket/.bashrc"
    fi

    cat > /home/admin/startup.sh <<EOF
# check for joinmarket.cfg
if [ -f "/home/joinmarket/.joinmarket/joinmarket.cfg" ] ; then
  echo ""
  echo "Welcome to the JoinMarket command line!"
  echo ""  
  echo "Notes on usage:"
  echo "https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/USAGE.md"
  echo ""
  echo "To return to the RaspiBlitz menu open a new a terminal window or use: exit"
  echo ""
else
  echo "Generating the joinmarket.cfg"
  echo ""
  . /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate &&\
  cd /home/joinmarket/joinmarket-clientserver/scripts/
  python wallet-tool.py generate --datadir=/home/joinmarket/.joinmarket
  sudo chmod 600 /home/joinmarket/.joinmarket/joinmarket.cfg || exit 1
  echo ""
  echo "Editing the joinmarket.cfg"
  sudo sed -i "s/^rpc_user =.*/rpc_user = raspibolt/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  PASSWORD_B=\$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  sudo sed -i "s/^rpc_password =.*/rpc_password = \$PASSWORD_B/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  echo "Filled the bitcoin RPC password (PASSWORD_B)"
  #communicate with IRC servers via Tor
  sudo sed -i "s/^host = irc.darkscience.net/#host = irc.darkscience.net/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^#host = darksci3bfoka7tw.onion/host = darksci3bfoka7tw.onion/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^host = irc.hackint.org/#host = irc.hackint.org/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^#host = ncwkrwxpq2ikcngxq3dy2xctuheniggtqeibvgofixpzvrwpa77tozqd.onion/host = ncwkrwxpq2ikcngxq3dy2xctuheniggtqeibvgofixpzvrwpa77tozqd.onion/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^socks5 = false/#socks5 = false/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^#socks5 = true/socks5 = true/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^#port = 6667/port = 6667/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^usessl = true/#usessl = true/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  sudo sed -i "s/^#usessl = false/usessl = false/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  echo "Edited the joinmarket.cfg to communicate over Tor only."
  echo ""
  echo "Welcome to the JoinMarket command line!"
  echo ""  
  echo "Notes on usage:"
  echo "https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/USAGE.md"
  echo ""
  echo "To return to the RaspiBlitz menu open a new a terminal window or use: exit"
  echo ""
fi
EOF

    sudo mv /home/admin/startup.sh /home/joinmarket/startup.sh
    sudo chown joinmarket:joinmarket /home/joinmarket/startup.sh
    
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
    echo "'sudo su - joinmarket'"
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
    echo "OK JoinMarket removed"
  else 
    echo "JoinMarket is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run
exit 1