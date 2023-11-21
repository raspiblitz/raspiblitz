#!/bin/bash

BitcoinMindsVersion="v0.1"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script to download and run from your Raspiblitz the BitcoinMinds.org website"
  echo "# on: installs BitcoinMinds.org and runs a local server"
  echo "# off: removes all the code"
  echo "# bonus.bitcoinminds.sh [on|off|menu]"
  echo "# BitcoinMinds.org installation script $BitcoinMindsVersion"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " BitcoinMinds.org Info" --msgbox "
This service downloads the full BitcoinMinds.org website in your Raspiblitz, so you can access its interface and Bitcoin resources from your local network, regardless of the internet connection.
Use the command 'bm' from the console to start the server.
" 11 78
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    echo ""
    echo "# ***"
    echo "# Installing BitcoinMinds.org in your Raspiblitz ..."
    echo "# ***"
    echo ""

    # create user
    USERNAME=bitcoinminds
    echo "# add the user: ${USERNAME}"
    sudo adduser --system --group --shell /bin/bash --home /home/${USERNAME} ${USERNAME}
    echo "Copy the skeleton files for login"
    sudo -u ${USERNAME} cp -r /etc/skel/. /home/${USERNAME}/

    # add local directory to path and set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/bitcoinminds/.local/bin' >> /home/bitcoinminds/.profile"
    sudo bash -c "echo 'PATH=\$PATH:/home/bitcoinminds/.local/share/composer' >> /home/bitcoinminds/.profile"

    cd /home/bitcoinminds

    echo ""
    echo "# ***"
    echo "# Downloading BitcoinMinds.org from GitHub ..."
    echo "# ***"
    echo ""
    sudo -u bitcoinminds git clone https://github.com/raulcano/bitcoinminds.git 2>/dev/null

    echo ""
    echo "# ***"
    echo "# Installing packages ..."
    echo "# ***"
    echo ""
    cd /home/bitcoinminds/bitcoinminds/bitcoinminds-ui
    sudo -u bitcoinminds npm install

    echo ""
    echo "# ***"
    echo "# Setting the autostart script for user bitcoinminds"
    echo "# ***"
    echo "
cd /home/bitcoinminds/bitcoinminds/bitcoinminds-ui
npm run serve -- --port 11026
" | sudo -u bitcoinminds tee -a /home/bitcoinminds/.bashrc


  # setting value in raspi blitz config
    sudo /home/admin/config.scripts/blitz.conf.sh set bitcoinminds on
   
  # add a firewall entry so the web UI is accessible from the local network
    sudo ufw allow 11026 comment 'bitcoinminds'

    echo ""
    echo "# ***"
    echo "# OK - BitcoinMinds installed. Type 'bm' in the console to start the environment."
    echo "# ***"
    echo ""

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=1
  if [ ${isInstalled} -eq 1 ]; then
    
    echo ""
    echo "# ***"
    echo "# Removing BitcoinMinds..."
    echo "# ***"
    echo ""
    # setting value in raspi blitz config
    sudo /home/admin/config.scripts/blitz.conf.sh set bitcoinminds off
    
    # Remove user and stuff here
    sudo userdel -rf bitcoinminds 2>/dev/null

    # delete firewall entry
    sudo ufw delete allow 11026 comment 'bitcoinminds'

    echo ""
    echo "# ***"
    echo "# OK - BitcoinMinds removed."
    echo "# ***"
    echo ""
  else
    echo "# BitcoinMinds has not been installed yet."
  fi
  exit 0
fi