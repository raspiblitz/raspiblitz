# FAQ - Frequently Asked Questions

## Whats new in Version 1.1 of RaspiBlitz?

Version 1.1 packs some first fixes and enhancements to make the RaspiBlitz more stable, protect HDD data better and support you better in case of data corruption of the blockchain data.

- Update: RTL (Ride the Lightning) Web UI version 0.2.15-beta
- Fix: Preventing logs from filling up the sd card 
- Fix: Pairing for latest Zap iOS Mobile Wallet
- Fix: Pairing for latest Shango Mobile Wallet
- Fix: Open LND port check when custom port
- New: Undervoltage Reports on LCD
- New: fsk (file system consistency check) of HDD on every boot
- New: Repair Help Menu in case if blockchain data corruption
- New: /config.scripts/lnd.setport.sh (set custom LND port)
- New: /config.scripts/lnd.rescue.sh (backup/replay LND data)
- New: Bootscreen with logo
- Removed: FTP download option for blockchain

For full details see issue list of [Release 1.1 Milestone](https://github.com/rootzoll/raspiblitz/milestone/3?closed=1).

Instructions on how to update see FAQ info below.

## How to update my RaspiBlitz (AFTER version 0.98)?

For update you dont need to close any channels, remove funding or download the blockchain again.

Here is a YouTube video tutorial on how to update: https://www.youtube.com/watch?v=Xvn0WQfHUdI

Simply [Download the new RaspiBlitz SD card image](https://github.com/rootzoll/raspiblitz#installing-the-software) to your laptop and have an sd card writer ready. Then login into your RaspiBlitz with SSH and:

- main menu > OFF
- remove power
- remove SD card

Write the new image it to your SD card .. yes you simply overwrite the old one, it's OK, all your personal data is on the HDD. If you want to be extra safe you can make a image backup of your old sd card first - but that is optional. If you made manual changes to your RaspiBlitz with scripts on the sd card you might wanna check on this FAQ question first: [Why do I need to re-burn my SD card for an update?](FAQ.md#why-do-i-need-to-re-burn-my-sd-card-for-an-update).

- insert new sd card image
- power on the RaspiBlitz again

You should see that it switched into recover/backup mode. Its now provisioning the fresh OS on the sd card your old settings and data. This process can take some while especially if you had RTL Web UI activated. Follow the instructions on the display ... if it takes longer then an hour .. [get support](https://github.com/rootzoll/raspiblitz#support).

When update/recover process is ready you will see a `FINAL RECOVER LOGIN NEEDED` message on the display. Login per SSH by using the password `raspiblitz` and set your Password A again. It can be the same as the old one, but maybe use the occasion to make password change for security reasons. If you had auto-unlock activated you might also be asked to enter your old Password C again. Then it wil make a final reboot.

After your RaspiBlitz is done with catching up the latest blockchain data you should see your status screen displaying your funds and channels. Your backup is complete.

## Can I downgrade from v1.1 to v1.0?

Yes - it was tested one time and worked. Just follow the normal update mechanism - just use the old v1.0 image or your own backup image of the old sd card.

## Can I still get version 1.0 of RaspiBlitz?

Yes here are the links:

HTTP: http://wiki.fulmo.org/downloads/raspiblitz-v1.0-2019-02-18.img.gz

Torrent: https://github.com/rootzoll/raspiblitz/raw/master/raspiblitz-v1.0-2019-02-18.torrent

SHA-256: 99ca96d214657388305ca117e2343ead45f9d907f185bef36c712a9a3e75568f

Code: https://github.com/rootzoll/raspiblitz/tree/v1.0

## How to update a old RaspiBlitz (BEFORE version 0.98)?

If your old RaspiBlitz if version 0.98 or higher, just follow the update instructions in the README.

If you run a version earlier then 0.98 you basically need to setup a new RaspiBlitz to update - but you can keep the blockchain data on the HDD, so you dont need have that long waiting time again:

1. Close all open lightning channels you have (`lncli closeallchannels --force`) or use the menu option 'CLOSE ALL' if available. Wait until all closing transactions are done.

2. Move all on-chain funds to a wallet outside raspiblitz (`lncli --conf_target 3 sendcoins [ADDRESS]`) or use the menu option 'CHASH OUT' if available

3. Prepare the HDD for the new setup by running the script `/home/admin/XXcleanHDD.sh` (Blockchain will stay on HDD)

4. then shutdown RaspiBlitz (`sudo shutdown now`), flash SD card with new image, redo a fresh setup of RaspiBlitz, move your funds back in, Re-Open your channels

## Why do I need to re-burn my SD card for an update?

I know it would be nicer to run just an update script and you are ready to go. But then the scripts would need to be written in a much more complex way to be able to work with any versions of LND and Bitcoind (they are already complex enough with all the edge cases) and testing would become even more time consuming than it is now already. That's nothing a single developer can deliver.

For some, it might be a pain point to make an update by re-burning a new sd card - especially if you added your own scripts or made changes to the system - but thats by design. It's a way to enforce a "clean state" with every update - the same state that I tested and developed the scripts with. The reason for that pain: I simply cannot write and support scripts that run on every modified system forever - that's simply too much work.

With the SD card update mechanism I reduce complexity, I deliver a "clean state" OS, LND/Bitcoind and the scripts tightly bundled together exactly in the dependency/combination like I tested them and its much easier to reproduce bug reports and give support that way.

Of course, people should modify the system, add own scripts, etc ... but if you want to also have the benefit of the updates of the RaspiBlitz, you have two ways to do it:

1. Contribute your changes back to the main project as pull requests so that they become part of the next update - the next SD card release.

2. Make your changes so that they survive an SD card update easily - put all your scripts and extra data onto the HDD AND document for yourself how to activate them again after an update .. maybe even write a small shell script (stored on your HDD) that installes & configs all your additional packages, software and scripts.

*BTW there is a beneficial side effect when updating with a new SD card: You also get rid of any malware or system bloat that happened in the past. You start with a fresh system :)*

## How can I avoid using a prepared blockchain and validate myself?

The torrent download use a prepared blockchain to kick start the RaspiBlitz. If you want to selft validate you could do this on another more powerful computer and then transfere your own validated blockchain over to the RaspiBlitz. Check the options `Copying from another Computer` & `Cloning from a 2nd HDD` described in the [README](README.md) for more details.

## I have the full blockchain on another computer. How do I copy it to the RaspiBlitz?

Copying a already synced blockchain from another computer (for example your Laptop) can be a quick way to get the RaspiBlitz started or replacing a corrupted blockchain with a fresh one. Also that way you synced and verified the blockchain yourself and not trusting the RaspiBlitz Torrent downloads (dont trust, verify).

One requirement is that the blockchain is from another bitcoin-core client with version greater or equal to 0.17.1 with transaction index switched on (`txindex=1` in the `bitcoin.conf`).

But we dont copy the data via USB to the device, because the HDD needs to be formatted in EXT4 and that is usually not read/writeable by Windows or Mac computers. So I will explain a way to copy the data through your local network. This should work from Windows, Mac, Linux and even from another already synced RaspiBlitz.

Both computers (your RaspberryPi and the other computer with the full blockchain on) need to be connected to the same local network. Make sure that bitcoin is stoped on the computer containing the blockchain. If your blockchain source is another RaspiBlitz run on the terminal `sudo systemctl stop bitcoind` and then go to the directory where the blockchain data is with `cd /mnt/hdd/bitcoin` - when copy/transfer is done later reboot a RaspiBlitz source with `sudo shutdown -r now`.

If everything of the above is prepared, start the setup of the new RaspiBlitz with a fresh SD card (like explained in the README) - its OK that there is no blockchain data on your HDD yet - just follow the setup. When you get to the setup-point `Getting the Blockchain` choose the COPY option. Starting from version 1.0 of the RaspiBlitz this will give you further detailed instructions how to transfer the blockchain data onto your RaspiBlitz. In short: On your computer with the blockchain data source you will execute SCP commands, that will copy the data over your Local Network to your RaspiBlitz.

Once you finished all the transferes the Raspiblitz will make a quick-check on the data - but that will not guarantee that everything in detail was OK with the transfer. Check further FAQ answeres if you get stuck or see a final sync with a value below 90%.

**If you want to replace a corrupted blockchain this way:**  *Go to terminal - maybe with CTRL+c. Then call `/home/admin/50copyHDD.sh` use the displayed SCP commands to copy over the fresh blockchain. Press ENTER when all is copied, so that the script can quick check the data. Then make a reboot `sudo shutdown -r now`*

## How do I clone the Blockchain from a 2nd HDD?

During setup, when you start with an empty HDD you need to get a copy of the blockchain. One option available is to connect a 2nd HDD to the RaspiBlitz that contains already the blockchain data and start to copy/clone.

If you choose this option, the console requests you to connect the second HDD and will autmatically detect it:

![SSH6b](pictures/ssh6b-copy.png)

You can simply use the HDD of another RaspiBlitz or you prepare a HDD yourself by:

* format second HDD with exFAT (availbale on Windows and Mac)
* copy an indexed Blockchain into the root folder "bitcoin"
* when your HDD is ready the content of your folder bitcoin should look like this:

```
/bitcoin/blocks
/bitcoin/chainstate
/bitcoin/indexes
```

optional you can add also the testnet data:

```
/bitcoin/testnet3/blocks
/bitcoin/testnet3/chainstate
/bitcoin/testnet3/indexes
```

To connect the 2nd HDD to the RaspiBlitz, the use of a Y cable to provide extra power is recommended (see optional shopping list). Because the RaspiBlitz cannot run 2 HDDs without extra power. For extra power you can use a battery pack (like in picture below) or choose a external HDD with its own power supply.

![ExtraPower](pictures/extrapower.png)

## How do I generate a Debug Report?

If your RaspiBlitz is not working right and you like to get help from the community, its good to provide more debug information, so other can better diagnose your problem - please follow the following steps to generate a debug report:

- ssh into your raspiblitz as admin user with your password A
- If you see the menu - use CTRL+C to get to the terminal
- To generate debug report run: `./XXdebugLogs.sh`
- Then copy all output beginning with `*** RASPIBLITZ LOGS ***` and share this

*PLEASE NOTICE: Its possible that this logs can contain private information (like IPs, node IDs, ...) - just share publicly what you feel OK with.*

## Why is my "final sync" taking so long?

First of all if you see a final sync over 90% and you can see from time to time small increase - you should be OK ... this can take some looong time to catch up with the network. Only in the case that you activly choose the `SYNC` option in the `Getting the Blockchain` a final sync under 90% is OK. If you did a torrent or a copy from another computer and seeing under 90% somthing went wrong and the setup process is ignoring your prepared Blockchain and doing a full sync - which can almost take forever on a raspberryPi.

So if something is wrong (like mentioned above) then try again from the beginning. You need to reset your HDD for a fresh start: SSH in as admin user. Abort the final sync info with CTRL+c to get to the terminal. There run `sudo /home/admin/XXcleanHDD.sh -all` and follow the script to delete all data in HDD. When finsihed power down with `sudo shutdown now`. Then make a fresh SD card from image and this time try another option to get the blockchain. If you run into trouble the second time, please report an issue on GitHub.

## How to backup my Lightning Node?

CAUTION: Restoring a backup can lead to LOSS OF ALL CHANNEL FUNDS if it's not the latest channel state. There is no perfect backup solution for lightning nodes yet - this topic is in development by the community.

But there is one safe way to start: Store your LND wallet seed (list of words you got on wallet creation) in a safe place. Its the key to recover access to your on-chain funds - your coins that are not bound in an active channel.

Recovering the coins that you have in an active channel is a bit more complicated. Because you have to be sure that you really have an up to date backup of your channel state data. The problem is: If you post an old state of your channel, to the network this looks like an atempt to cheat, and your channel partner is allowed claim all the funds in the channel.

To really have a reliable backup, such feature needs to be part of the LND software. Almost every other solution would not be perfect. Thats why RaspiBlitz is not trying to provide a backup feature at the moment. But if you feel experimental and you look for a continues backup you may want to check out the following script to integrate into your RaspiBlitz: https://github.com/vindard/lnd-backup/blob/master/do-lndbackup.sh

How to backup LND data in a rescue situation see next question "How can I recover my coins from a failing RaspiBlitz?".

## How can I recover my coins from a failing RaspiBlitz?

On a RaspiBlitz you have coins in your on-chain wallet (bitcoin wallet) and also coins in lightning channels. First we will try to recover all of them and even trying to keep your channels open with "Recover LND data". This that is not possible you can fall back to the second option "Recover from Wallet Seed".

### 1) Recover LND data

To recover all your LND data you must still be able to SSH into the RaspiBlitz (minimum v1.1) and the HDD should be still useable/reachable (mounted) - even it shows some errors. If this is not possible anymore you should skip to the second option "Recover from Wallet Seed".

If you still can SSH in and HDD is readable, we can try to rescue/export your LND data (funds and channels) from a RaspiBlitz to then be able to restore it back to a fresh one. For this you can use the following procedure ...

To rescue/export your Lightning data from a RaspiBlitz:

* SSH into your RaspiBlitz and EXIT to terminal from the menu.
* then run: `/home/admin/config.scripts/lnd.rescue.sh backup`
* follow the instructions of the script.

This will create a lnd-rescue file (ends on gz.tar) that contains all the data from the LND. The script offers you a command to transfere the lnd-rescue file to your laptop. If transfere was successfull. You can now setup a fresh RaspiBlitz. Do all the setup until you have a clean new Lightning node running - just without any funding or channels.

Then to restore your old LND data and to recover your funds and channels:

* SSH into your new RaspiBlitz and EXIT to terminal from the menu.
* then run: `/home/admin/config.scripts/lnd.rescue.sh restore`
* follow the instructions of the script.

This script will offer you a way to transfere the lnd-rescue file from your laptop to the new RaspiBlitz and will restore the old data. LND gets then restarted for you and after some time it should show you the status screen again with your old funds and channels.

**Be aware that if backup is some hours old, channels could have been closed by the other party and it may take some time until you see funds back on-chain. If backup is somewhat older then 1 day also the channel counter parties may have used your offline time to cheat you with an old state. And if your backup was not the latest state it could also been happening that you are posting an old channel state (seen as cheating) and funds of that channel get lost as punishment. So again .. this backup method can be risky, use with caution. But its recommended to try in recover and rescue situations - its not for regular backups.**

### 2) Recover from Wallet Seed

Remember those 24 words you were writing down during the setup? Thats your "cipher seed" - now this words are important to recover your wallet. If you dont have them anymore: skip this chapter and read option 2. If you still have the cypher seed: good, but read the following carefully:

With the cypher seed you can recover the bitcoin wallet that LND was managing for you - but it does not contain all the details about the channels you have open - its just the key to your funding wallet. If you were able to close all channels or never opened any channels, then everything is OK and you can go on. If you had open channels with funds in there, the following is to consider:

* You now rely on your channel counter parts to force close the channel at one point. If they do, the coins will be available to use in your funding wallet again at one point in the future - after force close delay (but see also [#278](https://github.com/rootzoll/raspiblitz/issues/278) ).
* If your channel counter parts never force close the channel (because they are offline too) your channel funds can be frozen forever.

So going this way there is a small risk, that you will not recover your funds. But normally if your channel counter parts are still online, see that you will not come back online and they have themselves some funds on their channel side with you: They have an incentive to force close the channel to make use of their funds again.

So here is what todo if you want to "Recover from Wallet Seed" with RaspiBlitz:

- SetUp a fresh RaspiBlitz (fresh SD-Card image and clean HDD).
- During the new SetUp you get to the point of creating the LND wallet (see image below).

![SSH8](pictures/wallet-recover.png)

- When you get asked "do you have an existing cypher wallet" answere `y` this time.
- Enter the cypher seed - all words in one line seperated by spaces
- If you get asked at the end for the password D to encrypt your cypher seed, use the same as the last time. If you havent entered one last time, just press Enter again.
- When asked about the "address look-ahead" number - use `250000` instead of the default!

Then give LND some time to rescan the blockchain. In the end you will have restored your funding wallet. You maybe need to wait for your old channel counter parts to force close the old channels until you see the coins back displayed.

*Important: If you see a zero balance for on-chain funds after restoring from seed ... see details discussed [here](https://github.com/rootzoll/raspiblitz/issues/278) - you might try setup fresh this time with bigger look-ahead number.*

## What is this mnemonic seed word list?

With the 24 word list given you by LND on wallet creation you can recover your private key (BIP 39). You should write it down and store it at a save place. 

For more background on mnemonic seeds see this video: https://www.youtube.com/watch?v=wWCIQFNf_8g

## How does PASSWORD D effects the word seed?

On wallet creation you get asked if you want to protect your word seed list with an additional password. If you choose so, RaspiBlitz recommends you to use your PASSWORD D at this point.

To use a an additional password for your seed words is optional. If you choose so, you will need the password to recover your private key from your your seed words later on. Without this password your private key cannot be recovered from your seed words. So the password adds an additional layer of security, if someone finds your written down word list.

## How do I change the Name/Alias of my lightning node

Use the "Change Name/Alias of Node" option in the main menu. The RaspiBlitz will make a reboot after this.

## What to do when on SSH I see "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!"

This means, that he public ssh key of the RaspiBlitz has changed to the one you logged in the last time under that IP.

It's OK when happening during an update - when you changed the sd card image. If it's really happening out of the blue - check your local network setup for a second. Maybe the local IP of your RaspiBlitz changed? Is there a second RaspiBlitz connected? It's a security warning, so at least take some time to check if anything is strange. But also don't get to panic - when it's in your local network, normally it's some network thing - not an intruder.

To fix this and to be able to login with SSH again, you have to remove the old public key for that IP from your local client computer. Just run the following command (with the replaced IP of your RaspiBlitz): `ssh-keygen -R IP-OF-YOUR-RASPIBLITZ` or remove the line for this IP manually from the known_hosts file (see the path to the file in the warning message).

After that, you should be able to login with SSH again.

## When using Auto-Unlock, how much security do I lose?

The idea of the "wallet lock" in general, is that your private key / seed / wallet is stored in a encrypted way on your HDD. On every restart, you have to input the password once manually (unlock your wallet), so that the LND can read and write to the encrypted wallet again. This improves your security if your RaspiBlitz gets stolen or taken away - it loses power and then your wallet is safe - the attacker cannot access your wallet.

When you activate the "Auto-Unlock" feature of the RaspiBlitz, the password of the wallet gets stored on the RaspiBlitz. So if an attacker steals the RaspiBlitz physically, it's now possible for them to find the password and unlock the wallet.

## I connected my HDD but it still says 'Connect HDD' on the display?

Your HDD may have no partitions yet. SSH into the RaspiBlitz as admin (see command and password on display) and you should be offered the option to create a partition. If this is not the case:

Check/Exchange the USB cable. Connect the HDD to another computer and check if it shows up at all.

OSX: https://www.howtogeek.com/212836/how-to-use-your-macs-disk-utility-to-partition-wipe-repair-restore-and-copy-drives/

Windows: https://www.lifewire.com/how-to-open-disk-management-2626080

Linux/Ubuntu (desktop): https://askubuntu.com/questions/86724/how-do-i-open-the-disk-utility-in-unity

Linux/Raspbian (command line): https://www.addictivetips.com/ubuntu-linux-tips/manually-partition-a-hard-drive-command-line-linux/

## How do I shrink the QR code for connecting my Shango/Zap/Zeus mobile phone?

Make the fonts smaller until the QR code fits into your (fullscreen) terminal. In OSX use `CMD` + `-` key. In LINUX use `CTRL`+ `-` key. On WINDOWS Putty go into the settings and change the font size: https://globedrill.com/change-font-size-putty

## Why is my bitcoin IP on the display red?

The bitcoin IP is red, when the RaspiBlitz detects that it cannot reach the port of bitcoin node from the outside. This means the bitcoin node can peer with other bitcoin nodes, but other bitcoin nodes cannot initiate a peering with you. Dont worry, you dont need a publicly reachable bitcoin node to run a (public) lightning node. If you want to change this however, you need to forward port 8333 on your router to the the RaspiBlitz. How to do this is different on every router.

## Why is my node address on the display red?

The node address is red, when the RaspiBlitz detects that it cannot reach the port of the LND node from the outside - when the device is behind a NAT or firewall of the the router. Your node is not publicly reachable. This means you can peer+openChannel with other public nodes, but other nodes cannot peer+openChannel with you. To change this you need to forward port 9735 on your router to the the RaspiBlitz. How to do this is different on every router.

## Why is my node address on the display yellow (not green)?

Yellow is OK. The RaspiBlitz can detect, that it can reach a service on the port 9735 of your public IP - this is in most cases the LND of your RaspiBlitz. But the RaspiBlitz cannot 100% for sure detect that this is its own LND service on that port - thats why its just yellow, not green.

## Can I run the RaspiBlitz as Backend for BTCPayServer?

BTCPay Server is a solution to be your own payment processor to accept Lightning Payments for your online store: https://github.com/btcpayserver/btcpayserver

You can find setup instructions for a experimental setup here: https://goo.gl/KnTzLu

Thanks to @RobEdb (ask on twitter for more details) running his demo store with RaspiBlitz: https://store.edberg.eu - buy a picture of [him and Andreas](https://store.edberg.eu/produkt/jag-andreas/) :)

## I dont have a LAN port on my Laptop - how to connect to my RaspiBlitz?

You dont need a LAN port on your laptop as long as you can connect over WLAN to the same LAN router/switch the RaspiBlitz is connected to .. and you are on the same local network.

## Is it possible to connect the Blitz over Wifi instead of using a LAN cable?

A LAN cable is recommended because it reduces a possible source of error on the network connection side. But how to setup WLAN when you dont have a LAN-Router/Switch available see here:
https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#prepare-wifi

## Can I directly connect the RaspiBlitz with my laptop?

If you have a LAN port on your laptop - or you have a USB-LAN adapter, you can connect the RaspiBlitz directly (without a router/switch) to your laptop and share the WIFI internet connection. You can follow this [guide for OSX](https://medium.com/@tzhenghao/how-to-ssh-into-your-raspberry-pi-with-a-mac-and-ethernet-cable-636a197d055).

In short for OSX:

* make sure all VPN are off (can interfere with local LAN)
* connect with LAN directly
* Settings > Sharing/Freigaben > activate "internet sharing" from WLAN to Ethernet
* Settings > Network > Ethernet-Adapter > set to DHCP
* in terminal > `ifconfig` there you should the the IP of the bridge100
* in terminal > `arp -a` and check for an IP of a client to the bridge
* in terminal > ssh admin@[clientIP]

If anyone has expirence on doing this in Linux/Win, please share.

## How do I unplug/shutdown safely without SSH

Just removing power from the RaspiBlitz can lead to data corruption if the HDD is right in the middle of a writing process. The safest way is always to SSH into the RaspiBlitz and use the "POWER OFF" option in the main menu.

But if cannot login with SSH and you need to power off at least remove the LAN cable (network connection)first for sometime (around 10-30 secs - until you can see no more blinking lights on the HDD) and then remove the power cable. This should minimize the risk if data corruption in this situations.

## How can I build an SD card other then the master branch?

There might be a new not released features in development that are not yet in the master branch - but you want to try them out.

To build a sd card image from another branch than master you follow the [Build the SD Card Image](README.md#build-the-sd-card-image) from the README, but execute the build script from the other branch and add the name of that branch as a parameter to the build script.

For example if you want to  make a build from the 'dev' branch you execute the following command:

`wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build_sdcard.sh && sudo bash build_sdcard.sh 'dev'`

## How can I build an SD card from my forked GitHub Repo?

If you fork the RaspiBlitz repo (much welcome) and you want to run that code on your RaspiBlitz, there are two ways to do that:

* The quick way: For small changes in scripts, go to `/home/admin` on your running RaspiBlitz, delete the old git with `sudo rm -r raspiblitz` then replace it with your code `git clone [YOURREPO]` and `/home/admin/XXsyncScripts.sh`

* The long way: If you like to install/remove/change services and system configurations you need to build a SD card from your own code. Prepare like in [Build the SD Card Image](README.md#build-the-sd-card-image) from the README but in the end run the command:

`wget https://raw.githubusercontent.com/[GITHUB-USERNAME]/raspiblitz/[BRANCH]/build_sdcard.sh && sudo bash build_sdcard.sh [BRANCH] [GITHUB-USERNAME]

If you are then working in your forked repo and want to update the scripts on your RaspiBlitz with your latest repo changes, run `/home/admin/XXsyncScripts.sh` - thats OK as long as you dont make changes to the sd card build script - then you would need to build a fresh sd card again from your repo.

## How to attach the RaspberryPi to the HDD?

There are multiple ways to do it - just remember it should be easy to get to the SD card slot to remove and replace the card.

Here is an example to use [Hook-and-loop fastener](https://en.wikipedia.org/wiki/Hook-and-loop_fastener) tape:

![ExtraPower](pictures/befestigung.jpg)

## What other case options do I have?

You can replace the generic case in the shopping lists with a customized 3D printed for the RaspiBlitz called "Lightning Shell" - great work by @CryptoCloaks

https://thecryptocloak.com/product/lightningshell/

![LightningShell](pictures/lightningshell.png)

Also there are first free 3D open source files in this repo in the directory `case.3dprint` that you can selfprint. Those are much simpler then the 'Lightning Shell' and are not finished yet. But feel free to try out and improve - PullRequests welcome.

## Are those "Under-Voltage detected" warnings a problem?

When your USB power adapter for the RaspiBlitz delivers too low power those messages with "Under-Voltage detected" (undervoltage) are shortly seen on the display. This can lead to data loss/corruption on the HDD. If you see those just one or two times that's not OK, but can be in a tolerant window. Nevertheless it make sure your USB power adapter can deliver at least 3A (big and stable is good). If you still see those warnings maybe get a second USB Power adapter just for the HDD and power the HDD through a Y-Cable - see https://en.wikipedia.org/wiki/Y-cable#USB or put a USB Hub with extra power between the raspberry and the HDD.

## Why do we need to download the blockchain and not syncing it?

The RaspiBlitz is powered by the RaspberryPi. The processing power of this SingleBoardComputer is too low to make a fast sync of the blockchain from the bitcoin peer to peer network during setup process (validation). To sync and index the complete blockchain could take weeks or even longer. Thats why the RaspiBlitz needs to download a prepared blockchain from another source.

## Is using the perpared SD card image secure?

Using pre-built software almost always shifts trust to the one who made the binary. But at least you can check with the SHA checksum after download if the image downloaded is really the one offered by the GitHub Repo. To do so make a quick check if your browser is really in the correct GiutHub page and that your HTTPS of the GitHub page is signed by 'DigiCert'. Then compare the SHA-256 string (always next to the download link of the image on the README) with the result of the command `shasum -a 256 [DOWNLOADED-FILE-TO-CHECK]` (Mac/Linux). Still this is not optimal and if at least some people from the community request it, I will consider signing the download as an author for the future.

The best way would be to build the sd card yourself. You use the script `build_sdcard.sh` for it. Take some minutes to check if you see anything suspicious in that build script and then follow the [README](README.md#build-the-sd-card-image) on this.

## Is downloading the blockchain from a third party secure?

To download a blockchain from a third party (torrent/ftp) is not optimal and for the future with more cheap & powerfull SingleBoardComputers we could get rid of this 'patch'.

The downloaded blockchain is pre-indexed and pre-validated. That should be practically secure enough, because if the user gets a "manipulated" blockchain it would not work after setup. The beginning of the downloaded blockchain needs to fit the genesis block (in bitcoind software) and the end of the downloaded blockchain needs not match with the rest of the bitcoin network state - hashes of new block distrubuted within the peer-2-peer network need to match the downloaded blockchain head. So if you downloaded a manipulated blockchain it simply wouldn't work in practice. As long as you are not in a totally hostile environment where someone would be able to fake a whole network of peers and miners around you - this is secure enough for running a small funded full node to try out the lightning network.

If you dont trust the download or you want to run the RaspiBlitz in a more production like setup (on your own risk) then don't use the torrent/ftp download and choose the option to COPY the blockchain data from a more powerful computer (laptop or desktop) where you synced, verified and indexed the blockchain all by your yourself - see [README](README.md#4-copying-from-another-computer) for more details.

## Why is taking my torrent download of the blockchain so long?

Other users reported that opening up and forwarding the following port from their router to the RaspiBlitz helped speed up and getting started the torrent download: 6881-6889, 6969, 1337

## What is the "Base Torrent File"?

Inspired by the website getbitcoinblockchain.com we use one of their base torrent files to have a basic set of blocks - that will not change for the future. This torrent contains most of the data (the big file) and we dont need to change the torrent for a long time. This way the torrent can get establish a wide spread seeding and the torrent network can take the heavy load.

At the moment (Baseiteration=1) this is just the bitcoin blk and rev files up to the number:
- /blocks : 01390
- /testnet3/blocks: 00152

For litecoin (Baseiteration=1) its blk and rev files up to the number:
- /blocks : 00124

The base torrent file should always have the following naming scheme:

`raspiblitz-[CHAINNETWORK][BASEITERATIONNUMBER]-[YEAR]-[MONTH]-[DAY]-base.torrent`

So for example the second version of the base torrent for litecoin created on 2018-10-31 would have this name: raspiblitz-litecoin2-2018-10-31-base.torrent

## What is the "Update Torrent File" and how to create it?

All the rest of the files get packaged into a second torrent file. This file will be updated much more often. The seeding is expected to be not that good and download may be slower, but that's OK because it's a much smaller file.

This way a good balance between good seeding and up-to-date blockchain can be reached.

To create the Update Torrent file, follow the following step ...

Have a almost 100% synced bitcoind MAINNET with txindex=1 on a RaspiBlitz
(remove all funds from this node - because blockchain get messed with)

Stop bitcoind with:
```
sudo systemctl stop bitcoind
```

Delete base torrent blk-files with:
```
sudo rm /mnt/hdd/bitcoin/blocks/blk00*.dat
sudo rm /mnt/hdd/bitcoin/blocks/blk0{1000..1390}.dat
```

Delete base torrent rev-files with:
```
sudo rm /mnt/hdd/bitcoin/blocks/rev00*.dat
sudo rm /mnt/hdd/bitcoin/blocks/rev0{1000..1390}.dat
```

Now change to your computer where you package the torrent files and transfere the three directories into your torrent base directory (should be your current working directory):
```
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/blocks ./blocks
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/chainstate ./chainstate
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/indexes ./indexes
```

Also have an almost 100% synced bitcoind TESTNET with txindex=1 on a RaspiBlitz

Stop bitcoind with:
```
sudo systemctl stop bitcoind
```

Delete base torrent blk-files with:
```
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/blk000*.dat
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/blk00{100..152}.dat
```

Delete base torrent rev-files with:
```
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/rev000*.dat
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/rev00{100..152}.dat
```

Now change again to your computer where you package the torrent files and transfer the three directories into your torrent base directory (should be your current working directory):
```
mkdir testnet3
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/testnet3/blocks ./testnet3/blocks
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/testnet3/chainstate ./testnet3/chainstate
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/testnet3/indexes ./testnet3/indexes
```

(Re-)name the "torrent base directory" to the same name as the torrent UPDATE file itself later (without the .torrent ending). The update torrentfile should always have the following naming schema:

`raspiblitz-[CHAINNETWORK][BASEITERATIONNUMBER]-[YEAR]-[MONTH]-[DAY]-update.torrent`

*So for example an update torrent created on 2018-12-24 for litecoin that is an update to the second base torrent version would have this name: raspiblitz-litecoin2-2018-12-24-update.torrent*

Now open your torrent client (e.g. qTorrent for OSX) and create a new torrent-file with the freshly renamed "torrent base directory" as source directory.

Add this list of trackers to your torrent and start seeding (keep a free/empty line between the three single trackers):
```
udp://tracker.justseed.it:1337

udp://tracker.coppersurfer.tk:6969/announce

udp://open.demonii.si:1337/announce

udp://denis.stalker.upeer.me:6969/announce
```

After successful creation of the torrent file:
* copy to `/home.admin/assets`
* push to master
* change in `50torrentHDD.sh script`
* add to Torrent-[RSS](https://github.com/rootzoll/raspiblitz/issues/285#issuecomment-457796120)
* seed at home and at services like justseed.it
* update [issue](https://github.com/rootzoll/raspiblitz/issues/285#issuecomment-457796120) and ask on twitter for help on seeding

## What is the process of creating a new sd card image release?

Work Nodes for the process of producing a new sd card image release:

* Start `Ubuntu LIVE` from USB stick on Build Computer (press F12 on startup)
* Connect secure WIFI (hardware switch on)
* Download latest Raspbian Desktop (without recommended software) from [raspberrypi.org](https://www.raspberrypi.org/downloads/raspbian/) to the NTFS formatted data USB stick
* Open terminal and compare checksum `shasum -a 256 /media/ubuntu/...[DOWNLOADED-RASPBIAN]`
* Use in file manager context on NTFS USB stick `extract here` to unzip
* Connect sd card reader with 8GB sd card
* Use in file manager context on img-file `write image` write to sd card
* Use in file manager context on `boot` drive free space `open in terminal`
* Run command `touch ssh`
* Close terminal and eject `boot`
* Connect a RaspiBlitz (without HDD) to network, insert sd card and power up
* Find IP if RaspiBlitz (arp -a or check router)
* In terminal `ssh pi@[IP-OF-RASPIBLITZ]`
* Password is `raspberry`
* `wget https://raw.githubusercontent.com/rootzoll/raspiblitz/master/build_sdcard.sh && sudo bash build_sdcard.sh`
* Check output for warnings/errors - install LCD
* Login new with `ssh admin@[IP-OF-RASPIBLITZ]` (pw:raspiblitz) and run `./XXprepareRelease.sh`
* Deconnect Wifi on build laptop (hardware switch off) and shutdown
* Remove `Ubuntu LIVE` USB stick and replace with `Ubuntu AIRGAP`
* PowerOn Build Laptop (press F12 for boot menu)
* Cut Power of RaspiBlitz, remove sd card and connect with sd card reader to build laptop
* Connect and open in Filemenager NTFS - context on white scace -> open terminal
* run `df`to check on sd card reader device name
* `sudo dd if=/dev/[sdcarddevice] | gzip > ./raspiblitz-vX.X-YEAR-MONTH-DAY.img.gz`
* Delete all IMG files from NTFS (just keep zips/gzs)
* Context on white space, `Open in Terminal`, run `shasum -a 256 [NEW-ZIP] > sha256.txt`
* [Do future author signing here with tools from airgap build machine]
* Shutdown build computer
* Connect NTFS USB stick to MacOS (its just readonly)
* Check if file can be unzipped on OSX
* Run tests with new image
* Upload new image to Download Server
* Copy SHA256-String into GutHub README and update downloadlink

## Can I run RaspiBlitz on other computers than RaspberryPi?

There is an experimental section in this GitHub that tries to build for other SingleBoardComputers. Feel free to try it out and share your experience: [dietpi/README.md](dietpi/README.md)

## Can I flip the screen?

For the default 3.5" LCD you need to edit the /boot/config.txt. Run `sudo nano /boot/config.txt`
look for the line `dtoverlay=tft35a:rotate=270` towards the end. To flip the screen with 180 degrees change the line to `dtoverlay=tft35a:rotate=90` and reboot with `sudo reboot`. Reference: https://github.com/goodtft/LCD-show/issues/34

## How to setup fresh/clean/reset and not getting into recovery mode?

When you put in a sd card with a new/clean RaspiBlitz image the RaspiBlitz will get into recovery mode because it detects the old data on your HDD and assumes you just want to continue to work with this data.

But there might be cases where you want to start a totally fresh/clean RaspiBlitz from the beginning. To do so you need to delete the old data from the HDD. You can do so by formating it on another computer (for example with FAT and name it "NEW"). Or when you can run the script "/home/admin/XXcleanHD.sh -all" on the terminal.

When the HDD is clean, then flash a new RaspiBlitz sd card and your setup should start fresh.

## My blockchain data is corrupted - what can I do?

You could try to re-index, but that can take some very long time - multiple days or even weeks. But there are other options:

1. Copy Blockchain from another Computer

You can delete the old blockchain and get a new one. See for details the FAQ question: [I have the full blockchain on another computer. How do I copy it to the RaspiBlitz?](FAQ.md#i-have-the-full-blockchain-on-another-computer-how-do-i-copy-it-to-the-raspiblitz). And even if you are not able to delete the data, first rename the undeletable folders and then follow the instructions.

2. Re-Torrent download prepared Blockchain

You can also start a new Torrent-Download and replace the old blockchain with a new download once its finished. Go to terminal and run script `/mnt/hdd/50torrentHDD.sh`

3. Backup LND Data, make fresh Blitz, Replay LND Data

You can backup your channel and wallet data, make a complete fresh RaspiBlitz and after that one is setup you replace the LND data with your old one. Also make sure to check again on your power supply - it needs to deliver equal or more then 3A and should deliver a stable current. If you think your HDD or SD card is degrading - maybe this is a good time to replace. See for details the FAQ question: [How can I recover my coins from a failing RaspiBlitz?](FAQ.md#how-can-i-recover-my-coins-from-a-failing-raspiblitz)*

## Can I run the RaspiBlitz without a display/LCD?

The display is one of the nice features of the RaspiBlitz but the raspberry can un without it. Maybe not all add-on feature could be used to the full extend, but you can get started without the LCD and even plug it on later.

Normally with the LCD its easy to see your local IP changes and you can get started quickly. Without it needs a bit more digging thru your network - you can find a good tutorial on that on the RaspiBolt tutorial (origin of RaspiBlitz):

https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#connecting-to-the-network

*Please Note: Without a LCD-Hat you cannot simply use the HDMI as alternative, because screen signal is routed to the GPIO pins. On how to switch that back manually - see [waveshare documentation](https://www.waveshare.com/wiki/3.5inch_RPi_LCD_(A)).*

## I have two RaspiBlitz in my network - can they both be public?

Yes but you need to change at least on one RaspiBlitz the port number (for example to 9736) on one of your RaspiBlitzes - see how to change a port below. Then you can forward both ports from your home internet router to the matching RaspiBlitzes.

## How to change the public port LND/Lightning node is running on?

There is a experimental script you can call from the terminal that will make all changes for you ... see details here: https://github.com/rootzoll/raspiblitz/issues/100#issuecomment-466722712

## How to solve a "signature mismatch after caveat verification" error?

If you get this error by LND that means that something is wrong with the macaroons being used to communicate with LND .. see: https://github.com/lightningnetwork/lnd/blob/master/docs/macaroons.md

To fix this depends on where you get this error:

* If you get it in a mobile wallet, then redo the connection with the RaspiBlitz to get fresh macaroons.
* If you get this from RTL or from the scripts of the SSH menus of the RaspiBlitz, then go to "EXPORT Macacroons and TLS.cert" in SSH main menu and choose the the "RESET Macaroons & TLS" option.

Also make sure to check again on your power supply - it needs to deliver equal or more then 3A and should deliver a stable current. If you think your HDD is degrading - maybe this is a good time to replace it. See for details the FAQ question: [How can I recover my coins from a failing RaspiBlitz?](FAQ.md#how-can-i-recover-my-coins-from-a-failing-raspiblitz)

## Why is my node not routing? 

1. You don't have inbound liquidity 
2. Low uptime
3. Capital is committed to competitive destinations 
4. Capital committed to destinations no one wants to send to 
5. Fees are too high
6. Your inbound liquidity doesn't have good inbound liquidity itself

## How can I change the boot screen logo? 

Just replace the file `/home/admin/raspiblitz/pictures/logoraspiblitz.png` with a PNG of the same dimensions.

NOTE: On updates this change will get lost and you might need to redo it.

## How can I update LND or bitcoind even before the next RaspiBlitz update?

Try updating before a official RaspiBlitz on your very own risk - you can find some info about that here:
https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_faq.md#how-to-upgrade-bitcoin-core

## I cannot connect per SSH to my RaspiBlitz. What to do?

- Check the command again with how its on the display  - do you have it typed in correctly?
- Replace `ssh` with `sudo ssh` and try it (laptop admin password might be required).

If that not works ry to ping the IP of the RaspiBlitz with `ping [IP-of-RaspiBlitz]`. If you get no response on the ping requests the device is not reachable try this check list:

- Make sure that your RaspiBlitz and your laptop are really on the same local network
- Check if you have a VPN running on your laptop - some VPNs block local network
- Some Routers have `IP Isolation` switched on - not allowing to devices to connect

If that all is not working: Join the conversation on [GitHub Issue #420](https://github.com/rootzoll/raspiblitz/issues/420).

## How to setup port-forwarding with a SSH tunnel?

To use a public server for port-forwarding thru a SSH tunnel you can use the following experimental script on the RaspiBlitz (since v1.2):

`/home/admin/config.scripts/internet.sshtunnel.py`

But first you need to make sure that the public server you are using is supporting SSH reverse tunneling and authentification by public authorized key. Check the `/etc/ssh/sshd_config` on the public server to contain the following settings:

```
RSAAuthentication yes
PubkeyAuthentication yes
GatewayPorts yes
AllowTcpForwarding yes
```

You can add those at the end of the file, save and reboot.

On the RaspiBlitz you can then setup for example to forward the gRPC port 10009 (internal port) to the port 20009 on the public server (external port) with the user = `test` and server address = `raspiblitz.com` with the following command:

`/home/admin/config.scripts/internet.sshtunnel.py on test@raspiblitz.com "10009<20009"`

You can even set multiple port forwardings like with:

`/home/admin/config.scripts/internet.sshtunnel.py on test@raspiblitz.com "10009<20009" "8080<9090"`

Please beware that after you set such a port forwarding you need to set the domain of the public server as a `DynamicDNS` name (leave update url empty) and then connect mobile wallets fresh or export again the macaroons/certs. When connecting the mobile wallets you may need to adjust ports manually after QR code scan. And if you SSH tunnel the LND node port `9735` you may also need to sun the custom LND port script and maybe also a manual set of the domain in the LND service is needed. This all is very experimental at the moment ... better integration will come in the future.

To switch this SSH tunneling off again use: 

`/home/admin/config.scripts/internet.sshtunnel.py off` and also deactivate the DynamicDNS again. 

## How to setup just a port-forwarding user on my public server?

Make sure the `/etc/ssh/sshd_config` has the following lines at the end:

```
RSAAuthentication yes
PubkeyAuthentication yes
GatewayPorts yes
AllowTcpForwarding yes
AuthorizedKeysFile  /etc/ssh/authorized_keys/%u
```

The last one stores all authorized_keys in one directory with a file per user. See https://serverfault.com/questions/313465/is-a-central-location-for-authorized-keys-a-good-idea#424659 To prepare this run:
```
mkdir /etc/ssh/authorized_keys
groupadd forwardings
```

To add a forwarding user run:
```
useradd -g forwardings -d /home [USERNAME]
echo "command="date" [CONTENT-OF-RASPIBLITZ-ROOT-SSH-PUBKEY]" > /etc/ssh/authorized_keys/[USERNAME]
passwd [USERNAME]
```

The `[CONTENT-OF-RASPIBLITZ-ROOT-SSH-PUBKEY]` you get when running the `internet.sshtunnel.py` script on the RaspiBlitz (see above).

