# disable RPC listen
# to prevent tls cer auth error
sudo sed -i "s/^rpclisten=0.0.0.0:10009/#rpclisten=0.0.0.0:10009/g" /mnt/hdd/lnd/lnd.conf
sudo systemctl restart lnd

# install latest nodejs
curl -sL https://deb.nodesource.com/setup_11.x | sudo -E bash -
sudo apt-get install -y nodejs

# close source code
git clone https://github.com/ShahanaFarooqui/RTL.git
cd RTL
npm install
cd ..

# open firewall
sudo ufw allow 3000
sudo ufw --force enable

# install service
sudo cp /home/admin/assets/RTL.service /etc/systemd/system/RTL.service
sudo systemctl enable RTL
sudo systemctl start RTL

sleep 2