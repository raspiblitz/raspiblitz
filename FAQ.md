# FAQ - Frequently Asked Questions

## How do I generate a Debug Report?

If your RaspiBlitz is not working right and you like to get help from the community, its good to provide more debug information, so other can better diagnose your problem - please follow the following steps to generate a debug report:

- ssh into your raspiblitz as admin user with your password A
- If you see the menu - use CTRL+C to get to the terminal
- To generate debug report run: `./XXdebugLogs.sh`
- Then copy all output beginning with `*** RASPIBLITZ LOGS ***` and share this

*PLEASE NOTICE: Its possible that this logs can contain private information (like IPs, node IDs, ...) - just share publicly what you feel OK with.*

## How to update my RaspiBlitz (AFTER version 0.98)?

To prepare the RaspiBlitz update:

- main menu > OFF
- remove power
- remove SD card

Now download the new RaspiBlitz SD card image and write it to your SD card .. yes you simply overwrite the old one, it's OK, all your personal data is on the HDD (if you haven't done any manual changes to the system). See details about latest SD card image here: https://github.com/rootzoll/raspiblitz#scenario-2-start-at-home

If done successfully, simply put the SD card into the RaspiBlitz and power on again. Then follow the instructions on the display ... and dont worry, you dont need to re-download the blockchain again.

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

## I have the full blockchain on another computer. How do I copy it to the RaspiBlitz?

Copying a already synced blockchain from another computer (for example your Laptop) can be a quick way to get the RaspiBlitz started. Also that way you synced and verified the blockchain yourself and not trusting the RaspiBlitz FTP/Torrent downloads (dont trust, verify).

One requirement is that the blockchain is from another bitcoin-core client with version greater or equal to 0.17.1 with transaction index switched on (`txindex=1` in the `bitcoin.conf`). 

But we dont copy the data via USB to the device, because the HDD needs to be formatted in EXT4 and that is usually not read/writeable by Windows or Mac computers. So I will explain a way to copy the data thru your local network. This should work from Windows, Mac, Linux and even from another already synced RaspiBlitz.

Both computers (your RaspberryPi and the other computer with the full blockchain on) need to be connected to the same local network. Make sure that bitcoin is stoped on the computer containing the blockchain. If your blockchain source is another RaspiBlitz run on the terminal `sudo systemctl stop bitcoind` and then go to the directory where the blochcian data is with `cd /mnt/hdd/bitcoin` - when copy/transfer is done later reboot a RaspiBlitz source with `sudo shutdown -r now`.

If everything of the above is prepared, start the setup of the new RaspiBlitz with a fresh SD card (like explained in the README) - its OK that there is no blockchain data on your HDD yet - just follow the setup. When you get to the setup-point `Getting the Blockchain` choose the COPY option. Starting from version 1.0 of the RaspiBlitz this will give you further detailed instructions how to transfere the blockchain data onto your RaspiBlitz. In short: On your computer with the blockchain data source you will execute SCP commands, that will copy the data over your Local Network to your RaspiBlitz. 

Once you finished all the transferes the Raspiblitz will make a quick-check on the data - but that will not guarantee that everything in detail was OK with the transfere. Check further FAQ answeres if you get stuck or see a final sync with a value below 90%.

## Why is taking my torrent download of the blockchain so long?

Its a lot of data and torrent seeds can not be garantuued. Normally it should be done within 24 hours. If it takes longer then 2 days consider to abort the torrent download by pressing 'x' and choose FTP download as fallback ... will also take some time, but should be more stable. If even that is not working - choose SYNC option, which will take over a week, but is the classic way to get the blockchain thru the bitcoin peer2peer network.   

## Why is my "final sync" taking so long?

First of all if you see a final sync over 90% and you can see from time to time small increase - you should be OK ... this can take some looong time to catch up with the network. Only in the case that you activly choose the `SYNC` option in the `Getting the Blockchain` a final sync under 90% is OK. If you did a torrent, a FTP or a copy from another computer and seeing under 90% somthing went wrong and the setup process is ignoring your prepared Blockchain and doing a full sync - which can almost take forever on a raspberryPi.

So if something is wrong (like mentioned above) then try again from the beginning. You need to reset your HDD for a fresh start: SSH in as admin user. Abort the final sync info with CTRL+c to get to the terminal. There run `sudo /home/admin/XXcleanHDD.sh -all` and follow the script to delete all data in HDD. When finsihed power down with `sudo shutdown now`. Then make a fresh SD card from image and this time try another option to get the blockchain. If you run into trouble the second time, please report an issue on GitHub.

