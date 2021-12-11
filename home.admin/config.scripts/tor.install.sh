#!/usr/bin/env bash

#### INFO ####

## Lines that begin with "## " try to explain what's going on. Lines
## that begin with just "#" are disabled commands: you can enable them
## by removing the "#" symbol.

## https://onion.torproject.org/ or http://xao2lxsmia2edq2n5zxg6uahx6xox2t7bfjw6b5vdzsxi7ezmqob6qid.onion/
## https://support.torproject.org/apt/ or http://rzuwtpc4wb3xdzrj3yeajsvm3fkq4vbeubm2tdxaqruzzzgs5dwemlad.onion/apt/
## https://support.torproject.org/apt/tor-deb-repo/
## https://support.torproject.org/apt/apt-over-tor/

# command info
usage(){
 echo "script to switch Tor on or off"
 echo "tor.install.sh [install|enable|update]"
 exit 1
}

#### VARIABLES (some might be reset by prepare) ####

download_dir="/home/admin/download"
tor_data_dir="/mnt/hdd/tor"
tor_conf_dir="/mnt/hdd/app-data/tor/"
torrc="/etc/tor/torrc"
torrc_bridges="${tor_conf_dir}/torrc.d/bridges"
torrc_services="${tor_conf_dir}/torrc.d/services"
tor_pkgs="torsocks nyx obfs4proxy python3-stem apt-transport-tor curl gpg"
tor_deb_repo="tor+http://apow7mjfryruh65chtdydfmqfpj5btws7nbocgtaovhvezgccyjazpqd.onion"
#tor_deb_repo="tor+https://deb.torproject.org"
#tor_deb_repo="https://deb.torproject.org"

## https://github.com/keroserene/snowflake/commits/master
snowflake_commit_hash="af6e2c30e1a6aacc6e7adf9a31df0a387891cc37"

distribution=$(lsb_release -sc)
architecture=$(dpkg --print-architecture)

#### FUNCTIONS ####


configure_default_torrc(){
  echo -e "\n*** updating Tor config ${torrc} ***"
  echo "## raspiblitz torrc (anchor, do not remove this line)
## See 'man tor', or https://2019.www.torproject.org/docs/tor-manual.html.en
## See https://github.com/torproject/tor/blob/main/src/config/torrc.sample.in

%include ${tor_conf_dir}/torrc.d

DataDirectory ${tor_data_dir}/sys
PidFile ${tor_data_dir}/sys/tor.pid

SafeLogging 0
Log notice stdout
Log notice file ${tor_data_dir}/notice.log
Log info file ${tor_data_dir}/info.log

RunAsDaemon 1
ControlPort 9051
SocksPort 9050 IsolateDestAddr
ExitRelay 0
CookieAuthentication 1
CookieAuthFileGroupReadable 1
" | sudo tee ${torrc}
}


configure_bridges_torrc(){
  echo -e "\n*** updating Tor config ${torrc_bridges} ***"
  echo "
#UseBridges 1
#UpdateBridgesFromAuthority 1
#ClientTransportPlugin meek_lite,obfs4 exec /usr/bin/obfs4proxy
#ClientTransportPlugin snowflake exec /usr/bin/snowflake-client -url https://snowflake-broker.torproject.net.global.prod.fastly.net/ -front cdn.sstatic.net -ice stun:stun.l.google.com:19302,stun:stun.voip.blackberry.com:3478,stun:stun.altar.com.pl:3478,stun:stun.antisip.com:3478,stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,stun:stun.sonetel.net:3478,stun:stun.stunprotocol.org:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.voys.nl:3478

## Meek-Azure
#Bridge meek_lite 192.0.2.2:2 97700DFE9F483596DDA6264C4D7DF7641E1E39CE url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com

## Snowflake
#Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72

## Obfs4
##Bridge obfs4 IP:PORT FINGERPRINT cert=CERTIFICATE iat-mode=[0|1|2]
" | sudo tee ${torrc_bridges}
}


action=$1

