Working with the ODroid HC1 and this image: https://dietpi.com/downloads/images/DietPi_OdroidXU4-ARMv7-Stretch.7z

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
"Do you wish to continue with DietPi as a pure minimal image?"  
Ok  
Reboots again

`ssh root@[IP-OF-YOUR-DIETPI]`
Now only the bash prompt opens

use: wget https://raw.githubusercontent.com/[GITHUB-USERNAME]/raspiblitz/[BRANCH]/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh [BRANCH] [GITHUB-USERNAME]

`wget https://raw.githubusercontent.com/openoms/HardwareNode/OdroidHC1Debug/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh OdroidHC1Debug openoms`

see my output: [sdcard_build_output](sdcard_build_output.html)  
The only fault appears to be with `fail2ban`

 
`ssh admin@[IP-OF-YOUR-DROIDBLITZ]`.
password: raspiblitz

The raspiblitz GUI and setup worked I until I needed to get the blockchain data.

On the attempt to copy the blockchain from the HDD of a Raspiblitz the ODroid did not mount the 2nd HDD properly.
It appeared as `sdb` and as `sda` after reboot:
![](after_reboot_with_2nd_HDD.png)

 Copied the blockchain manually on my main computer to the root /bitcoin folder  
 Reinserted the HDD to the ODroid and booted up
 
 ssh admin@[IP-OF-YOUR-DROIDBLITZ]  
`./60finishHDD.sh` 

got this output here: [initial_setup_output](initial_setup_output.html)
and the same when tried again with a rebuilt sdcard.

Stuck here now: 
```
Failed to connect to bus: No such file or directory
1548191939
LND not ready yet ... waiting another 60 seconds.
If this takes too long (more then 10min total) --&gt; CTRL+c and report Problem
```

