https://dietpi.com/phpbb/viewtopic.php?f=8&t=9#p9

Login to DietPi
username = root
password = dietpi
DietPi also comes pre-installed with Dropbear SSH Server.

`ssh root@[IP-OF-YOUR-DIETPI]`
password: `dietpi`

automatic apt update & apt upgrade on first logon and reboots

`ssh root@[IP-OF-YOUR-DIETPI]`

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

run: `ssh-keygen -f "/home/buidl/.ssh/known_hosts" -R "dietpi.IP"`

`ssh root@[IP-OF-YOUR-DIETPI]`  
Ok in the menu  
" Do you wish to continue with DietPi as a pure minimal image? "  
Ok
Reboots again

`ssh root@[IP-OF-YOUR-DIETPI]`
Now only the bash prompt opens

`wget https://raw.githubusercontent.com/rootzoll/raspiblitz/master/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh`

see my output: [sdcard_build_output](raspiblitz/DroidBllitz/sdcard_build_output)  
The only fault appears to be with `fail2ban`

 
`ssh admin@[IP-OF-YOUR-DROIDBLITZ]`.
password: raspiblitz

The raspiblitz GUI and setup worked I until I neded to get the blockchain data.

On the attempt to copy the blockchain from the HDD of a Raspiblitz the ODroid did not mount the 2nd HDD properly.
It appeared as `sdb` and as `sda` after reboot:
!()[droidblitz/DietPi/after_reboot_with_2nd_HDD.png]

 Copied the blockchain manually on my main computer to the root /bitcoin folder  
 Reinserted the HDDto the ODroid and booted up
 
 ssh admin@[IP-OF-YOUR-DROIDBLITZ]  
./60finishHDD.sh 

got the same output here: [initial_setup_output](DietPi/initial_setup_output)

and when restarted and built a fresh sdcard.