## How to backup my Lightning Node?

CAUTION: Restoring a backup can lead to LOSS OF ALL CHANNEL FUNDS if it's not the latest channel state. There is no perfect backup solution for lightning nodes yet - this topic is in development by the community.

But there is one safe way to start: Store your LND wallet seed (list of words you got on wallet creation) in a safe place. Its the key to recover access to your on-chain funds - your coins that are not bound in an active channel.

Recovering the coins that you have in an active channel is a bit more complicated. Because you have to be sure that you really have an up to date backup of your channel state data. The problem is: If you post an old state of your channel, to the network this looks like an atempt to cheat, and your channel partner is allowed claim all the funds in the channel.

To really have a reliable backup, such feature needs to be part of the LND software. Almost every other solution would not be perfect. Thats why RaspiBlitz is not trying to provide a backup feature at the moment.

But you can try to backup at your own risk. All your Lightning Node data is within the `/mnt/hdd/lnd` directory. Just run a backup of that data when the lnd service is stopped.

## What is this mnemonic seed word list?

With the 24 word list given you by LND on wallet creation you can recover your private key (BIP 39). You should write it down and store it at a save place. 

For more background on mnemonic seeds see this video: https://www.youtube.com/watch?v=wWCIQFNf_8g

# How does PASSWORD D effects the word seed?

On wallet creation you get asked if you want to protect your word seed list with an additional password. If you choose so, RaspiBlitz recommends you to use your PASSWORD D at this point.

To use a an additional password for your seed words is optional. If you choose so, you will need the password to recover your private key from your your seed words later on. Without this password your private key cannot be recovered from your seed words. So the password adds an additional layer of security, if someone finds your written down word list.

## How can I recover my coins from a failing RaspiBlitz?

You might run into a situation where your hardware fails or the software starts to act buggy. So you decide to setup a fresh RaspiBlitz, like in the chapter above "Update to a new SD Card Release" - but the closing channels and cashing out is not working anymore. So whats about the funds you already have on your failing setup?

There is not a perfect way yet to backup/recover your coins, but you can try the following to make the best out of the situation:

### 1) Recover from Wallet Seed

Remember those 24 words you were writing down during the setup? Thats your "cipher seed" - now this words are important to recover your wallet. If you dont have them anymore: skip this chapter and read option 2. If you still have the cypher seed: good, but read the following carefully:

With the cypher seed you can recover the bitcoin wallet that LND was managing for you - but it does not contain all the details about the channels you have open - its just the key to your funding wallet. If you were able to close all channels or never opened any channels, then everything is OK and you can go on. If you had open channels with funds in there, the following is to consider:

* You now rely on your channel counter parts to force close the channel at one point. If they do, the coins will be available to use in your funding wallet again at one point in the future - after force close delay.
* If your channel counter parts never force close the channel (because they are offline too) your channel funds can be frozen forever.

So going this way there is a small risk, that you will not recover your funds. But normally if your channel counter parts are still online, see that you will not come back online and they have themselves some funds on their channel side with you: They have an incentive to force close the channel to make use of their funds again.

So here is what todo if you want to "Recover from Wallet Seed" with RaspiBlitz:

- SetUp a fresh RaspiBlitz (fresh SD-Card image and clean HDD).
- During the new SetUp you get to the point of creating the LND wallet (see image below).
- When you get asked "do you have an existing cypher wallet" answere `y` this time.
- Follow the dialog and enter the cypher seed.
- If you get asked at the end for the password D to encrypt your cypher seed, use the same as the last time. If you havent entered one last time, just press Enter again.

![SSH8](pictures/ssh8-wallet.png)

Then give LND some time to rescan the blockchain. In the end you will have restored your funding wallet. You maybe need to wait for your old channel counter parts to force close the old channels until you see the coins back displayed.

### 2) LND Channel State Backup

This second option is very very risky and can lead to complete loss of funds. And it olny can work, if you can still access the HDD content of your failing RaspiBlitz. It should only be used if you lost your cypher seed for the option above, forgot your cypher seed encryption password or your old channel counter parts are offline, too.

What you do is in priciple:
- Make a copy of the HDD directory `/mnt/hdd/lnd`
- Setup a fresh RaspiBlitz
- Stop LND with `sudo systemctl stop lnd`
- Replace the new `/mnt/hdd/lnd` with your backuped version
- Reboot the RaspiBlitz

