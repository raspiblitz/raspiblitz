# Background: RaspiBlitz Settings

## Before Version 1.0

The RaspiBlitz started as small collection of shell scripts to setup a bitcoin+lightning node. At this time it was not needed to have settings file. The idea was that the scripts analyse the system state and make the changes required - automatically trying to catch up. That was OK as long RaspiBlitz was just a helper to setup your Lightning node and the rest was up to you.

Over time users that are running a RaspiBlitz expected that it can handle more complex setup and customization. Also it should be easy to update the system (exchange sd card with a newer image) and should be able to have the same configuration afterwards - keeping its state. Thats why starting from version 1.0 there will be a raspiblitz config file stored on the HDD that stores stores the config state.

## The Config File

The RaspiBlitz config file is stored on the HDD root:

`/mnt/hdd/raspiblitz.conf`

Its simple structure is: one key-value pair per line. In the end its bash-script syntax to define varibales. The RaspiBlitz shell scripts can import this file with:

`source /mnt/hdd/raspiblitz.conf`

After this line all the config values are available and can be worked with. I prefer to call this line in scripts explicitly and not setting this values as environment variables, because when you read as a newbie such a script, you get an idea where the config file is stored.

## The Config Values

So see what config parameters are available check the comments in the following script:

`/home/admin/_bootstrap.sh`

## Adding new Config Values

If you extend the RaspiBlitz scripts and you have the need to add a new config key-value add it to the `/home/admin/00enforceConfig.sh` script. There is a section for default values and setting them in the config file, if they dont exist there yet. Because this script runs on every startup, you can be sure that the default value is then available to your extended script - especially if people update their system.

## Bootstrap Service: Enforcing the Config

On every start of the RaspiBlitz take the config file and check if the system is running as stated in the config file and when needed make changes to the system. This is done by calling this script on startup with systemd:

`/home/admin/_bootstrap.sh`

So if you change the config by hand or you write a script that changes the config, then simply trigger a restart the RaspiBliz.

Having this script checking the system on every startup, the user can easily update the SD card with a fresh image and the system will automatically establish the old state.

## What to put into the config file and what not

All values users put into setup or setting dialogs and that is not stored on the HDD (for example in the config files of lnd or bitcoin) is a hot cadidate to put into the raspi config file. Some values make sense to get stored as a duplicate (for performance or easy of access) - but dont get to wild.