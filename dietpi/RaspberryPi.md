# ⚡️ RaspiBlitz-on-DietPi ⚡️
## Tested on the Raspberry Pi 3 B +

### Automated the SDcard building process:

* Download the DietPi image for the Raspberry Pi:   
https://dietpi.com/downloads/images/DietPi_RPi-ARMv6-Stretch.7z  
* Burn it to the SD card with [Etcher](https://www.balena.io/etcher/)

* Right click and download the following two files: [DietPi.txt](/dietpi/boot/dietpi.txt), [Automation_Custom_Script.sh](/dietpi/boot/Automation_Custom_Script.sh)
* Copy them to the /boot directory of the DietPi SDcard:

    [DietPi.txt](/dietpi/boot/dietpi.txt): Overwrites the default dietpi.txt. Modified the settings to automate the DietPi setup. (see the details [here](https://github.com/rootzoll/raspiblitz/tree/master/dietpi#excerpts-from-the-default-dietpitxt))

    [Automation_Custom_Script.sh](/dietpi/boot/Automation_Custom_Script.sh): Runs after DietPi installation is completed. Contains the link to download and run the build_sdcard.sh from the dev branch of @rootzoll.  
    (Optionally open the file with a text editor and uncomment (remove the `#` from the front of) the line with the branch you want to build the SDcard from.) 

* Insert the SDcard into your Raspberry Pi.

* Connect the HDD, network cable and power supply to boot. (The optional default LCD will be setup automtically)

* The automated setup will run and the Raspberry Pi will restart at least twice during the process. This will take up to an hour. Log in with `root` if you want to follow along. The build_sdcard.sh script output can be seen with: `tail -n1000 -f /var/tmp/dietpi/logs/dietpi-automation_custom_script.log`

* When the setup is finished log in as `admin`:  
`ssh admin@[IP-OF-RASPIBLITZ]`  
password: `raspiblitz`

* From here he setup continues with the [RaspiBlitz Setup Process](https://github.com/rootzoll/raspiblitz/blob/master/README.md#setup-process-detailed-documentation)

## To build manually
* Follow the generic DietPi install process to [build your own SDCard](https://github.com/rootzoll/raspiblitz/tree/master/dietpi#general-guide-for-the-raspiblitz-on-dietpi)
