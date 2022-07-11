#!/bin/bash

# https://github.com/ElementsProject/peerswap/commits/master
pinnedVersion="7b78ebc48869f176a18dc5b36d7ed5392e0552e4"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to switch the PeerSwap Service on,off or update."
  echo "Can run with CLN and LND parallel, but only on one network each."
  echo "Usage:"
  echo "bonus.peerswap.sh on <lnd|cl> <mainnet|testnet|signet>"
  echo "bonus.peerswap.sh menu <lnd|cl> <mainnet|testnet|signet>"
  echo "bonus.peerswap.sh update <lnd|cl> <mainnet|testnet|signet> <testPR> <PRnumber>"
  echo "bonus.peerswap.sh off <purge>"
  exit 1
fi

echo
echo "# Running: 'bonus.peerswap.sh $*'"
echo
source <(/home/admin/config.scripts/network.aliases.sh getvars $2 $3)


if [ "${LNTYPE}" = "cl" ]; then
  helpText="\n
Usage and examples:
https://github.com/ElementsProject/peerswap/blob/master/docs/usage.md\n
\n
In order to check if your daemon is setup correctly run:\n
${netprefix}cl peerswap-reloadpolicy\n"
elif [ "${LNTYPE}" = "lnd" ]; then
  helpText="\n
Usage and examples:\n
https://github.com/ElementsProject/peerswap/blob/master/docs/usage.md\n
\n
Use the command 'sudo su - peerswap' in the terminal to switch to the dedicated user.\n
\n
Type 'pscli help' to see the available options.\n
\n
In order to check if your daemon is setup correctly run:\n
pscli reloadpolicy\n
\n
Monitoring:\n
sudo journalctl -fu peerswapd\n"
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " PeerSwap Service Info" --msgbox "$helpText" 20 73
  exit 0
fi