#### INSTALL ####
if [ "${action}" = "install" ]; then

  echo -e "*** Installing tor (but not run it yet - needs HDD connected )***\n"

  echo -e "\n--> Configuring pluggable transports ***"

  ## https://github.com/radio24/TorBox/blob/master/install/run_install.sh
  ## Configuring Tor with the pluggable transports
  sudo apt install -y obfs4proxy
  sudo setcap 'cap_net_bind_service=+ep' /usr/bin/obfs4proxy

  ## Install Snowflake
  ## nyxnor: unfortunately it reaches TPO domain for a lib which I can't fix
  if [ ! -f /usr/bin/snowflake-proxy ] || [ ! -f /usr/bin/snowflake-client ]; then
    sudo rm -rf "${download_dir}"/snowflake
    git clone https://github.com/keroserene/snowflake.git "${download_dir}"/snowflake
    if [ ! -d "${download_dir}"/snowflake ]; then
      echo "FAIL: COULDN'T CLONE THE SNOWFLAKE REPOSITORY!"
      echo "INFO: The Snowflake repository may be blocked or offline!"
      echo "INFO: Please try again later and if the problem persists, please report it"
    else
      git -C "${download_dir}"/snowflake -c advice.detachedHead=false checkout "${snowflake_commit_hash}"
      echo; sudo bash /home/admin/config.scripts/bonus.go.sh on
      . /etc/profile ## GOPATH
      export GO111MODULE="on"
      cd "${download_dir}"/snowflake/proxy || exit 1
      echo -e "\n*** Installing snowflake-proxy ***"
      go get
      go build
      sudo cp proxy /usr/bin/snowflake-proxy
      cd "${download_dir}"/snowflake/client || exit 1
      echo -e "\n*** Installing snowflake-client ***"
      go get
      go build
      sudo cp client /usr/bin/snowflake-client
      cd ~ || exit 1
      sudo rm -rf "${download_dir}"/snowflake
    fi
  else
    echo -e "\n--> Snowflake client and proxy already installed ***\n"
  fi

  # install tor
  echo -e "\n*** Install Tor ***"
  # shellcheck disable=SC2086
  sudo apt -o Dpkg::Options::="--force-confold" install -y tor
  sudo apt install -y ${tor_pkgs}

  echo -e "\n*** Adding deb.torproject.org keyring ***"
  if ! torsocks curl -s https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/NAME.gpg --import
  then
    echo "!!! FAIL: Was not able to import deb.torproject.org key";
    exit 1
  fi
  echo "- OK key added"

  echo -e "\n*** Adding Tor Sources ***"
  echo "
deb [arch=${architecture}] ${tor_deb_repo}/torproject.org ${distribution} main
deb-src [arch=${architecture}] ${tor_deb_repo}/torproject.org  ${distribution} main
" | sudo tee /etc/apt/sources.list.d/tor.list
  echo "- OK sources added"

  echo -e "\n*** Reinstall ***"
  sudo apt update -y
  # shellcheck disable=SC2086
  sudo apt -o Dpkg::Options::="--force-confold" install -y tor
  sudo apt install -y ${tor_pkgs}

  echo
  exit
fi 

#### ENABLE (once HDD is available) ####
if [ "${action}" = "enbable" ]; then

  echo -e "\n*** Enable Tor Service ***"

  # create tor dirs and set permissions
  echo -e "*** Create directories and set permissions ***"
  sudo mkdir -pv "${tor_conf_dir}"/torrc.d "${tor_data_dir}"/sys/keys "${tor_data_dir}"/services "${tor_data_dir}"/onion_auth
  sudo chmod -v 700 "${tor_data_dir}"
  sudo chmod -v 755 "${tor_conf_dir}""${tor_conf_dir}"/torrc.d
  sudo chmod -v 644 "${torrc}" "${tor_conf_dir}"/torrc.d/*
  # make sure its the correct owner
  sudo chown -Rv debian-tor:debian-tor "${tor_data_dir}"
  sudo chown -Rv root:root "${tor_conf_dir}"

  # create tor config if not existent
  sudo grep -q "raspiblitz" ${torrc} || configure_default_torrc
  sudo grep -q "Bridge" ${torrc_bridges} || configure_bridges_torrc

  # edit tor services
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@default.service
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@.service
  sudo mkdir -p /etc/systemd/system/tor@default.service.d
  echo "# DO NOT EDIT! This file is generated by raspiblitz and will be overwritten
    [Service]
    ReadWriteDirectories=-${tor_data_dir}
    [Unit]
    After=network.target nss-lookup.target mnt-hdd.mount
    " | sudo tee /etc/systemd/system/tor@default.service.d/raspiblitz.conf

  # enable tor services
  sudo systemctl unmask tor@default
  sudo systemctl daemon-reload
  sudo systemctl enable --now tor@ tor@service
  sudo systemctl restart tor@default

  echo
  exit 
fi

if [ "${action}" = "update" ]; then
    case "$2" in
      source)
        # as in https://2019.www.torproject.org/docs/debian#source
        echo "# Install the dependencies"
        sudo apt update
        sudo apt install -y build-essential fakeroot devscripts
        sudo apt build-dep -y tor deb.torproject.org-keyring
        rm -rf /home/admin/download/debian-packages
        mkdir -p /home/admin/download/debian-packages
        cd /home/admin/download/debian-packages || exit 1
        echo "# Building Tor from the source code ..."
        apt source tor
        cd tor-* || exit 1
        debuild -rfakeroot -uc -us
        cd ..
        echo "# Stopping the tor.service before updating"
        sudo systemctl stop tor
        echo "# Update ..."
        sudo dpkg -i tor_*.deb
        echo "# Starting the tor.service "
        sudo systemctl start tor
        echo "# Installed $(tor --version)"
      ;;
      *) sudo apt update -y && sudo apt upgrade -y tor;;
    esac
  echo
  exit
fi

# if above didnt matched - show info onf usage
usage