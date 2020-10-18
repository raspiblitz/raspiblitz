BTCPAY 


    # use postgres for new btcpay instances where there is no sqllite.db to restore
    if [ ! -f "/home/btcpay/.btcpayserver/Main/sqllite.db" ]; then
      sudo -u btcpay touch /home/btcpay/.btcpayserver/Main/settings.config
      echo "
### Global settings ###
#network=mainnet

### Server settings ###
#port=23000
#bind=127.0.0.1
#httpscertificatefilepath=devtest.pfx
#httpscertificatefilepassword=toto

### Database ###
#postgres=User ID=root;Password=myPassword;Host=localhost;Port=5432;Database=myDataBase;
#mysql=User ID=root;Password=myPassword;Host=localhost;Port=3306;Database=/home/btcpay/.btcpayserver/Main/sqllite.db;

### NBXplorer settings ###
#BTC.explorer.url=http://127.0.0.1:24444/
#BTC.explorer.cookiefile=/home/btcpay/.nbxplorer/Main/.cookie
#BTC.lightning=/root/.lightning/lightning-rpc
#BTC.lightning=https://apitoken:API_TOKEN_SECRET@charge.example.com/
"     | sudo tee -a /home/btcpay/.btcpayserver/Main/settings.config
    fi