# releases are created on GitHub
PGPsigner="web-flow"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="4AEE18F83AFDEB23"

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Install PeerSwap"

  isInstalled=$(sudo ls /etc/systemd/system/peerswapd.service 2>/dev/null | grep -c 'peerswapd.service')
  isPlugin=$(sudo ls /home/bitcoin/${netprefix}cl-plugins-enabled/peerswap-plugin | grep -c peerswap-plugin)
  if [ ${isInstalled} -eq 0 ] || [ ${isPlugin} -eq 0 ]; then

  function getSource() {
    # install Go
    /home/admin/config.scripts/bonus.go.sh on

    # get Go vars
    source /etc/profile

    # create dedicated user
    sudo adduser --disabled-password --gecos "" peerswap

    # set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/peerswap/go/bin/' >> /home/peerswap/.profile"

    cd /home/peerswap || exit 1
    sudo -u peerswap git clone https://github.com/ElementsProject/peerswap.git
    cd /home/peerswap/peerswap || exit 1
    sudo -u peerswap git reset --hard $pinnedversion

    sudo -u peerswap /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
  }

    if [ ${LNTYPE} = cl ]; then
      # https://github.com/ElementsProject/peerswap/blob/master/docs/setup_cln.md
      if [ ! -f /home/bitcoin/cl-plugins-available/peerswap-plugin ]; then
        getSource
        # build
        sudo -u peerswap bash -c 'PATH=/usr/local/go/bin/:$PATH; make cln-release'|| exit 1
        # install
        sudo mv /home/peerswap/peerswap/peerswap-plugin /home/bitcoin/cl-plugins-available/
        sudo chown bitcoin:bitcoin /home/bitcoin/cl-plugins-available/peerswap-plugin
        sudo chmod +x /home/bitcoin/cl-plugins-available/peerswap-plugin
      fi
      # symlink
      sudo -u bitcoin ln -s /home/bitcoin/cl-plugins-available/peerswap-plugin /home/bitcoin/${netprefix}cl-plugins-enabled/


      # log-level=debug:plugin-peerswap-plugin
      #
      # peerswap-db-path ## Path to swap db file (default: $HOME/.lightning/<network>/peerswap/swap)
      # peerswap-policy-path ## Path to policy file (default: $HOME/.lightning/<network>/peerswap/policy.conf)
      #
      # # Bitcoin connection info
      # peerswap-bitcoin-rpchost ## Host of bitcoind rpc (default: localhost)
      # peerswap-bitcoin-rpcport ## Port of bitcoind rpc (default: network-default)
      # peerswap-bitcoin-rpcuser ## User for bitcoind rpc
      # peerswap-bitcoin-rpcpassword ## Password for bitcoind rpc
      # peerswap-bitcoin-cookiefilepath ## Path to bitcoin cookie file
      #
      # peerswap-elementsd-enabled ## Override liquid enable (default: true)
      RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
      PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
      # blitz.conf.sh set [key] [value] [?conffile] <noquotes>
      /home/admin/config.scripts/blitz.conf.sh set "log-level" "debug:plugin-peerswap-plugin" "${CLCONF}" noquotes
      /home/admin/config.scripts/blitz.conf.sh set "bitcoin-rpcconnect" "127.0.0.1" "${CLCONF}" noquotes
      /home/admin/config.scripts/blitz.conf.sh set "bitcoin-rpcport" "${portprefix}8332" "${CLCONF}" noquotes
      /home/admin/config.scripts/blitz.conf.sh set "bitcoin-rpcuser" "${RPC_USER}" "${CLCONF}" noquotes
      /home/admin/config.scripts/blitz.conf.sh set "bitcoin-rpcpassword" "${PASSWORD_B}" "${CLCONF}" noquotes
      /home/admin/config.scripts/blitz.conf.sh set "peerswap-elementsd-enabled" "false" "${CLCONF}" noquotes

      sudo -u bitcoin mkdir /home/bitcoin/.lightning/${CLNETWORK}/peerswap/
      if [ "${CHAIN}" = "mainnet" ]; then
        echo "accept_all_peers=false" | sudo -u bitcoin tee /home/bitcoin/.lightning/${CLNETWORK}/peerswap/policy.conf
      else
        echo "accept_all_peers=true" | sudo -u bitcoin tee /home/bitcoin/.lightning/${CLNETWORK}/peerswap/policy.conf
      fi

      source <(/home/admin/_cache.sh get state)
      if [ "${state}" == "ready" ]; then
        echo "# OK - peerswapd-plugin is enabled, system is on ready so restarting ${netprefix}lightningd"
        sudo systemctl restart ${netprefix}lightningd
      else
        echo "# OK - peerswapd-plugin is enabled, but needs reboot or manual starting: sudo systemctl start ${netprefix}lightningd"
      fi

      # setting value in raspiblitz.conf
      /home/admin/config.scripts/blitz.conf.sh set peerswapcln "on"

      echo "$helpText"
      exit 0

    elif [ ${LNTYPE} = lnd ]; then
      echo "# persist settings in app-data"
      # move old data if present
      sudo mv /home/peerswap/.peerswap /mnt/hdd/app-data/ 2>/dev/null
      echo "# make sure the data directory exists"
      sudo mkdir -p /mnt/hdd/app-data/.peerswap
      echo "# symlink"
      sudo rm -rf /home/peerswap/.peerswap # not a symlink.. delete it silently
      sudo ln -s /mnt/hdd/app-data/.peerswap/ /home/peerswap/.peerswap
      sudo chown peerswap:peerswap -R /mnt/hdd/app-data/.peerswap

      if [ ! -f /usr/local/bin/peerswapd ]; then
        # https://github.com/ElementsProject/peerswap/blob/master/docs/setup_lnd.md
        getSource
        # build
        sudo -u peerswap bash -c 'PATH=/usr/local/go/bin/:$PATH; make lnd-release'|| exit 1
        # install
        sudo mv /home/peerswap/peerswap/peerswapd /usr/local/bin/
        sudo mv /home/peerswap/peerswap/pscli /usr/local/bin/
        sudo chown root:root /usr/local/bin/peerswapd
        sudo chown root:root /usr/local/bin/pscli
      fi

      # make sure symlink to central app-data directory exists
      sudo rm -rf /home/peerswap/.lnd  # not a symlink.. delete it silently
      # create symlink
      sudo ln -s /mnt/hdd/app-data/lnd/ /home/peerswap/.lnd

      # sync all macaroons and unix groups for access
      /home/admin/config.scripts/lnd.credentials.sh sync "${CHAIN}"
      # macaroons will be checked after install

      # add user to group with admin access to lnd
      sudo /usr/sbin/usermod --append --groups lndadmin peerswap
      # add user to group with readonly access on lnd
      sudo /usr/sbin/usermod --append --groups lndreadonly peerswap
      # add user to group with invoice access on lnd
      sudo /usr/sbin/usermod --append --groups lndinvoice peerswap
      # add user to groups with all macaroons
      sudo /usr/sbin/usermod --append --groups lndinvoices peerswap
      sudo /usr/sbin/usermod --append --groups lndchainnotifier peerswap
      sudo /usr/sbin/usermod --append --groups lndsigner peerswap
      sudo /usr/sbin/usermod --append --groups lndwalletkit peerswap
      sudo /usr/sbin/usermod --append --groups lndrouter peerswap

      echo "\
# PeerSwap config for ${LNTYPE} on ${CHAIN}
lnd.tlscertpath=/home/peerswap/.lnd/tls.cert
lnd.macaroonpath=/home/peerswap/.lnd/data/chain/bitcoin/${CHAIN}/admin.macaroon
lnd.host=localhost:1${L2rpcportmod}009
"   | sudo -u peerswap tee /home/peerswap/.peerswap/peerswap.conf

      if [ "${CHAIN}" = "mainnet" ]; then
        echo "accept_all_peers=false" | sudo -u peerswap tee /home/peerswap/.peerswap/policy.conf
      else
        echo "accept_all_peers=true" | sudo -u peerswap tee /home/peerswap/.peerswap/policy.conf
      fi

      # sudo nano /etc/systemd/system/peerswapd.service
      echo "
