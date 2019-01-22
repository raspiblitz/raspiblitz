https://dietpi.com/phpbb/viewtopic.php?f=8&t=9#p9

Step 4:
Login to DietPi
username = root
password = dietpi
DietPi also comes pre-installed with Dropbear SSH Server.

ssh root@dietpi.IP
password: dietpi

automatic apt update & apt upgrade on first logon and reboots

ssh root@dietpi.IP

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

run: ssh-keygen -f "/home/buidl/.ssh/known_hosts" -R "dietpi.IP"

ssh root@dietpi.IP
Ok in the menu
" Do you wish to continue with DietPi as a pure minimal image? "
Ok
Reboots again

ssh root@dietpi.IP
no opens only the bash prompt

wget https://raw.githubusercontent.com/rootzoll/raspiblitz/master/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh

see my output: [](raspiblitz/DroidBllitz/sdcard_build_output)

 user `admin` 
 default password is now `raspiblitz`
 
 
 `ssh admin@[IP-OF-YOUR-RASPI]`.