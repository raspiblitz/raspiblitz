# FAQ - Frequently Asked Questions

## How to update my RaspiBlitz (AFTER version 0.98)?

To prepare the RaspiBlitz update:

- main menu > OFF
- remove power
- remove SD card

Now download the new RaspiBlitz SD card image and write it to your SD card .. yes you simply overwrite the old one, its OK all your personal data is on the HDD (if you havent done any manual changes to the system). See details about latest SD card image here: https://github.com/rootzoll/raspiblitz#scenario-2-start-at-home

If done successful simple put the SD card into the RaspiBlitz and power on again. Then follow the instructions on the display ... and dont worry you dont need to redownload the blockchain again.

## How to update my RaspiBlitz (BEFORE version 0.98)?

Before version 0.98 you need to setup a new RaspiBlitz. So close all channels. Remove all funds from your Raspiblitz (cash-out). Go into terminal and run: `sudo /home/admin/XXleanHDD.sh` and then `sudo shutdown now`. This way you keep your blockchain data on the HDD, but your HDD is cleaned. Now follow again: https://github.com/rootzoll/raspiblitz#scenario-2-start-at-home

## Why do I need to re-burn my SD card for an update (AFTER version 0.98)? 

I know it would be nicer to run just an update script and you are ready to go. But then the scripts would need to be written in a much more complex way to be able to work with any versions of LND and Bitcoind (they are already complex enough with all the edge cases) and testing would become even more time consuming as it is now already. Thats nothing a single developer can deliver. 

For some it might be a pain point to make a update by re-burning a new sd card - especially if you added own scripts or made changes to the system -> but thats by design. Its a way to enforce a "clean state" with every update - the same state that I tested and developed the scripts against. The reason for that pain: I simply cannot write and support scripts that run on every modified system forever - thats simply too much work.

With the SD card update mechanism I reduce complexity, I deliver a "clean state" OS, LND/Bitcoind and the scripts tightly bundled together exactly in the dependency/combination like I tested them and its much easier to reproduce bug reports and give support that way.

Of course people should modify the system, add own scripts, etc ... but if you want also benefit of the updates of the RaspiBlitz you have two ways to do it:

1. Contribute your changes back to the main project as pull requests so that they become part of the next update - the next SD card release.

2. Make your changes so that they survive an SD card update easily -> put all your scripts and extra data onto the HDD AND document for yourself how to activate them again after an update. 

BTW there is a beneficial side effect, when updating with a new SD card: You also get rid of any maleware or system bloat that happend in the past. You start with a fresh system :)

## I have the full blockchain on another computer. How do I copy it to the RaspiBlitz?

Copying a already synced blockchain from another computer (for example your Laptop) can be a quick way to get the RaspiBlitz started. Also that way you synced and verified the blockchain yourself and not trusting the RaspiBlitz FTP/Torrent downloads (dont trust, verify).

One requirement is that the blockchain is from another bitcoin-core client with version greater or equal to 0.17.1 with transaction index switched on (`txindex=1` in the `bitcoin.conf`). 

But we dont copy the data via USB to the device, because the HDD needs to be formatted in EXT4 and that is usually not read/writeable by Windows or Mac computers. So I will explain a way to copy the data thru your local network. This should work from Windows, Mac, Linux and even from another already synced RaspiBlitz.

Both computers (your RaspberryPi and the other computer with the full blockchain on) need to be connected to the same local network. Make sure that bitcoin is stoped on the computer containing the blockchain. If your blockchain source is another RaspiBlitz run on the terminal `sudo systemctl stop bitcoind` and then go to the directory where the blochcian data is with `cd /mnt/hdd/bitcoin` - when copy/transfer is done later reboot a RaspiBlitz source with `sudo shutdown -r now`.

If everything of the above is prepared, start the setup of the new RaspiBlitz with a fresh SD card (like explained in the README) - its OK that there is no blockchain data on your HDD yet - just follow the setup. When you get to the setup-point `Getting the Blockchain` choose the COPY option. Starting from version 1.0 of the RaspiBlitz this will give you further detailed instructions how to transfere the blockchain data onto your RaspiBlitz. In short: On your computer with the blockchain data source you will execute SCP commands, that will copy the data over your Local Network to your RaspiBlitz. 

Once you finished all the transferes the Raspiblitz will make a quick-check on the data - but that will not guarantee that everything in detail was OK with the transfere. Check further FAQ answeres if you get stuck or see a final sync with a value below 90%.

## Why is my "final sync" taking so long?

