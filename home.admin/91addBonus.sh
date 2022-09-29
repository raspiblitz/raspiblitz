
mkdir /home/admin/tmpScriptDL
cd /home/admin/tmpScriptDL
echo "installing bash completion for bitcoin-cli and lncli"
wget https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/bitcoin-cli.bash-completion
wget https://raw.githubusercontent.com/lightningnetwork/lnd/master/contrib/lncli.bash-completion
sudo cp *.bash-completion /etc/bash_completion.d/
echo "OK - bash completion available after next login"
echo "type \"bitcoin-cli getblockch\", press [Tab] → bitcoin-cli getblockchaininfo"
rm -r /home/admin/tmpScriptDL

cd
