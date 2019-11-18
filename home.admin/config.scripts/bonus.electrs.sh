#!/bin/bash

# https://github.com/romanz/electrs/blob/master/doc/usage.md

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch the Electrum Rust Server on or off"
 echo "bonus.btc-rcp-explorer.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if [ ${#ElectRS} -eq 0 ]; then
  echo "ElectRS=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop service
echo "making sure services are not running"
sudo systemctl stop electrs 2>/dev/null


# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL ELECTRS ***"

  isInstalled=$(sudo ls /etc/systemd/system/electrs.service 2>/dev/null | grep -c 'electrs.service')
  if [ ${isInstalled} -eq 0 ]; then

    #cleanup
    sudo systemctl stop electrs
    sudo systemctl disable electrs
    sudo rm -f /etc/systemd/system/electrs.service
    sudo rm -f /home/electrs/.electrs/config.toml 

    echo ""
    echo "***"
    echo "Creating the electrs user"
    echo "***"
    echo ""
    sudo adduser --disabled-password --gecos "" electrs
    cd /home/electrs

    echo ""
    echo "***"
    echo "Installing Rust"
    echo "***"
    echo ""
    sudo -u electrs curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u electrs sh -s -- -y
    # check Rust version with: $ sudo -u electrs /home/electrs/.cargo/bin/cargo --version
    # workaround to keep Rust at v1.37.0
    # sudo -u electrs /home/electrs/.cargo/bin/rustup install 1.37.0 --force
    # sudo -u electrs /home/electrs/.cargo/bin/rustup override set 1.37.0

    #source $HOME/.cargo/env
    sudo apt update
    sudo apt install -y clang cmake  # for building 'rust-rocksdb'

    echo ""
    echo "***"
    echo "Downloading and building electrs. This will take ~30 minutes" # ~22 min on an Odroid XU4
    echo "***"
    echo ""
    sudo -u electrs git clone https://github.com/romanz/electrs
    cd /home/electrs/electrs
    sudo -u electrs /home/electrs/.cargo/bin/cargo build --release

    echo ""
    echo "***"
    echo "The electrs database will be built in /mnt/hdd/electrs/db. Takes ~18 hours and ~50Gb diskspace"
    echo "***"
    echo ""
    sudo mkdir /mnt/hdd/electrs 2>/dev/null
    sudo chown -R electrs:electrs /mnt/hdd/electrs

    echo ""
    echo "***"
    echo "getting RPC credentials from the bitcoin.conf"
    echo "***"
    echo ""
    #echo "Type the PASSWORD B of your RaspiBlitz followed by [ENTER] (needed for Electrs to access the bitcoind RPC):"
    #read PASSWORD_B
    RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    echo "Done"

    echo ""
    echo "***"
    echo "generating electrs.toml setting file with the RPC passwords"
    echo "***"
    echo ""
    # generate setting file: https://github.com/romanz/electrs/issues/170#issuecomment-530080134
    # https://github.com/romanz/electrs/blob/master/doc/usage.md#configuration-files-and-environment-variables

    sudo -u electrs mkdir /home/electrs/.electrs 2>/dev/null
    touch /home/admin/config.toml
    chmod 600 /home/admin/config.toml || exit 1 
    cat > /home/admin/config.toml <<EOF