First of all if you see a final sync over 90% and you can see from time to time small increase - you should be OK ... this can take some looong time to catch up with the network. Only in the case that you activly choose the `SYNC` option in the `Getting the Blockchain` a final sync under 90% is OK. If you did a torrent, a FTP or a copy from another computer and seeing under 90% somthing went wrong and the setup process is ignoring your prepared Blockchain and doing a full sync - which can almost take forever on a raspberryPi.

So if something is wrong (like mentioned above) then try again from the beginning. You need to reset your HDD for a fresh start: SSH in as admin user. Abort the final sync info with CTRL+c to get to the terminal. There run `sudo /home/admin/XXcleanHDD.sh -all` and follow the script to delete all data in HDD. When finsihed power down with `sudo shutdown now`. Then make a fresh SD card from image and this time try another option to get the blockchain. If you run into trouble the second time, please report an issue on GitHub.

## How to backup my Lightning Node?

CAUTION:  Restoring a backup can lead to LOSS OF ALL CHANNEL FUNDS if its not the latest channel state. There is no perfect backup solution for lightning nodes yet - this topic is in development by the community.

But there is one safe way to start: Store your LND wallet seed (list of words you got on wallet creation) in a safe place. Its the key to recover access to your on-chain funds - your coins that are not bound in an active channel.

Recovering the coins that you have in a active channel is a bit more complicated. Because you have to be sure that you really have an up to date backup of your channel state data. The problem is: If you post an old state of your channel this looks to the network like you want to cheat and your channel partner is allowed claim all the funds in the channel.

To really have a good backup to rely on such feature needs to be part of the LND software. Almost every other solution would not be perfect. Thats why RaspiBlitz is not trying to provide a backup feature at the moment.

But you can try to backup at your own risk. All your Lightning Node data is within the `/mnt/hdd/lnd` directory. Just run a backup of that data when the lnd service is stopped.

## How do I change the Name/Alias of my lightning node

Use the "Change Name/Alias of Node" option in main menu. The RaspiBlitz will make a reboot after this.

## What to do when on SSH I see "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!"

This means, that he public ssh key of the RaspiBlitz has changed to the one you logged in the last time under that IP.

Its OK when happening during an update - when you changed the sd card image. If its really happening out of the blue - check your local network setup for a second. Maybe the local IP of your RaspiBlitz changed? Is there a second RaspiBlitz connected? Its a security warning, so at least take some time to check if anything is strange. But also dont get to panic - when its in your local network, normally its some network thing - not an intruder.

To fix this and to be able to login with SSH again, you have to remove the old public key for that IP from your local client computer. Just run the following command (with the replaced IP of your RaspiBlitz): `ssh-keygen -R IP-OF-YOUR-RASPIBLITZ` or remove the line for this IP manually from the known_hosts file (path see in warning message).

After that you should be able to login with SSH again.

## When using Auto-Unlock, which security do I loose?

The idea of the "wallet lock" in general is that your privatekey/seed/wallet is stored in a encrypted way on your HDD. On every you restart you have to input the password once manually (unlock your wallet), so that the LND can again read and write to the encrypted wallet. This gives you security if your RaspiBlitz gets stolen or taken away - it looses power and then your wallet is safe - the attacker cannot access your wallet. 

When you activate the "Auto-Unlock" feature of the RaspiBlitz, the password of the wallet gets stored on the RaspiBlitz. So for an attacker stealing the RaspiBlitz physically its now possible to find the password and unlock the wallet.

## I connected my HDD but it still says 'Connect HDD' on the display?

Your HDD may have no partitions yet. SSH into the RaspiBlitz as admin (see command and password on display) and you should get offert the option to create a partition. If this is not the case:

Check/Exchange the USB cable. Connect the HDD to another computer and check if it shows up at all .. 

OSX: https://www.howtogeek.com/212836/how-to-use-your-macs-disk-utility-to-partition-wipe-repair-restore-and-copy-drives/

Windows:
https://www.lifewire.com/how-to-open-disk-management-2626080

Linux/Ubuntu (desktop):
https://askubuntu.com/questions/86724/how-do-i-open-the-disk-utility-in-unity

Linux/Raspbian (command line):
https://www.addictivetips.com/ubuntu-linux-tips/manually-partition-a-hard-drive-command-line-linux/

## How do I shrink the QR code for connecting my Shango/Zap mobile phone?

Make the fonts smaller until the QR code fits into your (fullscreen) terminal. In OSX use `CMD` + `-` key. In LINUX use `CTRL`+ `-` key. On WINDOWS Putty go into the settings and change the font size: https://globedrill.com/change-font-size-putty