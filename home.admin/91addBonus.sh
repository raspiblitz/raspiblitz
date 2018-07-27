# https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_67_additional-scripts.md

echo "*** Adding: raspibolt_67_additional-scripts.md"
echo "Creating the command lnbalance as well as lnchannels which will give you a nicer output"
cd
mkdir /home/admin/tmpScriptDL
cd /home/admin/tmpScriptDL
wget https://raw.githubusercontent.com/Stadicus/guides/master/raspibolt/resources/lnbalance
wget https://raw.githubusercontent.com/Stadicus/guides/master/raspibolt/resources/lnchannels
chmod +x lnbalance
chmod +x lnchannels
sudo cp lnchannels /usr/local/bin
sudo cp lnbalance /usr/local/bin
echo "Done. Let's try them out"
cd
rm -r /home/admin/tmpScriptDL
echo "Output of lnbalance:"
lnbalance
echo "Output of lnchannels:"
lnchannels
