# ⚡️ RaspiBlitz-on-DietPi ⚡️
# Rock64


* Download the DietPi Image for the Rock64: https://dietpi.com/downloads/images/DietPi_Rock64-ARMv8-Stretch.7z

* Burn the image to the SDCard with Etcher.

## Automate the SDcard building process

* Copy two files to the /boot dicectory of the DietPi SDcard:

    [DietPi.txt](/dietpi/boot/dietpi.txt) - Overwrites the default dietpi.txt. Modified the settings to automate the DietPi setup. (see the details [here](https://github.com/rootzoll/raspiblitz/tree/master/dietpi#excerpts-from-the-default-dietpitxt))

    [Automation_Custom_Script.sh](/dietpi/boot/Automation_Custom_Script.sh) - Runs after DietPi installation is completed. Contains the link to download and to run the build_sdcard.sh from @openoms, tested on the Rock64.

* Insert the SDcard into your Rock64.

* Connect the HDD.

* The setup will run automatically and the Rock64 will restart at least twice during the process. Give it circa 20 mins. Log in with `root` if you want to follow along. The build_sdcard.ah script output can be seen with: `tail -n1000 -f /var/tmp/dietpi/logs/dietpi-automation_custom_script.log`

* When the setup is finished log in as `admin`:  
`ssh admin@[IP-OF-RASPIBLITZ]`  
password: `raspiblitz`

* From here he setup continues with the [RaspiBlitz Setup Process](https://github.com/rootzoll/raspiblitz/blob/master/README.md#setup-process-detailed-documentation)

## To build manually
* Follow the generic DietPi install process to [build your own SDCard](https://github.com/rootzoll/raspiblitz/tree/master/dietpi#general-guide-for-the-raspiblitz-on-dietpi)

* Use the rock64 branch from @openoms to build the SDcard:  
`wget https://raw.githubusercontent.com/openoms/raspiblitz/rock64/build_sdcard.sh && sudo bash build_sdcard.sh rock64 openoms`  