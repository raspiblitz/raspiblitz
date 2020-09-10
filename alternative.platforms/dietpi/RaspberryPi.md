# ⚡️ RaspiBlitz-on-DietPi ⚡️
## Tested on the Raspberry Pi 3 B +

### The automated building process:

1) Download the DietPi image for the Raspberry Pi:   
https://dietpi.com/downloads/images/DietPi_RPi-ARMv6-Stretch.7z  

2) Burn it to the SD card with [Etcher](https://www.balena.io/etcher/)

3) Right click and download the following two files: [DietPi.txt](https://raw.githubusercontent.com/rootzoll/raspiblitz/master/alternative.platforms/dietpi/boot/dietpi.txt), [Automation_Custom_Script.sh](https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/alternative.platforms/dietpi/boot/Automation_Custom_Script.sh)

4) Copy them to the /boot directory of the DietPi SDcard

    [DietPi.txt](https://raw.githubusercontent.com/rootzoll/raspiblitz/master/alternative.platforms/dietpi/boot/dietpi.txt): Overwrites the default dietpi.txt. Modified the settings to automate the DietPi setup. (see the details [here](https://github.com/rootzoll/raspiblitz/tree/dev/alternative.platforms/dietpi#excerpts-from-the-customized-dietpitxt))

    [Automation_Custom_Script.sh](https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/alternative.platforms/dietpi/boot/Automation_Custom_Script.sh): Runs after DietPi installation is completed. Contains the link to download and run the build_sdcard.sh from the dev branch of @rootzoll.  
    (Optionally open the file with a text editor and uncomment (remove the `#` from the front of) the line with the branch you want to build the SDcard from.) 

5) Assemble and boot the Raspberry Pi

    Insert the SDcard, connect the HDD, network cable and power supply to boot.
    (The default LCD will be set up automatically)


    The automated setup will continue and the Raspberry Pi will restart at least twice during the process. This will take up to an hour.  
    To follow the logs during the automated building process login with `root` and press CTRL+C.  
    `tail -n1000 -f /tmp/DietPi-Update/dietpi-update.log` - follow the dietpi-update process  
    `tail -n1000 -f /var/tmp/dietpi/logs/dietpi-automation_custom_script.log` follow the output of the build_sdcard.sh  


6) When the setup is finished log in as `admin`:  
`ssh admin@[IP-OF-RASPIBLITZ]`  
password: `raspiblitz`

    The setup continues with the [RaspiBlitz Setup Process](https://github.com/rootzoll/raspiblitz/blob/dev/README.md#setup-process-detailed-documentation)

---
### To build manually:
[Follow the generic DietPi install process.](https://github.com/rootzoll/raspiblitz/tree/dev/alternative.platforms/dietpi#general-guide-for-the-raspiblitz-on-dietpi)