[Unit]
Description=peerswapd Service
After=${netprefix}lnd.service

[Service]
WorkingDirectory=/home/peerswap/.peerswap
ExecStart=/usr/local/bin/peerswapd \
 --host=localhost:42069 \
 --resthost=localhost:42070 \
 --configfile=/home/peerswap/.peerswap/peerswap.conf \
 --policyfile=/home/peerswap/.peerswap/policy.conf \
 --datadir=/home/peerswap/.peerswap
User=peerswap
Group=peerswap
Type=simple
TimeoutSec=60
Restart=always
RestartSec=60

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
"   | sudo tee /etc/systemd/system/peerswapd.service
      sudo systemctl enable peerswapd
      echo "# OK - the peerswap service is now enabled"
      source <(/home/admin/_cache.sh get state)
      if [ "${state}" == "ready" ]; then
        echo "# OK - peerswapd service is enabled, system is on ready so starting peerswapd.service"
        sudo systemctl start peerswapd
      else
        echo "# OK - peerswapd.service is enabled, but needs reboot or manual starting: sudo systemctl start peerswapd"
      fi

    else
      echo "# The peerswapd.service is already installed."
    fi

    # setting value in raspiblitz.conf
    /home/admin/config.scripts/blitz.conf.sh set peerswaplnd "on"

    echo "$helpText"
  fi

  echo "\
On first startup of the plugin a policy file will be generated
(default path: /home/peerswap/.peerswap/policy.conf) in which trusted nodes will be specified.
This can be done manually by adding a line with:
allowlisted_peers=<REPLACE_WITH_PUBKEY_OF_PEER>
or with pscli addpeer <PUBKEY>.
If you feel especially reckless you can add the line:
accept_all_peers=true
this will allow anyone with a direct channel to you to do a swap with you.
"
  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  if [ "${LNTYPE}" = "cl" ]; then
    /home/admin/config.scripts/blitz.conf.sh set peerswapcln "off"
    # remove symlink
    sudo rm /home/bitcoin/${netprefix}cl-plugins-enabled/peerswap-plugin
    sudo sed -i "/^peerswap/d" ${CLCONF}

  elif [ "${LNTYPE}" = "lnd" ]; then
    /home/admin/config.scripts/blitz.conf.sh set peerswaplnd "off"
    isInstalled=$(sudo ls /etc/systemd/system/peerswapd.service 2>/dev/null | grep -c 'peerswapd.service')
    if [ ${isInstalled} -eq 1 ]; then
      echo "# Removing the PeerSwap service"
      # remove the systemd service
      sudo systemctl stop peerswapd
      sudo systemctl disable peerswapd
      sudo rm /etc/systemd/system/peerswapd.service
      echo "# OK, the PeerSwap Service is removed."
    else
      echo "# PeerSwap is not installed."
    fi
  fi

  # only if 'purge' is an additional parameter (other instances/services might need this)
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    # cl
    echo "# Removing the binaries"
    sudo rm /home/bitcoin/cl-plugins-available/peerswap-plugin
    echo "# Delete swaps data"
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/peerswap/swap
    echo "# Delete policy.conf"
    sudo rm /home/bitcoin/.lightning/${CLNETWORK}/peerswap/policy.conf
    echo "# Delete all peerswap data"
    sudo rm -rf /home/bitcoin/.lightning/${CLNETWORK}/peerswap
    # lnd
    echo "# Removing the binaries"
    echo "# Delete user and home directory"
    sudo userdel -rf peerswap
    echo "# Delete swaps data"
    sudo rm /mnt/hdd/app-data/.peerswap/swaps
    echo "# Delete all peerswap data"
    sudo rm -rf /mnt/hdd/app-data/.peerswap
  fi
  exit 0
