#!/bin/bash


# Background:
# https://medium.com/@lopp/how-to-run-bitcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
# https://bitcoin.stackexchange.com/questions/70069/how-can-i-setup-bitcoin-to-be-anonymous-with-tor
# https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md
# https://github.com/bitcoin/bitcoin/blob/master/doc/tor.md

# INFO
# --------------------
# basic install of Tor is done by the build script now .. on/off will just switch service on/off
# also thats where the sources are set and the preparation is done

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to switch Tor on or off"
 echo "tor.network-install.sh [status|on|btcconf-on|lndconf-on]"
 exit 1
fi

# include lib
. /home/admin/config.scripts/tor.functions.lib


activateBitcoinOverTor()
{
  echo "*** Changing ${network} Config ***"

  btcExists=$(sudo ls /home/bitcoin/.${network}/${network}.conf | grep -c "${network}.conf")
  if [ ${btcExists} -gt 0 ]; then

    # make sure all is turned off and removed and then activate fresh (so that also old settings get removed)
    deactivateBitcoinOverTor

    echo "# Make sure the user ${OWNER_CONF_DIR} is in the ${OWNER_DATA_DIR} group"
    sudo usermod -a -G ${OWNER_DATA_DIR} ${OWNER_CONF_DIR}
    sudo chmod 777 /home/bitcoin/.${network}/${network}.conf
    echo "Adding Tor config to the the ${network}.conf ..."
    sudo sed -i "s/^torpassword=.*//g" /home/bitcoin/.${network}/${network}.conf
    echo "onlynet=onion" >> /home/bitcoin/.${network}/${network}.conf
    echo "proxy=127.0.0.1:9050" >> /home/bitcoin/.${network}/${network}.conf
    echo "main.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "test.bind=127.0.0.1" >> /home/bitcoin/.${network}/${network}.conf
    echo "dnsseed=0" >> /home/bitcoin/.${network}/${network}.conf
    echo "dns=0" >> /home/bitcoin/.${network}/${network}.conf

    # remove empty lines
    sudo sed -i '/^ *$/d' /home/bitcoin/.${network}/${network}.conf
    sudo chmod 444 /home/bitcoin/.${network}/${network}.conf

    # copy new bitcoin.conf to admin user for cli access
    sudo cp /home/bitcoin/.${network}/${network}.conf ${USER_DIR}/.${network}/${network}.conf
    sudo chown ${USER}:${USER} ${USER_DIR}/.${network}/${network}.conf

  else
    echo "BTC config does not found (yet) -  try with 'tor.on.sh btcconf-on' again later"
  fi
}


deactivateBitcoinOverTor()
{
  # always make sure also to remove old settings
  sudo sed -i "s/^onlynet=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^main.addnode=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^test.addnode=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^proxy=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^main.bind=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^test.bind=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^dnsseed=.*//g" /home/bitcoin/.${network}/${network}.conf
  sudo sed -i "s/^dns=.*//g" /home/bitcoin/.${network}/${network}.conf
  # remove empty lines
  sudo sed -i '/^ *$/d' /home/bitcoin/.${network}/${network}.conf
  sudo cp /home/bitcoin/.${network}/${network}.conf ${USER_DIR}/.${network}/${network}.conf
  sudo chown ${USER}:${USER} ${USER_DIR}/.${network}/${network}.conf
}


