Working with the ODroid HC1 and this image: https://dietpi.com/downloads/images/DietPi_OdroidXU4-ARMv7-Stretch.7z

Getting started with DietPi: https://dietpi.com/phpbb/viewtopic.php?f=8&t=9#p9

Login to DietPi  
username = root  
password = dietpi  
DietPi also comes pre-installed with Dropbear SSH Server.

`ssh root@[IP-OF-DIETPI]`  
password: `dietpi`
Ok > Cancel > Cancel
automatic apt update & apt upgrade on first logon and reboots
Opt out of survey > Ok > Ok

`ssh root@[IP-OF-DIETPI]`

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

run (copy from the terminal output): `ssh-keygen -f "/home/buidl/.ssh/known_hosts" -R "dietpi.IP"`

`ssh root@[IP-OF-DIETPI]`  
Ok > Install fail2ban > Install > Ok  
Reboots again

`ssh root@[IP-OF-DIETPI]`
Now only the bash prompt opens

use: wget https://raw.githubusercontent.com/[GITHUB-USERNAME]/raspiblitz/[BRANCH]/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh [BRANCH] [GITHUB-USERNAME]

`wget https://raw.githubusercontent.com/openoms/HardwareNode/OdroidHC1Debug/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh OdroidHC1Debug openoms`

see my output: [sdcard_build_output](DietPi/sdcard_build_output)  

`ssh admin@[IP-OF-DROIDBLITZ]`  
password: raspiblitz

and continue as in the RaspiBlitz setup [README.md](README.md)