This is highly experimental. And again: If you restore the LND with an backup that is not representing the latest channel state, this will trigger the lightning "penalty" mechanism - allowing your channel counter part to grab all the funds from a channel. Its a measure of last resort. But if its working for you, let us know.

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

## How do I shrink the QR code for connecting my Shango/Zap mobile phone?

Make the fonts smaller until the QR code fits into your (fullscreen) terminal. In OSX use `CMD` + `-` key. In LINUX use `CTRL`+ `-` key. On WINDOWS Putty go into the settings and change the font size: https://globedrill.com/change-font-size-putty

## Why is my bitcoin IP on the display red?

The bitcoin IP is red, when the RaspiBlitz detects that it cannot reach the port of bitcoin node from the outside. This means the bitcoin node can peer with other bitcoin nodes, but other bitcoin nodes cannot initiate a peering with you. Dont worry, you dont need a publicly reachable bitcoin node to run a (public) lightning node. If you want to change this however, you need to forward port 8333 on your router to the the RaspiBlitz. How to do this is different on every router.

## Why is my node address on the display red?

The node address is red, when the RaspiBlitz detects that it cannot reach the port of the LND node from the outside - when the device is behind a NAT or firewall of the the router. Your node is not publicly reachable. This means you can peer+openChannel with other public nodes, but other nodes cannot peer+openChannel with you. To change this you need to forward port 9735 on your router to the the RaspiBlitz. How to do this is different on every router.

## Why is my node address on the display yellow (not green)?

Yellow is OK. The RaspiBlitz can detect, that it can reach a service on the port 9735 of your public IP - this is in most cases the LND of your RaspiBlitz. But the RaspiBlitz cannot 100% for sure detect that this is its own LND service on that port - thats why its just yellow, not green. 

#### Can I run the RaspiBlitz as Backend for BTCPayServer?

BTCPay Server is a solution to be your own payment processor to accept Lightning Payments for your online store: https://github.com/btcpayserver/btcpayserver 

You can find setup instructions for a experimental setup here: https://goo.gl/KnTzLu

Thanks to @RobEdb (ask on twitter for more details) running his demo store with RaspiBlitz: https://store.edberg.eu - buy a picture of [him and Andreas](https://store.edberg.eu/produkt/jag-andreas/) :)

## I dont have an LAN router - how to connect to my RaspiBlitz?

To connect a RaspiBlitz directly (without a router/switch) to your laptop and share the WIFI internet connection, you can follow this [guide for OSX](https://medium.com/@tzhenghao/how-to-ssh-into-your-raspberry-pi-with-a-mac-and-ethernet-cable-636a197d055). 

In short:

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

`wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh 'dev'`

## How can I build an SD card from my forked GitHub Repo?

If you fork the RaspiBlitz repo (much welcome) and you want to run that code on your RaspiBlitz, there are two ways to do that:

* The quick way: For small changes in scripts, go to `/home/admin` on your running RaspiBlitz, delete the old git with `sudo rm -r raspiblitz` then replace it with your code `git clone [YOURREPO]` and `/home/admin/XXsyncScripts.sh`

* The long way: If you like to install/remove/change services and system configurations you need to build a SD card from your own code. Prepare like in [Build the SD Card Image](README.md#build-the-sd-card-image) from the README but in the end run the command:

`wget https://raw.githubusercontent.com/[GITHUB-USERNAME]/raspiblitz/[BRANCH]/build.sdcard/raspbianStretchDesktop.sh && sudo bash raspbianStretchDesktop.sh [BRANCH] [GITHUB-USERNAME]

If you are then working in your forked repo and want to update the scripts on your RaspiBlitz with your latest repo changes, run `/home/admin/XXsyncScripts.sh` - thats OK as long as you dont make changes to the sd card build script - then you would need to build a fresh sd card again from your repo.

## What other case options do I have?

You can replace the generic case in the shopping lists with a customized 3D printed for the RaspiBlitz called "Lightning Shell" - great work by @CryptoCloaks

https://thecryptocloak.com/product/lightningshell/

![LightningShell](pictures/lightningshell.png)

Also there are first free 3D open source files in this repo in the directory `case.3dprint` that you can selfprint. Those are much simpler then the 'Lightning Shell' and are not finished yet. But feel free to try out and improve - PullRequests welcome.   