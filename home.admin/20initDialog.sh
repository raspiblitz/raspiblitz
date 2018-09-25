#!/bin/sh
_temp="./download/dialog.$$"

# load network
network=`cat .network`

# welcome and ask for name of RaspiBlitz 
result=""
while [ ${#result} -eq 0 ]
  do
    l1="Please enter the name of your new RaspiBlitz:\n"
    l2="one word, keep characters basic & not too long"
    dialog --backtitle "RaspiBlitz - Setup" --inputbox "$l1$l2" 11 52 2>$_temp
    result=$( cat $_temp |  tr -d [:space:] )
    shred $_temp
  done

# set lightning alias
sed -i "s/^alias=.*/alias=${result}/g" /home/admin/assets/lnd.${network}.conf

# store hostname for later - to be set right before the next reboot
# work around - because without a reboot the hostname seems not updates in the whole system
echo $result > /home/admin/.hostname

# show password info dialog
dialog --backtitle "RaspiBlitz - Setup" --msgbox "RaspiBlitz uses 4 different passwords.
Referenced as password A, B, C and D.

A) Master User Password
B) Blockchain RPC Password
C) LND Wallet Password
D) LND Seed Password

Choose now 4 new passwords - all min 8 chars
Write them down & store them in a safe place.
" 14 52

# ask user for new password A
dialog --backtitle "RaspiBlitz - Setup"\
       --inputbox "Please enter your Master/Admin Password A:\n!!! This is new password to login per SSH !!!" 10 52 2>$_temp

# get user input
result=$( cat $_temp )
shred $_temp

# check input (check for more later)
if [ ${#result} -eq 0 ]; then
  clear
  echo "FAIL - Password cannot be empty"
  echo "Please restart with ./00mainMenu.sh"
  exit 1
fi

# change user passwords and then change hostname
echo "pi:$result" | sudo chpasswd
echo "root:$result" | sudo chpasswd
echo "bitcoin:$result" | sudo chpasswd
echo "admin:$result" | sudo chpasswd
sleep 1

# sucess info dialog
dialog --backtitle "RaspiBlitz" --msgbox "OK - password changed to '$result'\nfor all users pi, admin, root & bitcoin" 6 52

# repeat until user input is nit length 0
result=""
while [ ${#result} -lt 8 ]
  do
    dialog --backtitle "RaspiBlitz - Setup"\
       --inputbox "Enter your RPC Password B (min 8 chars):" 9 52 2>$_temp
    result=$( cat $_temp )
    shred $_temp
  done

# set Blockchain RPC Password (for admin cli & template for user bitcoin)
sed -i "s/^rpcpassword=.*/rpcpassword=${result}/g" /home/admin/assets/${network}.conf
sed -i "s/^${network}d.rpcpass=.*/${network}d.rpcpass=${result}/g" /home/admin/assets/lnd.${network}.conf

# success info dialog
dialog --backtitle "RaspiBlitz - SetUP" --msgbox "OK - RPC password changed to '$result'\n\nNow starting the Setup of your RaspiBlitz." 7 52
clear

# init get publicip service
getpublicipExists=$(sudo ls /usr/local/bin/getpublicip.sh 2>/dev/null | grep "getpublicip.sh" -c)
if [ ${getpublicipExists} -eq 0 ]; then
  echo "*** Installing getPublic ip script and service *** "
  sudo cp ./assets/getpublicip.sh /usr/local/bin/getpublicip.sh
  sudo chmod +x /usr/local/bin/getpublicip.sh
  sudo cp ./assets/getpublicip.service /etc/systemd/system/getpublicip.service
  sudo systemctl enable getpublicip
  sudo systemctl start getpublicip
  echo ""
fi