verbose = 4
timestamp = true
jsonrpc_import = true
db_dir = "/mnt/hdd/electrs/db"
cookie = "$RPC_USER:$PASSWORD_B"
EOF
    sudo mv /home/admin/config.toml /home/electrs/.electrs/config.toml
    sudo chown electrs:electrs /home/electrs/.electrs/config.toml

    echo ""
    echo "***"
    echo "Open port 50001 on UFW "
    echo "***"
    echo ""
    sudo ufw allow 50001

    echo ""
    echo "***"
    echo "Checking for config.toml"
    echo "***"
    echo ""
    if [ ! -f "/home/electrs/.electrs/config.toml" ]
        then
            echo "Failed to create config.toml"
            exit 1
        else
            echo "OK"
    fi

    echo ""
    echo "***"
    echo "installing Nginx"
    echo "***"
    echo ""

    sudo apt-get install -y nginx
    sudo /etc/init.d/nginx start

    # Only generate if there is none. Or Electrum will not connect if the cert changed.
    if [ -f /etc/ssl/certs/localhost.crt ] ; then
        echo "skiping self signed SSL certificate" 
    else
        echo ""
        echo "***"
        echo "Create a self signed SSL certificate"
        echo "***"
        echo ""
        
        #https://www.humankode.com/ssl/create-a-selfsigned-certificate-for-nginx-in-5-minutes
        #https://stackoverflow.com/questions/8075274/is-it-possible-making-openssl-skipping-the-country-common-name-prompts

        echo "
[req]
prompt             = no
default_bits       = 2048
default_keyfile    = localhost.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca

[req_distinguished_name]
C = US
ST = California
L = Los Angeles
O = Our Company Llc
#OU = Org Unit Name
CN = Our Company Llc
#emailAddress = info@example.com

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1   = localhost
DNS.2   = 127.0.0.1
        " | sudo tee /mnt/hdd/electrs/localhost.conf

        cd /mnt/hdd/electrs
        sudo openssl req -x509 -nodes -days 1825 -newkey rsa:2048 -keyout localhost.key -out localhost.crt -config localhost.conf

        sudo cp localhost.crt /etc/ssl/certs/localhost.crt
        sudo cp localhost.key /etc/ssl/private/localhost.key

    fi

    echo ""
    echo "***"
    echo "Setting up nginx.conf"
    echo "***"
    echo ""

    isElectrs=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'upstream electrs')
    if [ ${isElectrs} -gt 0 ]; then
            echo "electrs is already configured with Nginx. To edit manually run \`sudo nano /etc/nginx/nginx.conf\`"

    elif [ ${isElectrs} -eq 0 ]; then

            isStream=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'stream {')
            if [ ${isStream} -eq 0 ]; then

            echo "