fi


# update
if [ "$1" = "update" ]; then

  echo "# Updating PeerSwap"
  # clean old code
  sudo rm -rf /home/peerswap/peerswap || exit 1
  cd /home/peerswap || exit 1
  sudo -u peerswap git clone https://github.com/ElementsProject/peerswap.git
  cd /home/peerswap/peerswap || exit 1
  if [ "$4" = "testPR" ]; then
    PRnumber=$5 || (echo "# no PRnumber was provided"; exit 1)
    echo "# Using the PR:"
    echo "# https://github.com/ElementsProject/peerswap/pull/$PRnumber"
    sudo -u peerswap git fetch origin pull/$PRnumber/head:pr$PRnumber || exit 1
    sudo -u peerswap git checkout pr$PRnumber || exit 1
  fi

  if [ "${LNTYPE}" = "cl" ]; then
    # build
    sudo -u peerswap bash -c 'PATH=/usr/local/go/bin/:$PATH; make cln-release'|| exit 1
    # install
    sudo mv /home/peerswap/peerswap/peerswap-plugin /home/bitcoin/cl-plugins-available/
    sudo chown bitcoin:bitcoin /home/bitcoin/cl-plugins-available/peerswap-plugin
  elif [ "${LNTYPE}" = "lnd" ]; then
    sudo systemctl stop peerswapd
    # build
    sudo -u peerswap bash -c 'PATH=/usr/local/go/bin/:$PATH; make lnd-release'|| exit 1
    # install
    sudo mv /home/peerswap/peerswap/peerswapd /usr/local/bin/
    sudo mv /home/peerswap/peerswap/pscli /usr/local/bin/
    sudo chown root:root /usr/local/bin/peerswapd
    sudo chown root:root /usr/local/bin/pscli
    echo "# Starting the peerswapd.service ..."
    sudo systemctl start peerswapd
  fi

  if [ "$4" = "testPR" ]; then
    echo "# Updated to the latest in https://github.com/ElementsProject/peerswap/pull/$PRnumber"
  else
    echo "# Updated to the latest in https://github.com/ElementsProject/peerswap/commits/master"
  fi
  echo
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
