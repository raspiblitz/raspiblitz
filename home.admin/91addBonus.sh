# https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_67_additional-scripts.md

echo ""
echo "*** Adding: raspibolt_67_additional-scripts.md"
echo "Creating the command lnbalance as well as lnchannels which will give you a nicer output"
cd
mkdir /home/admin/tmpScriptDL
cd /home/admin/tmpScriptDL
wget https://stadicus.github.io/RaspiBolt/resources/lnbalance
wget https://stadicus.github.io/RaspiBolt/resources/lnchannels
chmod +x lnbalance
chmod +x lnchannels
sudo cp lnchannels /usr/local/bin
sudo cp lnbalance /usr/local/bin
echo "OK"
echo "installing bash completion for bitcoin-cli and lncli"
wget https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/bitcoin-cli.bash-completion
wget https://raw.githubusercontent.com/lightningnetwork/lnd/master/contrib/lncli.bash-completion
sudo cp *.bash-completion /etc/bash_completion.d/
echo "OK - bash completion available after next login"
echo "type \"bitcoin-cli getblockch\", press [Tab] → bitcoin-cli getblockchaininfo"
cd
rm -r /home/admin/tmpScriptDL