stream {
        upstream electrs {
                server 127.0.0.1:50001;
        }
        server {
                listen 50002 ssl;
                proxy_pass electrs;
                ssl_certificate /etc/ssl/certs/localhost.crt;
                ssl_certificate_key /etc/ssl/private/localhost.key;
                ssl_session_cache shared:SSL-electrs:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

            elif [ ${isStream} -eq 1 ]; then
                    sudo truncate -s-2 /etc/nginx/nginx.conf
                    echo "
        upstream electrs {
                server 127.0.0.1:50001;
        }
        server {
                listen 50002 ssl;
                proxy_pass electrs;
                ssl_certificate /etc/ssl/certs/localhost.crt;
                ssl_certificate_key /etc/ssl/private/localhost.key;
                ssl_session_cache shared:SSL-electrs:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

            elif [ ${isStream} -gt 1 ]; then
                    echo " Too many \`stream\` commands in nginx.conf. Please edit manually: \`sudo nano /etc/nginx/nginx.conf\` and retry"
                    exit 1
            fi
    fi

    echo "allow port 50002 on ufw"
    sudo ufw allow 50002

    sudo systemctl enable nginx
    sudo systemctl restart nginx

    echo ""
    echo "***"
    echo "Installing the systemd service"
    echo "***"
    echo ""

    # sudo nano /etc/systemd/system/electrs.service 
    echo "
[Unit]
Description=Electrs
After=bitcoind.service

[Service]
WorkingDirectory=/home/electrs/electrs
ExecStart=/home/electrs/electrs/target/release/electrs --index-batch-size=10 --electrum-rpc-addr=\"0.0.0.0:50001\"
User=electrs
Group=electrs
Type=simple
KillMode=process
TimeoutSec=60
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
    " | sudo tee -a /etc/systemd/system/electrs.service
    sudo systemctl enable electrs
    sudo systemctl start electrs
    # manual start:
    # sudo -u electrs /home/electrs/.cargo/bin/cargo run --release -- --index-batch-size=10 --electrum-rpc-addr="0.0.0.0:50001"
    echo ""
    echo "***"
    echo "Starting ElectRS in the background"
    echo "***"
    echo ""

  else 
    echo "ElectRS already installed."
    # start service
    echo "start service"
    sudo systemctl start electrs 2>/dev/null
  fi

  # Hidden Service for electrs if Tor active
  if [ "${runBehindTor}" = "on" ]; then
    isElectrsTor=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c 'electrs')
    if [ ${isElectrsTor} -eq 0 ]; then
      echo "
# Hidden Service for Electrum Server
HiddenServiceDir /mnt/hdd/tor/electrs
HiddenServiceVersion 3
HiddenServicePort 50002 127.0.0.1:50002
      " | sudo tee -a /etc/tor/torrc

      sudo systemctl restart tor
      sleep 2
    else
      echo "The Hidden Service is already installed"
    fi
    
    TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/electrs/hostname)
    if [ -z "$TOR_ADDRESS" ]; then
      echo "Waiting for the Hidden Service"
      sleep 10
      TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/electrs/hostname)
        if [ -z "$TOR_ADDRESS" ]; then
        echo " FAIL - The Hidden Service address could not be found - Tor error?"
        exit 1
        fi
    fi    
    echo ""
    echo "***"
    echo "The Tor Hidden Service address for electrs is:"
    echo "$TOR_ADDRESS"
    echo "Electrum wallet: to connect through Tor open the Tor Browser and start with the options:" 
    echo "\`electrum --oneserver --server=$TOR_ADDRESS:50002:s --proxy socks5:127.0.0.1:9150\`"
    echo "***"
    echo "" 
  fi

  ## Enable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  if [ "${BTCRPCexplorer}" = "on" ]; then
      # Enable BTCEXP_ADDRESS_API if electrs is active
      if [ $(sudo -u bitcoin lsof -i | grep -c 50001) -eq 1 ]; then
        echo "electrs is active - switching support on"
        sudo -u bitcoin sed -i '/BTCEXP_ADDRESS_API=electrumx/s/^#//g' /home/bitcoin/.config/btc-rpc-explorer.env
        sudo -u bitcoin sed -i '/BTCEXP_ELECTRUMX_SERVERS=/s/^#//g' /home/bitcoin/.config/btc-rpc-explorer.env
      else
        echo "electrs is not active - switching support off"
        sudo -u bitcoin sed -i '/BTCEXP_ADDRESS_API=electrumx/s/^/#/g' /home/bitcoin/.config/btc-rpc-explorer.env
        sudo -u bitcoin sed -i '/BTCEXP_ELECTRUMX_SERVERS=/s/^/#/g' /home/bitcoin/.config/btc-rpc-explorer.env    
      fi
  fi

  echo ""
  echo "To connect through SSL from outside of the local network make sure the port 50002 is forwarded on the router"
  echo "Electrum wallet: start with the options \`electrum --oneserver --server RaspiBlitz_IP:50002:s\`"
  echo ""
  
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^ElectRS=.*/ElectRS=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/electrs.service 2>/dev/null | grep -c 'electrs.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING ELECTRS ***"
    sudo systemctl stop electrs
    sudo systemctl disable electrs
    sudo rm /etc/systemd/system/electrs.service
    sudo rm -rf /home/electrs/.cargo
    sudo rm -rf /home/electrs/electrs
    echo "OK ElectRS removed."
    
    ## Disable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
    if [ "${BTCRPCexplorer}" = "on" ]; then
      echo "electrs is not active - switching support off"
      sudo -u bitcoin sed -i '/BTCEXP_ADDRESS_API=electrumx/s/^/#/g' /home/bitcoin/.config/btc-rpc-explorer.env
      sudo -u bitcoin sed -i '/BTCEXP_ELECTRUMX_SERVERS=/s/^/#/g' /home/bitcoin/.config/btc-rpc-explorer.env    
    fi
  else 
    echo "ELectRS is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