activateLndOverTor()
{
  echo "*** Putting LND behind Tor ***"

  lndExists=$(sudo ls /etc/systemd/system/lnd.service | grep -c "lnd.service")
  if [ ${lndExists} -gt 0 ]; then

    # deprecate 'torpassword='
    sudo sed -i '/\[Tor\]*/d' /mnt/hdd/lnd/lnd.conf
    sudo sed -i '/^tor.password=*/d' /mnt/hdd/lnd/lnd.conf

    # modify LND service
    echo "# Make sure LND is disabled"
    sudo systemctl disable lnd 2>/dev/null

    echo "# Editing /etc/systemd/system/lnd.service"
    sudo sed -i "s/^ExecStart=\/usr\/local\/bin\/lnd.*/ExecStart=\/usr\/local\/bin\/lnd \
    --tor\.active --tor\.streamisolation --tor\.v3 --tor\.socks=${DEFAULT_SOCKS_PORT} --tor\.control=${DEFAULT_CONTROL_PORT} \
    --listen=127\.0\.0\.1\:9735 \${lndExtraParameter}/g" /etc/systemd/system/lnd.service

    echo "# Enable LND again"
    sudo systemctl enable lnd
    echo "# OK"
    echo

  else
    echo "# LND service not found (yet) - try with 'tor.on.sh lndconf-on' again later"
  fi
}

