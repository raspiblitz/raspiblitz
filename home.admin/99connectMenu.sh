#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
HEIGHT=12
WIDTH=64
CHOICE_HEIGHT=6
BACKTITLE="RaspiBlitz"
TITLE="Connect Options"
MENU=""
OPTIONS=()

OPTIONS+=(MOBILE "Connect Mobile Wallet")
if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(ELECTRS "Electrum Rust Server")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(BTCPAY "Show LND connection string")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
OPTIONS+=(${network}RPC "Connect Specter Desktop or JoinMarket")
OPTIONS+=(BISQ "Connect Bisq to this node")
OPTIONS+=(EXPORT "Get Macaroons and TLS.cert")
OPTIONS+=(RESET "Recreate LND Macaroons & tls.cert")
OPTIONS+=(SYNC "Sync Macaroons & tls.cert with Apps/Users")

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Main menu" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in

  MOBILE)
    /home/admin/97addMobileWallet.sh;;
  ELECTRS)
    /home/admin/config.scripts/bonus.electrs.sh menu;;
  BTCPAY)
    /home/admin/config.scripts/lnd.export.sh btcpay
    echo "Press ENTER to return to main menu."
    read key
    exit 0;;
  RESET)
    sudo /home/admin/config.scripts/lnd.credentials.sh reset
    sudo /home/admin/config.scripts/lnd.credentials.sh sync
    sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
    exit 0;;
  SYNC)
    sudo /home/admin/config.scripts/lnd.credentials.sh sync
    echo "Press ENTER to return to main menu."
    read key
    exit 0;;
  EXPORT)
    sudo /home/admin/config.scripts/lnd.export.sh
    exit 0;;

  BISQ)
    OPTIONS=()
    if [ $(grep -c "peerbloomfilters=1" < /mnt/hdd/bitcoin/bitcoin.conf) -eq 0 ]||\
    [ $(grep -c Bisq < /etc/tor/torrc) -eq 0 ];then
      OPTIONS+=(ADDBISQ "Add a Hidden Service for Bisq")
    fi
    if [ $(grep -c "peerbloomfilters=1" < /mnt/hdd/bitcoin/bitcoin.conf) -gt 0 ]&&\
    [ $(grep -c Bisq < /etc/tor/torrc) -gt 0 ];then
      OPTIONS+=(SHOWBISQ "Show the Hidden Service to connect Bisq")
      OPTIONS+=(REMOVEBISQ "Remove the Hidden Service for bisq")
    fi
    CHOICE=$(dialog --clear \
                --backtitle "" \
                --title "Connect Bisq" \
                --ok-label "Select" \
                --cancel-label "Cancel" \
                --menu "" \
                8 64 2 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

      case $CHOICE in
        ADDBISQ)
          clear
          if [ $(grep -c "peerbloomfilters=1" < /mnt/hdd/bitcoin/bitcoin.conf) -eq 0 ]
          then
            echo "peerbloomfilters=1" | sudo tee -a /mnt/hdd/bitcoin/bitcoin.conf
            echo "# Restarting bitcoind"
            sudo systemctl restart bitcoind
          else
            echo "# bitcoind is already configured with peerbloomfilters=1"
          fi

          if [ $(grep -c Bisq < /etc/tor/torrc) -eq 0 ];then
            echo "# Creating the Hidden Service for Bisq"
            echo "
