## FAQ Development

### What is the process of creating a new SD card image release?

Work notes for the process of producing a new SD card image release:

* Make sure you have the "Versioning" final in your RaspiBlitz Source Code
* Start [`Ubuntu LIVE`](http://releases.ubuntu.com/18.04.3/ubuntu-18.04.3-desktop-amd64.iso) from USB stick
* Under Settings: best to set correct keyboard language & power settings to prevent monitor turn off
* Connect to a secure WiFi (hardware switch on) or LAN
* Download the latest RaspiOS-64bit (zip/xz & sig file) namend in the [build_sdcard.sh](./build_sdcard.sh) and note the SHA256 checksum
* From the browser `Show All Downloads` and from the context menu select `Open Containing Folder`
* On that file manager open context (right click) on the white-space and select `Open in Terminal`
* Compare the checksum with the one you just made note of, using `shasum -a 256 *.zip`
* Install curl if needed `sudo apt-get install -f curl net-tools`
* Check signature: `curl https://www.raspberrypi.org/raspberrypi_downloads.gpg.key | gpg --import && gpg --verify *.sig`
* The result should say "correct signature" and the fingerprint should end with `8738 CD6B 956F 460C`
* Insert an NTFS formatted USB stick and use the file manager to move all files to the USB
* If image is an ZIP file use in file manager context on NTFS USB stick `extract here` to unzip
* Download script for later with `curl https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh > pishrink.sh`
* Connect SD card reader with a SD card (16GB recommended)
* In the file manager open context on the .img-file, select `Open With Disk Image Writer` and write the image to the SD card
* In the file manager open context on `boot` drive free space `open in terminal`
* Run the commands `touch ssh`
* Run the command: `echo "pi:\$6\$TE7HmruYY9EaNiKP\$Vz0inJ6gaoJgJvQrC5z/HMDRMTN2jKhiEnG83tc1Jsw7lli5MYdeA83g3NOVCsBaTVW4mUBiT/1ZRWYdofVQX0" > userconf` and `exit`
* Eject the `boot` and the `NTFS` volume
* Connect a RaspiBlitz (without HDD) to network, insert sd card and power up
* Find the IP of the RaspiBlitz (arp -a or check router)
* In terminal `ssh pi@[IP-OF-RASPIBLITZ]`
* Password is `raspberry`
* Run the following command BUT REPLACE `[BRANCH]` with the branch-string of your latest version
* `wget --no-cache https://raw.githubusercontent.com/rootzoll/raspiblitz/[BRANCH]/build_sdcard.sh && sudo bash build_sdcard.sh -b [BRANCH]`
* Monitor/Check outputs for warnings/errors - install LCD
* Login new with `ssh admin@[IP-OF-RASPIBLITZ]` (pw: raspiblitz) and run `release`
* Disconnect WiFi/LAN on build laptop (hardware switch off) and shutdown
* Remove `Ubuntu LIVE` USB stick and cut power from the RaspberryPi
* Connect USB stick with latest `TAILS` (make it stay offline)
* Boot Tails with extra setting of Admin-Passwort and remember (use later for sudo)
* Menu > Systemtools > Settings > Energy -> best to set monitor to never turn off
* Connect USB stick with GPG signing keys - decrypt drive if needed
* Open Terminal and cd into directory of USB Stick under `/media/amnesia`
* Run `gpg --import ./sub.key`, check and `exit`
* Disconnect USB stick with GPG keys
* Take the SD card from the RaspberryPi and connect with an external SD card reader to the laptop
* Click on `boot` volume once in the file manger
* Connect the NTFS USB stick, open in file manager and delete old files
* Open Terminal and cd into directory of NTFS USB stick under `/media/amnesia`
* `shasum -a 256 ./pishrink.sh` should be `e46e1e1e3c6e3555f9fff5435e2305e99b98aaa8dc28db1814cf861fbb472a69`
* if not: review changes in latest pishrink script
* Run `df` to check on the SD card device name (`boot` - ignore last partition number)
* `dd if=/dev/[sdcarddevice] of=./raspiblitz.img`
* `chmod +x ./pishrink.sh | sudo ./pishrink.sh ./raspiblitz.img`
* `gzip -c ./raspiblitz.img > ./raspiblitz-vX.X-YEAR-MONTH-DAY.img.gz`
* Then run `shasum -a 256 *.gz > sha256.txt`
* Sign with `gpg --output raspiblitz-vX.X-YEAR-MONTH-DAY.img.gz.sig --detach-sign *.gz`
* Shutdown build computer
* Connect the NTFS USB stick to MacOS (it is just read-only)
* Run tests on the new image
* Upload the new image to the Download Server - put sig-file next to it
* Copy SHA256-String into GitHub README and update the download link
* Create Torrent file from image (for example with Transmission) and place in in the `home.admin/assets` folder & link on README

This is a recommended tracker list to be used with the torrent:
```
udp://tracker.coppersurfer.tk:6969/announce
http://tracker.yoshi210.com:6969/announce
http://open.acgtracker.com:1096/announce
http://tracker.skyts.net:6969/announce
udp://9.rarbg.me:2780/announce
http://tracker2.itzmx.com:6961/announce
udp://exodus.desync.com:6969/announce
http://pow7.com:80/announce
udp://tracker.leechers-paradise.org:6969
```

### Versioning

* Major Updates: 1.0.0, 2.0.0, 3.0.0, ... are epic updates signaling that the software reached a new era.
* Main Updates: 1.1.0, 1.2.0, 1.3.0, ... are breaking updates - the reflashing of the sd ard is mandatory.
* Minor Updates: 1.3.0, 1.3.1, 1.3.2, ... are soft updates - can be done by 'patching' the scripts & code, but new sd card reflash is still advised.

### How can I customize my RaspiBlitz or add other software?

The RaspiBlitz is your computer to experiment with. Feel free to add your own scripts, edit the system or install further software from the command line. Just keep in mind that after an update/recovery the RaspiBlitz starts with a fresh and clean operating system again. So all your editings and installs might be gone. To prevent this you should do the following:

- place your own scripts and data that should survive an update/recovery into the `/mnt/hdd/app-data` directory
- put all install commands & modification of the system into the script `/mnt/hdd/app-data/custom-installs.sh` which will be started automatically on a recovery/update.

### GitHub Workflow

- Development is done on the 'dev' branch, new features should be done on single feature branches and merged into 'dev' once ready.
- When a release of a new main-update (see above) comes closer, a new release branch gets created from 'dev' with the first release candidate - the RCs and the final release sd card will be build from this branch.
- All minor-releases will basically all work with the same 'build_sdcard.sh' script so that the code could be updated by just calling 'patch'. Emergency updates on lnd & bitcoin may break this guideline, but basic structure & packaging should stay mostly consistent over a main-update version.
- Once a release is ready, that release branch will be set as the "default" branch on GitHub (so its shown as main page)
- Hot fixes & new features for minor verisons will be created as single branches from the release branch, and once ready will be merged back into that release branch as a Pull Request using 'Squash-Merge' AND then, this 'Squash-Merge' (one single commit) will get cherry-picked into the  'dev' branch ('git cherry-pick COMMITHASH' - may call 'git fetch' & 'git pull' before to make a clean cherry-pick into dev).

### Can I run RaspiBlitz on other computers than RaspberryPi?

There is an experimental section in this GitHub that tries to build for other SingleBoardComputers. Feel free to try it out and share your experience: [alternative.platforms/README.md](alternative.platforms/README.md)

### How can I build an SD card from another branch?

There might be new, but not released features in development that are not yet in the default version branch - but you want to try them out.

To build a SD card image from another branch than master, you follow the [Build the SD Card Image](README.md#build-the-sd-card-image) from the README, but execute the build script from the other branch and add the name of that branch as a parameter to the build script.

For example if you want to make a build from the 'dev' branch you execute the following command:

`wget --no-cache https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build_sdcard.sh && sudo bash build_sdcard.sh -b dev`

If you want to see all the optional parameters for building your sd card, just answere `no` on first question and call `sudo bash build_sdcard.sh --help`.

### How can I build an SD card from my forked GitHub Repo?

If you fork the RaspiBlitz repo (much welcome) and you want to run that code on your RaspiBlitz, there are two ways to do that:

* The quick way: For small changes in a single script, go to `/home/admin` on your running RaspiBlitz, delete the old git with `sudo rm -r raspiblitz` then replace it with your code `git clone [YOURREPO]` and `patch`

* The long way: If you like to install/remove/change services and system configurations you need to build a SD card from your own code. Prepare like in [Build the SD Card Image](README.md#build-the-sd-card-image) from the README but in the end run the command:

`wget --no-cache https://raw.githubusercontent.com/[GITHUB-USERNAME]/raspiblitz/[BRANCH]/build_sdcard.sh && sudo bash build_sdcard.sh -b [BRANCH]`

If you are then working in your forked repo and want to update the scripts on your RaspiBlitz with your latest repo changes, run `patch` - That's OK as long as you don't make changes to the SD card build script - for that you would need to build a fresh SD card again from your repo.

### How can I checkout a new branch from the RaspiBlitz repo to my forked repo?

You need to have your forked repo checked-out on your laptop. There your should see your forked repo as `origin` when you run `git remote -v`. If you don't see an additional `upstream` remote yet, then create it with the following command: `git remote add upstream https://github.com/rootzoll/raspiblitz.git`.

So, first checkout the new branch named `BRANCH` from the original RaspBlitz repo to your local computer with: `git fetch upstream` and then `git checkout -b BRANCH upstream/BRANCH`.

Now push the new branch to your forked GitHub repo with `git push -u origin BRANCH`.

Once the branch is available and synced between the RaspiBlitz GitHub repo, your forked GitHub repo and your local computer git repo, you can start developing.

### How can I sync a branch of my forked GitHub with my local RaspiBlitz?

Since v1.5 of RaspiBlitz there has been an easy way thru the SSH menus: Under `MAIN MENU > UPDATE > PATCH` you have the option to change the GitHub repository and and branch to sync with. You change the GitHub Reposity by setting the GitHub username where you forked the Repo.

So for example: If you forked the RaspiBlitz project (rootzoll/raspiblitz) on GitHub and your GitHub project page is now called: https://github.com/raumi75/raspiblitz ... then just change the repo to sync/patch with to your username `raumi75`.

Now you can use the `Patch/Sync RaspiBlitz with GitHub Repo` to easily keep your RaspiBlitz in sync with your forked repository and develop your own customizations and features.

Background info and doing it manually:

There is a git copy of the original RaspiBlitz GitHub repo on your physical RaspiBlitz in the folder `/home/admin/raspiblitz`. If you change into that folder and run `git remote -v` you can see the set origin repo.

You need to change that origin repo to your forked repo. You do that with:
```
git remote set-url origin [THE-URL-OF-YOUR-FORKED-REPO]
```

Now to sync your branch namend BRANCH on your forked repo with your RaspiBlitz, you always just run:
```
/home/admin/config.scripts/blitz.github.sh BRANCH
```

So your workflow can go like this: You write code on your local computer. Commit to your local repo, push it to your forked repo and use the sync-script above to get the code to your RaspiBlitz.

### How to add an app to the RaspiBlitz?

To add your app you can fork the raspiblitz repo, follow the `/home.admin/config.scripts/bonus.template.sh` script [see code](https://github.com/rootzoll/raspiblitz/blob/dev/home.admin/config.scripts/bonus.template.sh), copy/adapt it, test it on your RaspiBlitz and make a PR back to the main repo.

### How contribute a feature/change from my forked branch back to the RaspiBlitz repo?

In the same way as described above, you can build a new feature or test a change. Once you have something ready that you want to contribute back, you make sure it's pushed to your forked GitHub repo, and then start a pull request from your forked repo to the RaspiBlitz repo.

See more info: https://yangsu.github.io/pull-request-tutorial/

### How can I help testing a Pull Request?

Make sure to have the correct base image.
Then go to the command line and create a branch for the PR:

```
cd /home/admin/raspiblitz
git fetch origin pull/[PRNUMBER]/head:pr[PRNUMBER]
git checkout pr[PRNUMBER]
cd /home/admin
/home/admin/config.scripts/blitz.github.sh -justinstall
```

Now you have the code of the PR active - depending on what scripts are changed you might need to reboot.

To change back to the code:
```
/home/admin/config.scripts/blitz.github.sh master
```

### How can I push changes to an existing Pull Request?

See article: https://tech.sycamore.garden/add-commit-push-contributor-branch-git-github .. only works if your a contributer on raspiblitz repo.