torRunning=$(sudo systemctl --no-pager status tor@default | grep -c "Active: active")
torFunctional=$(curl --connect-timeout 30 --socks5-hostname "127.0.0.1:9050" https://check.torproject.org 2>/dev/null | grep -c "Congratulations. This browser is configured to use Tor.")
if [ "${torFunctional}" == "" ]; then torFunctional=0; fi
if [ ${torFunctional} -gt 1 ]; then torFunctional=1; fi

# if started with status
if [ "$1" = "status" ]; then
  # is Tor activated
  if [ "${runBehindTor}" == "on" ]; then
    echo "activated=1"
  else
    echo "activated=0"
  fi
  echo "torRunning=${torRunning}"
  echo "torFunctional=${torFunctional}"
  echo "config='${TORRC}'"
  exit 0
fi

# if started with btcconf-on
if [ "$1" = "btcconf-on" ]; then
  activateBitcoinOverTor
  exit 0
fi

# if started with lndconf-on
if [ "$1" = "lndconf-on" ]; then
  activateLndOverTor
  exit 0
fi

# add default value to raspi config if needed
checkTorEntry=$(sudo cat ${CONF} | grep -c "runBehindTor")
if [ ${checkTorEntry} -eq 0 ]; then
  echo "runBehindTor=off" >> ${CONF}
fi

# location of Tor config
# make sure /etc/tor exists
sudo mkdir /etc/tor 2>/dev/null

if [ "$1" != "update" ]; then
  # stop services (if running)
  echo "making sure services are not running"
  sudo systemctl stop lnd 2>/dev/null
  sudo systemctl stop ${network}d 2>/dev/null
  sudo systemctl stop tor@default 2>/dev/null
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# switching Tor ON"

  # *** CURL TOR PROXY ***
  # see https://github.com/rootzoll/raspiblitz/issues/1341
  #echo "socks5-hostname localhost:9050" > .curlrc.tmp
  #sudo cp ./.curlrc.tmp /root/.curlrc
  #sudo chown root:root /home/admin/.curlrc
  #sudo cp ./.curlrc.tmp /home/pi/.curlrc
  #sudo chown pi:pi /home/pi/.curlrc
  #sudo cp ./.curlrc.tmp /home/admin/.curlrc
  #sudo chown admin:admin /home/admin/.curlrc
  #rm .curlrc.tmp

  # make sure the network was set (by sourcing raspiblitz.conf)
  if [ ${#network} -eq 0 ]; then
    echo "!! FAIL - unknown network due to missing ${CONF}"
    echo "# switching Tor config on for RaspiBlitz services is just possible after basic hdd/ssd setup"
    echo "# but with new 'Tor by default' basic Tor socks will already be available from the start"
    exit 1
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^runBehindTor=.*/runBehindTor=on/g" ${CONF}

  # check if Tor was already installed and is funtional
  echo ""
  echo "*** Check if Tor service is functional ***"
  torRunning=$(curl --connect-timeout 10 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org 2>/dev/null | grep "Congratulations. This browser is configured to use Tor." -c)
  if [ ${torRunning} -gt 0 ]; then
    clear
    echo "You are all good - Tor is already running."
    echo ""
    exit 0
  else
    echo "Tor not running ... proceed with switching to Tor."
    echo ""
  fi

  #  Configuring Tor with the pluggable transports
  sleep 10
  clear
  echo -e "${RED}[+] Configuring Tor with the pluggable transports....${NOCOLOR}"
  sudo cp /usr/share/tor/geoip* /usr/bin
  sudo chmod a+x /usr/bin/geoip*
  sudo setcap 'cap_net_bind_service=+ep' /usr/bin/obfs4proxy
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@default.service
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@.service

  # Additional installation for GO
  bash ${USER_DIR}/config.scripts/bonus.go.sh on
  export GO111MODULE="on"

  # Do NOT use torproject.org domain cause they could be blocked
  # they can be used later when tor is functioning, but now is the setup
  # paths saved here for those who want, it is always the same version anyway

  # SNOWFLAKE
  #git clone https://git.torproject.org/pluggable-transports/snowflake.git
  git clone https://github.com/keroserene/snowflake.git
  cd ${USER_DIR}/snowflake/proxy
  go get
  go build
  sudo cp proxy /usr/bin/snowflake-proxy
  cd ${USER_DIR}/snowflake/client
  go get
  go build
  sudo cp client /usr/bin/snowflake-client

  cd ${USER_DIR}

  # OBFS4
  #git clone https://gitweb.torproject.org/pluggable-transports/obfs4.git/
  git clone https://salsa.debian.org/pkg-privacy-team/obfs4proxy.git
  cd ${USER_DIR}/obfs4proxy/
  go build -o obfs4proxy/obfs4proxy ./obfs4proxy
  sudo cp ./obfs4proxy/obfsproxy /usr/local/bin/obfs4proxy/obfsproxy

  cd ${USER_DIR}

  sudo rm -rf obfs4proxy
  sudo rm -rf snowflake
  sudo rm -rf go*

  # remove GO
  bash ${USER_DIR}/config.scripts/bonus.go.sh off

  # Install requirements to request bridges from the database
  # https://github.com/radio24/TorBox/blob/master/requirements.txt
  sudo pip3 -r install ${USER_DIR}/tor.requirements.txt

  # TODO(nyxnor): ask if user want to configure Tor Bridges with Pluggable Transport before installing Tor
  # will use assets/torrc.sample for default bridges. Bridges configured do not need to be used, user can select or add at will

  # install package just in case it was deinstalled
  sudo apt install tor nyx torsocks -y

  # create tor data directory if it not exist
  if [ ! -d "${DATA_DIR}" ]; then
    echo "# - creating tor data directory"
    sudo mkdir -p ${DATA_DIR}
    sudo mkdir -p ${DATA_DIR}/sys
  else
    echo "# - tor data directory exists"
  fi
  # make sure its the correct owner
  set_owner_permission

  # create tor config .. if not exists or is old
  isTorConfigOK=$(sudo cat ${TORRC} 2>/dev/null | grep -c "Bitcoin")
  if [ ${isTorConfigOK} -eq 0 ]; then
    echo "# - updating Tor config ${TORRC}"
    cat > ./torrc <<EOF
######################################################
## BLITZ MAIN CONFIGURATION
### torrc for tor@default
### See 'man tor', or https://www.torproject.org/docs/tor-manual.html

DataDirectory ${DATA_DIR}/sys
PidFile ${DATA_DIR}/sys/tor.pid

SafeLogging 0
Log notice stdout
Log notice file ${DATA_DIR}/notice.log
Log info file ${DATA_DIR}/info.log

RunAsDaemon 1
ControlPort 9051
SocksPort 9050
ExitRelay 0
CookieAuthentication 1
CookieAuthFileGroupReadable 1
######################################################

######################################################
## TO OVERCOME CENSORSHIP, START HERE!
## If you like to use bridges to overcome censorship, EDIT THE LINES BELOW!
## To use bridges, uncomment the three lines below...
#UseBridges 1
#UpdateBridgesFromAuthority 1
#ClientTransportPlugin meek_lite,obfs4 exec /usr/bin/obfs4proxy
#ClientTransportPlugin snowflake exec PluggableTransports/snowflake-client -url https://snowflake-broker.azureedge.net/ -front ajax.aspnetcdn.com -ice stun:stun.l.google.com:19302,stun:stun.voip.blackberry.com:3478,stun:stun.altar.com.pl:3478,stun:stun.antisip.com:3478,stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,stun:stun.sonetel.net:3478,stun:stun.stunprotocol.org:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.voys.nl:3478

## Meek-Azure
#Bridge meek_lite 0.0.2.0:2 97700DFE9F483596DDA6264C4D7DF7641E1E39CE url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com

## Snowflake
#Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72

## OBFS4 bridges
##
## You have two ways to get new bridge-addresses:
## 1. Get them here https://bridges.torproject.org/
##    (chose "Advanced Options", "obfs4" and press "Get Bridges)
## 2. Or send an email to bridges@torproject.org, using an address
##    from Riseup or Gmail with "get transport obfs4" in the body of the mail.
#Bridge obfs4 144.217.20.138:80 FB70B257C162BF1038CA669D568D76F5B7F0BABB cert=vYIV5MgrghGQvZPIi1tJwnzorMgqgmlKaB77Y3Z9Q/v94wZBOAXkW+fdx4aSxLVnKO+xNw iat-mode=0
#Bridge obfs4 192.95.36.142:443 CDF2E852BF539B82BD10E27E9115A31734E378C2 cert=qUVQ0srL1JI/vO6V6m/24anYXiJD3QP2HgzUKQtQ7GRqqUvs7P+tG43RtAqdhLOALP7DJQ iat-mode=1
#Bridge obfs4 [2001:470:b381:bfff:216:3eff:fe23:d6c3]:443 CDF2E852BF539B82BD10E27E9115A31734E378C2 cert=qUVQ0srL1JI/vO6V6m/24anYXiJD3QP2HgzUKQtQ7GRqqUvs7P+tG43RtAqdhLOALP7DJQ iat-mode=1
#Bridge obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=0
#Bridge obfs4 109.105.109.165:10527 8DFCD8FB3285E855F5A55EDDA35696C743ABFC4E cert=Bvg/itxeL4TWKLP6N1MaQzSOC6tcRIBv6q57DYAZc3b2AzuM+/TfB7mqTFEfXILCjEwzVA iat-mode=1
#Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0
#Bridge obfs4 85.31.186.26:443 91A6354697E6B02A386312F68D82CF86824D3606 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=0
#Bridge obfs4 109.105.109.147:13764 BBB28DF0F201E706BE564EFE690FE9577DD8386D cert=KfMQN/tNMFdda61hMgpiMI7pbwU1T+wxjTulYnfw+4sgvG0zSH7N7fwT10BI8MUdAD7iJA iat-mode=2
#Bridge obfs4 104.153.209.217:30262 D28E0345809AE4BAC903EF7FC78CAAF111A63C58 cert=DtNNYXeRG4ds+iTM7sdbJHJgH7RmxDb1lt8JR17BiT7eHnORyn+4y+RcoqAI65XGvhXKJg iat-mode=0
#Bridge obfs4 212.101.26.106:443 594A38734ACA5A611AF3C4444A914E5F940BCAAF cert=cNymj+v4Orz558wzvDYjmhVAEcFW1xKjbyVf/xUp+M6OoOvNRixvxLpyoY0SPsXSxIneFw iat-mode=0
#Bridge obfs4 50.115.168.41:443 BD0443DBEB32E9C96290DDFFB2F8B8681906D2BB cert=zqc3tU9Bw7uYfTi5AydGZC1pFu/UVpWRS3c4gzfS/qtCxJwC94d1XrKb116qoW/MZ8soTw iat-mode=0
#Bridge obfs4 34.255.123.165:52176 EFF298A7FB2A1056189C5C12B46CD912AA77B16A cert=5CLOANyguG1hzulvbHZNlWy2BoMGk/VTAyfKvA7S0w0v/24XIYTz5tWlKWbyrZhxPEvWFA iat-mode=0
#Bridge obfs4 198.98.59.76:80 2E18F504F27DFC23B5A716BB157C281874265AD1 cert=RHJPe84Blvxm7FiRTDQ/CAdERigYU0KTWUivRDqJm7tOkmpE/p4ZcNKB9kH8SSa/FfKmTw iat-mode=0
#Bridge obfs4 192.155.95.222:53050 68FE1B7511B5956D81DDDD23B30B49828DF36D21 cert=r8elMzelcc8b4wvG6MdvBrOTXWshKiDi1gPbpSgjgDJGzqLC2iGHiZ+GRx9gAZALlcqQPA iat-mode=0
#Bridge obfs4 78.47.50.242:19080 B6BD71FC589EB436C82D75FF30BBAC3A35E23E63 cert=RRNBu00BNAhJV+npPtTU6ocWK6jvhbDQ2Lx5ABXtc4pTk7PIWWxZVroQTScpuHqjg9lfMA iat-mode=0
#Bridge obfs4 93.104.174.209:55405 3C3893086B27E879778E4A6275E5230AA49132E9 cert=uZorJsxG11sfGmt2tsJRX6jCDQF043crM0vfsY+BJUdciPsszVN1eAem2zNteZ2WVjFqLg iat-mode=0
#Bridge obfs4 92.74.108.88:9043 129553DE394807C826C2088B6B4DF85C3DC7646B cert=I+VY1kfKNV6u62BhJq94lIzqxbguYGo5dQFg6Nb9b6+EvONHg4TsSPgxTN+f7aHyJeM/SQ iat-mode=0
#Bridge obfs4 94.16.156.109:36739 491CEAB740FDEA24D588B28C6915E6EC37D65B90 cert=Vax0EBHOO0x1NGjVJPNCECfTK9XSGy8IVjBk/ewyeoBq+o1i9/ksmKBj+XmMpUc5BCCzOQ iat-mode=0
#Bridge obfs4 109.105.109.165:10527 8DFCD8FB3285E855F5A55EDDA35696C743ABFC4E cert=Bvg/itxeL4TWKLP6N1MaQzSOC6tcRIBv6q57DYAZc3b2AzuM+/TfB7mqTFEfXILCjEwzVA iat-mode=1
#Bridge obfs4 85.31.186.26:443 91A6354697E6B02A386312F68D82CF86824D3606 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=0
#Bridge obfs4 216.252.162.21:46089 0DB8799466902192B6C7576D58D4F7F714EC87C1 cert=XPUwcQPxEXExHfJYX58gZXN7mYpos7VNAHbkgERNFg+FCVNzuYo1Wp+uMscl3aR9hO2DRQ iat-mode=0
#Bridge obfs4 76.230.156.129:5002 B37BC162454314B6572F9A3A79A1C92BB9E63809 cert=IIJMWkUUmzRbS78LCm8znYKvMf/mmcWIM5ZNyzwl1gHxKievV4h1NKdlVkRH3KpZH/fmbg iat-mode=0
#Bridge obfs4 95.31.12.22:5010 5721D25FA2D0194E698EC46AC4703F24DE82829F cert=whNT5Nx/k1fZL4MQu99SIl+5OXccyAlMKwjKmjoTGTgPTdVSNeMnh6lPBxcqbx4vMdRTTQ iat-mode=0
#Bridge obfs4 185.185.251.132:443 91C99EA7DD3851DC18F40D66D9283829AECC95C3 cert=i9dbEJaVF+4Keam69Bg5lbtfDiITFc2i7Otly9OEBmxBPq8xk2Nr5BWOOYlslTFdfPKFfg iat-mode=0
#Bridge obfs4 76.217.52.130:9030 D3D09370EB7F0988D0E7C8B4C495C2B015E7375C cert=NjQZ25njAQxVx3Z3WLzEyop7NemZs/YZZ7UCJDI/4pvJJPPeMrScI1N3TbcY1g0l8mC9DQ iat-mode=0
#Bridge obfs4 70.134.63.129:7005 1259A98554879633891EA67A3D8DCF8E7C6F87C2 cert=2kM4mcKyRdIhxzB9Pc9SdcXCE7j49nASJhrhxUi+PzBATuODugh36GHijWaZf01/ACEGaA iat-mode=0
#Bridge obfs4 193.11.166.194:27025 1AE2C08904527FEA90C4C4F8C1083EA59FBC6FAF cert=ItvYZzW5tn6v3G4UnQa6Qz04Npro6e81AP70YujmK/KXwDFPTs3aHXcHp4n8Vt6w/bv8cA iat-mode=0
#Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0
#Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0
#Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0
#Bridge obfs4 [2a0c:4d80:42:702::1]:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0
#Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0
#Bridge obfs4 38.229.1.78:80 C8CBDB2464FC9804A69531437BCF2BE31FDD2EE4 cert=Hmyfd2ev46gGY7NoVxA9ngrPF2zCZtzskRTzoWXbxNkzeVnGFPWmrTtILRyqCTjHR+s9dg iat-mode=1
#Bridge obfs4 38.229.33.83:80 0BAC39417268B96B9F514E7F63FA6FBA1A788955 cert=VwEFpk9F/UN9JED7XpG1XOjm/O8ZCXK80oPecgWnNDZDv5pdkhq1OpbAH0wNqOT6H6BmRQ iat-mode=1
#Bridge obfs4 193.11.166.194:27015 2D82C2E354D531A68469ADF7F878FA6060C6BACA cert=4TLQPJrTSaDffMK7Nbao6LC7G9OW/NHkUwIdjLSS3KYf0Nv4/nQiiI8dY2TcsQx01NniOg iat-mode=0
#Bridge obfs4 193.11.166.194:27020 86AC7B8D430DAC4117E9F42C9EAED18133863AAF cert=0LDeJH4JzMDtkJJrFphJCiPqKx7loozKN7VNfuukMGfHO0Z8OGdzHVkhVAOfo1mUdv9cMg iat-mode=0
######################################################

######################################################
## HIDDEN SERVICES
# Hidden Service for WEB ADMIN INTERFACE
HiddenServiceDir ${DATA_DIR}/web80/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80

# Hidden Service for LND RPC
HiddenServiceDir ${DATA_DIR}/lndrpc10009/
HiddenServiceVersion 3
HiddenServicePort 10009 127.0.0.1:10009

# Hidden Service for LND REST
HiddenServiceDir ${DATA_DIR}/lndrest8080/
HiddenServiceVersion 3
HiddenServicePort 8080 127.0.0.1:8080
EOF
    sudo rm ${TORRC}
    sudo mv ./torrc ${TORRC}
    sudo chmod 644 ${TORRC}
    sudo chown -R ${OWNER_DATA_DIR}:${OWNER_DATA_DIR} /var/run/tor/ 2>/dev/null
    echo ""

    sudo mkdir -p /etc/systemd/system/tor@default.service.d
    sudo tee /etc/systemd/system/tor@default.service.d/raspiblitz.conf >/dev/null <<EOF
    # DO NOT EDIT! This file is generated by raspiblitz and will be overwritten
[Service]
ReadWriteDirectories=-${DATA_DIR}
[Unit]
After=network.target nss-lookup.target mnt-hdd.mount
EOF

  else
    echo "# - Tor config ${TORRC} is already updated"
  fi

  # ACTIVATE Tor SERVICE
  echo "*** Enable Tor Service ***"
  sudo systemctl daemon-reload
  sudo systemctl enable tor@default
  echo ""

  # INSTALL TOR
  echo "*** Adding KEYS Tor Project Organization keys for Debian packages ***"
  torsocks wget -qO- ${SOURCES_TOR_UPDATE_ONION}/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --import
  sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -
  torKeyAvailable=$(sudo gpg --list-keys | grep -c "A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89")
  if [ ${torKeyAvailable} -eq 0 ]; then
    echo "!!! FAIL: Was not able to import Tor Project Organization keys for Debian packages "
    exit 1
  fi
  echo "- OK key added"

  echo "*** Adding Tor Sources to sources.list ***"
  torSourceListAvailable=$(sudo grep -c 'torproject.org' /etc/apt/sources.list.d/tor.list)
  echo "torSourceListAvailable=${torSourceListAvailable}"
  if [ ${torSourceListAvailable} -eq 0 ]; then
    echo "- adding TOR sources ..."
      echo "- using: deb [arch=arm64] ${SOURCES_TOR_UPDATE_ONION}torproject.org ${DISTRIBUTION} main"
      echo "deb [arch=arm64] ${SOURCES_TOR_UPDATE_ONION}torproject.org ${DISTRIBUTION} main" | sudo tee -a /etc/apt/sources.list.d/tor.list
      echo "deb-src [arch=arm64] ${SOURCES_TOR_UPDATE_ONION}torproject.org ${DISTRIBUTION} main" | sudo tee -a /etc/apt/sources.list.d/tor.list
    fi
    echo "- OK sources added"
  else
    echo "Tor sources are available"
  fi

  echo "*** Install & Enable Tor ***"
  sudo apt update
  sudo apt install -y tor nyx torsocks obfs4proxy
  echo ""

  # ACTIVATE BITCOIN OVER Tor (function call)
  activateBitcoinOverTor

  # ACTIVATE LND OVER Tor (function call)
  activateLndOverTor

  # ACTIVATE APPS OVER Tor
  source ${CONF} 2>/dev/null

  # for organizatation, FROM_PORT_2 is the TLS one

  if [ "${sshTor}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} ssh 22 22
    if [ "${sshTorOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on ssh
    fi
  fi

  if [ "${BTCRPCexplorer}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} btc-rpc-explorer 80 3002
    if [ "${BTCRPCexplorerOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on btc-rpc-explorer
    fi
  fi

  if [ "${rtlWebinterface}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} RTL 80 3002 443 3003
    if [ "${rtlWebinterfaceOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on RTL
    fi
  fi

  if [ "${BTCPayServer}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} btcpay 80 23002 443 23003
    if [ "${BTCPayServerOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on btcpay
    fi
  fi

  if [ "${ElectRS}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} electrs 50001 50001 50002 50002
  fi

  if [ "${LNBits}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} lnbits 80 5002 443 5003
    if [ "${LNBitsOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on lnbits
    fi
  fi

  if [ "${thunderhub}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} thunderhub 80 3012 443 3013
    if [ "${thunderhubAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on thunderhub
    fi
  fi

  if [ "${specter}" = "on" ]; then
    # specter makes only sense to be served over https
    ${ONION_SERVICE_SCRIPT} cryptoadvance-specter 443 25441
    if [ "${specterOnionAuth}" = "on" ]; then
      ${ONION_SERVICE_SCRIPT} auth on cryptoadvance-specter
    fi
  fi

  if [ "${sphinxrelay}" = "on" ]; then
    ${ONION_SERVICE_SCRIPT} sphinxrelay 80 3302 443 3303
    toraddress=$(sudo cat${DATA_DIR}/sphinxrelay/hostname 2>/dev/null)
    sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"
  fi

    # get Tor address and store it readable for sphixrelay user
    toraddress=$(sudo cat ${DATA_DIR}/sphinxrelay/hostname 2>/dev/null)
    sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"

  echo "Setup logrotate"
  # add logrotate config for modified Tor dir on ext. disk
  sudo tee /etc/logrotate.d/raspiblitz-tor >/dev/null <<EOF
${DATA_DIR}/*log {
        daily
        rotate 5
        compress
        delaycompress
        missingok
        notifempty
        create 0640 debian-tor debian-tor
        sharedscripts
        postrotate
                if invoke-rc.d tor status > /dev/null; then
                        invoke-rc.d tor reload > /dev/null
                fi
        endscript
}
EOF

  sudo systemctl restart tor@default

  echo "OK - Tor is now ON"
  echo "needs reboot to activate new setting"
  exit 0
fi
