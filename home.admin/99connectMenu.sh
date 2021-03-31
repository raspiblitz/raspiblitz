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
OPTIONS+=(BITCOINRPC "Connect Specter Desktop or JoinMarket")
OPTIONS+=(BISQ "Connect Bisq to this node")
OPTIONS+=(EXPORT "Get Macaroons and TLS.cert")
OPTIONS+=(RESET "Recreate LND Macaroons + TLS")
OPTIONS+=(SYNC "Sync Macaroons + TLS with Apps/Users")

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
    /home/admin/config.scripts/lnd.export.sh btcpay;;
  RESET)
    sudo /home/admin/config.scripts/lnd.credentials.sh reset
    echo "Press ENTER to return to main menu."
    read key
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
HiddenServiceDir /mnt/hdd/tor/bisq
HiddenServiceVersion 2
HiddenServicePort 8333 127.0.0.1:8333" | sudo tee -a /etc/tor/torrc
            echo "# Restarting Tor"
            sudo systemctl restart tor
            sleep 10
            TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/bisq/hostname)
              if [ -z "$TOR_ADDRESS" ]; then
                echo "Waiting for the Hidden Service"
                sleep 10
                TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/bisq/hostname)
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
          echo "Press ENTER to return to main menu."
          read key
          exit 0;;
        REMOVEBISQ)
          sudo sed -i '/Bisq/{N;N;N;d}'  /etc/tor/torrc
          echo "# Restarting Tor"
          sudo systemctl restart tor;;
        SHOWBISQ)
          clear
          TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/bisq/hostname)
          echo
          echo "Install from https://bisq.network/downloads/"
          echo "Go to Bisq Settings -> Network Info -> 'Custom Bitcoin Node'."
          echo
          echo "Enter: ${TOR_ADDRESS}:8333 to connect to this node."
          echo
          echo "Press ENTER to return to main menu."
          read key;;
      esac
    ;;
  BITCOINRPC)
    echo "# Make sure the bitcoind wallet is on"
    /home/admin/config.scripts/network.wallet.sh on
    #TODO
    ;;
esac

# go into loop - start script from beginning to load config/start fresh
/home/admin/00mainMenu.sh