# Download and run this script to the Linux desktop:

# Download
# wget https://raw.githubusercontent.com/openoms/bitcoin-tutorials/master/electrs/electrum_wallet.sh 
# Run:
# bash electrum_wallet.sh

echo "
Enter the version of Electrum Wallet to install. 

Find the latest version number at:
https://electrum.org/#download

For example: '3.3.8' or '4.0.0b0'"
read electrumVersion

echo "
Install dependencies: python3-pyqt5 and libsecp256k1-0
"
sudo apt-get install -y python3-pyqt5 libsecp256k1-0

echo "
Download the package: 	
https://download.electrum.org/$electrumVersion/Electrum-$electrumVersion.tar.gz
"
rm -f Electrum-$electrumVersion.tar.gz.*
wget https://download.electrum.org/$electrumVersion/Electrum-$electrumVersion.tar.gz

echo "
Verify signature
"
rm -f ThomasV.asc
wget https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/ThomasV.asc
gpg --import ThomasV.asc
wget https://download.electrum.org/$electrumVersion/Electrum-$electrumVersion.tar.gz.asc
verifyResult=$(gpg --verify Electrum-$electrumVersion.tar.gz.asc 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
if [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> PGP Verify not OK / signature(${goodSignature})"
  exit 1
fi

echo "
Installing with the command:
python3 -m pip install --user Electrum-$electrumVersion.tar.gz[fast]
"
# Run without installing: 	tar -xvf Electrum-$electrumVersion.tar.gz
# python3 Electrum-$electrumVersion/run_electrum
# Install with PIP: 	
sudo apt-get install -y python3-setuptools python3-pip
python3 -m pip install --user Electrum-$electrumVersion.tar.gz[fast]

isInPath=$(echo $PATH | grep -c ~/.local/bin)
if [ $isInPath -eq 0 ]; then
  echo ""
  echo "add install dir to PATH"
  PATH=$PATH:~/.local/bin
  touch ~/.profile
  export PATH
  echo "PATH=$PATH" | tee -a ~/.profile
else 
  echo ""
  echo "The install dir is already in the PATH"
fi

echo "
To start use:
'electrum --oneserver --server YOUR_ELECTRUM_SERVER_IP:50002:s'

To start with your custom server now and save the setting:
type the LAN_IP_ADDRESS of your Electrum Server followed by [ENTER]:"
read RASPIBLITZ_IP

echo "
Make the oneserver config persist (editing ~/.electrum/config)
"
electrum setconfig oneserver true
electrum setconfig server $RASPIBLITZ_IP:50002:s

echo "
To run with the chosen server, just use:
'electrum'

To change the preset server:
edit the file ~/.electrum/config and change:
\"server\": \"<your__ IP_domain_or_dynDNS>:50002:s\"
"

electrum --oneserver --server $RASPIBLITZ_IP:50002:s 