# Hidden Service for Bisq (bitcoin RPC v2)
HiddenServiceDir ${SERVICES_DATA_DIR}/bisq
HiddenServiceVersion 2
HiddenServicePort 8333 127.0.0.1:8333" | sudo tee -a /etc/tor/torrc
            echo "# Restarting Tor"
            sudo systemctl restart tor
            sleep 10
            TOR_ADDRESS=$(sudo cat ${SERVICES_DATA_DIR}/bisq/hostname)
              if [ -z "$TOR_ADDRESS" ]; then
                echo "Waiting for the Hidden Service"
                sleep 10
                TOR_ADDRESS=$(sudo cat ${SERVICES_DATA_DIR}/bisq/hostname)
                if [ -z "$TOR_ADDRESS" ]; then
                  echo "# FAIL - The Hidden Service address could not be found - Tor error?"
                  exit 1
                fi
              fi
          else
            echo "# The Hidden Service for Bisq is already configured"
          fi
          echo
          echo "Install from https://bisq.network/downloads/"
          echo "Go to Bisq Settings -> Network Info -> 'Custom Bitcoin Node'."
          echo
          echo "Enter: ${TOR_ADDRESS}:8333 to connect to this node."
          echo
          echo "Press ENTER to return to the menu."
          read key
          exit 0;;
        REMOVEBISQ)
          sudo sed -i '/Bisq/{N;N;N;d}'  /etc/tor/torrc
          echo "# Restarting Tor"
          sudo systemctl restart tor;;
        SHOWBISQ)
          clear
          TOR_ADDRESS=$(sudo cat ${SERVICES_DATA_DIR}/bisq/hostname)
          echo
          echo "Install from https://bisq.network/downloads/"
          echo "Go to Bisq Settings -> Network Info -> 'Custom Bitcoin Node'."
          echo
          echo "Enter: ${TOR_ADDRESS}:8333 to connect to this node."
          echo
          echo "Press ENTER to return to the menu."
          read key;;
      esac
    ;;
  ${network}RPC)
    # vars
    if [ "${chain}net" == "mainnet" ]; then
      BITCOINRPCPORT=8332
    elif [ "${chain}net" == "testnet" ]; then
      BITCOINRPCPORT=18332
    elif [ "${chain}net" == "signet" ]; then
      BITCOINRPCPORT=38332
    else
      # have this to signal that selection went wrong
      BITCOINRPCPORT=0
    fi
    echo "# Running on ${chain}net"
    echo
    localIPrange=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' |\
    grep 'eth0\|wlan0\|enp0\|inet' | tail -n1 | awk '{print $2}' |\
    awk -F. '{print $1"."$2"."$3".0/24"}')
    localIP=$(hostname -I | awk '{print $1}')
    allowIPrange=$(grep -c "rpcallowip=$localIPrange" <  /mnt/hdd/${network}/${network}.conf)
    bindIP=$(grep -c "${chain}.rpcbind=$localIP" <  /mnt/hdd/${network}/${network}.conf)
    rpcTorService=$(grep -c "HiddenServicePort ${BITCOINRPCPORT} 127.0.0.1:${BITCOINRPCPORT}"  < /etc/tor/torrc)
    TorRPCaddress=$(sudo cat ${SERVICES_DATA_DIR}/bitcoin${BITCOINRPCPORT}/hostname)

    function showRPCcredentials() {
      RPCUSER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
      RPCPSW=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
      echo
      echo "RPC username:"
      echo "$RPCUSER"
      echo
      echo "RPC password:"
      echo "$RPCPSW"
      if [ $allowIPrange -gt 0 ]&&[ $bindIP -gt 0 ];then
        echo
        echo "Host on the local network (make sure to connect from the same network):"
        echo $localIP
      fi
      if [ $rpcTorService -gt 0 ];then
        echo
        echo "Host via Tor (Tor needs to run on the client connecting as well):"
        echo $TorRPCaddress
      fi
      echo
      echo "Port:"
      echo "${BITCOINRPCPORT}"
      echo
      echo "More documentation at:"
      echo "https://github.com/openoms/joininbox/blob/master/prepare_remote_node.md"
    }

    # menu
    OPTIONS=()
    if [ $allowIPrange -eq 0 ]&&\
    [ $bindIP -eq 0 ]&&\
    [ $rpcTorService -eq 0 ];then
      OPTIONS+=(ADDRPCLAN "Accept local connections to ${network} RPC")
      OPTIONS+=(ADDRPCTOR "Add a Hidden Service to connect to ${network} RPC")
    else
      OPTIONS+=(CREDENTIALS "Show how to connect to ${network} RPC")
      OPTIONS+=(REMOVERPC "Close all connections to ${network} RPC")
      if [ $allowIPrange -eq 0 ]||[ $bindIP -eq 0 ];then
        OPTIONS+=(ADDRPCLAN "Accept local connections to ${network} RPC")
      fi
      if [ $rpcTorService -eq 0 ];then
        OPTIONS+=(ADDRPCTOR "Add a Hidden Service to connect to ${network} RPC")
      fi
    fi
    CHOICE=$(dialog --clear \
                --backtitle "" \
                --title "${network} RPC" \
                --ok-label "Select" \
                --cancel-label "Cancel" \
                --menu "" 9 66 3 \
                "${OPTIONS[@]}" 2>&1 >/dev/tty)

    case $CHOICE in
      ADDRPCLAN)
        clear
        echo "# Make sure the bitcoind wallet is on"
        /home/admin/config.scripts/network.wallet.sh on

        restartCore=0
        if [ $allowIPrange -eq 0 ]; then
          echo "rpcallowip=$localIPrange" | sudo tee -a /mnt/hdd/${network}/${network}.conf
          restartCore=1
        fi
        if [ $bindIP -eq 0 ]; then
          echo "${chain}.rpcbind=$localIP" | sudo tee -a /mnt/hdd/${network}/${network}.conf
          restartCore=1
        fi
        if [ $restartCore = 1 ];then
          echo "# Restarting ${network}d"
          sudo systemctl restart ${network}d
        fi
        echo "# ufw allow from $localIPrange to any port ${BITCOINRPCPORT}"
        sudo ufw allow from $localIPrange to any port ${BITCOINRPCPORT}
        echo
        showRPCcredentials
        echo "Press ENTER to return to the menu."
        read key
        ;;
      ADDRPCTOR)
        clear
        echo "# Make sure the bitcoind wallet is on"
        /home/admin/config.scripts/network.wallet.sh on
        /home/admin/config.scripts/tor.onion-service.sh bitcoin${BITCOINRPCPORT} ${BITCOINRPCPORT} ${BITCOINRPCPORT}
        echo
        echo "The address of the local node is: $TorRPCaddress"
        echo
        showRPCcredentials
        echo
        echo "Press ENTER to return to the menu."
        read key
        ;;

      CREDENTIALS)
        clear
        showRPCcredentials
        echo
        echo "Press ENTER to return to the menu."
        read key
        ;;
      REMOVERPC)
        # remove old entry
        sudo sed -i "/# Hidden Service for BITCOIN RPC (mainnet, testnet, signet)/,/^\s*$/{d}" /etc/tor/torrc
        # remove Hidden Service
        /home/admin/config.scripts/tor.onion-service.sh off bitcoin${BITCOINRPCPORT}
        sudo ufw deny from $localIPrange to any port ${BITCOINRPCPORT}
        restartCore=0
        if [ $allowIPrange -gt 0 ]; then
          sudo sed -i "/^rpcallowip=.*/d" /mnt/hdd/${network}/${network}.conf
          restartCore=1
        fi
        if [ $bindIP -gt 0 ]; then
          sudo sed -i "/^${chain}.rpcbind=$localIP/d" /mnt/hdd/${network}/${network}.conf
          restartCore=1
        fi
        if [ $restartCore = 1 ];then
          echo "# Restarting ${network}d"
          sudo systemctl restart ${network}d
        fi
        ;;
    esac
  ;;
esac
