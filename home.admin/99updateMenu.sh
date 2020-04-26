#!/bin/bash

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
source /home/admin/_version.info

clear

# Basic Options
OPTIONS=(RELEASE "RaspiBlitz Release Update/Recovery" \
         PATCH "Patch RaspiBlitz v${codeVersion}" \
         LND "Update LND Release Options"
	)

CHOICE=$(whiptail --clear --title "Update Options" --menu "" 10 55 3 "${OPTIONS[@]}" 2>&1 >/dev/tty)

release()
{
  whiptail --title "Update Instructions" --yes-button "Not Now" --no-button "Start Update" --yesno "To update your RaspiBlitz to a new version:

- Download the new SD card image to your laptop:
  https://github.com/rootzoll/raspiblitz
- Flash that SD card image to a new SD card
- Choose 'Start Update' below.

No need to close channels or download blockchain again.

Do you want to start the Update now?
      " 16 62
  if [ $? -eq 0 ]; then
    exit 1
  fi

  whiptail --title "LND Data Backup" --yes-button "Download Backup" --no-button "Skip" --yesno "
Before we start the RaspiBlitz Update process,
its recommended to make a backup of all your LND Data
and download that file to your laptop.

Do you want to download LND Data Backup now?
      " 12 58
  if [ $? -eq 0 ]; then
    clear
    echo "*************************************"
    echo "* PREPARING LND BACKUP DOWNLOAD"
    echo "*************************************"
    echo "please wait .."
    sleep 2
    /home/admin/config.scripts/lnd.rescue.sh backup
    echo
    echo "PRESS ENTER to continue once your done downloading."
    read key
  else
    clear
    echo "*************************************"
    echo "* JUST MAKING BACKUP TO OLD SD CARD"
    echo "*************************************"
    echo "please wait .."
    sleep 2
    /home/admin/config.scripts/lnd.rescue.sh backup no-download
  fi

  whiptail --title "READY TO UPDATE?" --yes-button "START UPDATE" --no-button "Cancel" --yesno "If you start the update: The RaspiBlitz will power down.
Once the LCD is white and no LEDs are blicking anymore:

- Remove the Power from RaspiBlitz
- Exchange the old with the new SD card
- Connect Power back to the RaspiBlitz
- Follow the instructions on the LCD

Do you have the SD card with the new version image ready
and do you WANT TO START UPDATE NOW?
      " 16 62

  if [ $? -eq 1 ]; then
    dialog --title " Update Canceled " --msgbox "
OK. RaspiBlitz will NOT update now.
      " 7 39
    sudo systemctl start lnd
    exit 1
  fi

  clear
  sudo shutdown now
}

patchNotice()
{
  whiptail --title "Patching Notice" --yes-button "Dont Patch" --no-button "Start Patch" --yesno "This is the possibility to patch your RaspiBlitz:
It means it will sync the program code with the
the GitHub repo for your version branch v${codeVersion}.

This can be usefull if there are important updates 
inbetween releases to fix severe bugs. It can also
be used to sync your own code with your RaspiBlitz 
if you are developing on your own GitHub Repo.

BUT BEWARE: This means RaspiBlitz will contact GitHub,
hotfix the code and might compromise your security.

Do you want to Patch your RaspiBlitz now?
      " 18 58
  if [ $? -eq 0 ]; then
    exit 1
  fi
}

patch()
{

  # get sync info
  source <(sudo /home/admin/XXsyncScripts.sh info)

  # Patch Options
  OPTIONS=(PATCH "Patch/Sync RaspiBlitz with GitHub Repo" \
           REPO "Change GitHub Repo to sync with" \
           BRANCH "Change GitHub Branch to sync with"
	)

  CHOICE=$(whiptail --clear --title "GitHub-User: ${activeGitHubUser} Branch: ${activeBranch}" --menu "" 10 55 3 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  clear
  case $CHOICE in
    PATCH)
      sudo -u admin /home/admin/XXsyncScripts.sh
      sleep 4
      whiptail --title " Patching/Syncing " --yes-button "Reboot" --no-button "Skip Rebbot" --yesno "  OK patching/syncing done.

  By default a reboot is advised.
  Only skip reboot if you know
  it will work without restart.
      " 11 40
      if [ $? -eq 0 ]; then
        clear
        echo "REBOOT .."
        /home/admin/XXshutdown.sh reboot
        sleep 8
      else
        echo "SKIP REBOOT .."
      fi
      exit 1
      ;;
    REPO)
      clear
      echo "..."
      newGitHubUser=$(whiptail --inputbox "\nPlease enter the GitHub USERNAME of the forked RaspiBlitz Repo?" 10 38 ${activeGitHubUser} --title "Change Sync Repo" 3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus = 0 ]; then
        newGitHubUser=$(echo "${newGitHubUser}" | cut -d " " -f1)
        echo "--> " ${newGitHubUser}
        error=""
        source <(sudo -u admin /home/admin/XXsyncScripts.sh -clean ${activeBranch} ${newGitHubUser})
        if [ ${#error} -gt 0 ]; then
          whiptail --title "ERROR" --msgbox "${error}" 8 30
        fi
      fi
      patch
      exit 1
      ;;
    BRANCH)
      clear
      echo "..."
      newGitHubBranch=$(whiptail --inputbox "\nPlease enter the GitHub BRANCH of the RaspiBlitz Repo '${activeGitHubUser}'?" 10 38 ${activeBranch} --title "Change Sync Branch" 3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus = 0 ]; then
        newGitHubBranch=$(echo "${newGitHubBranch}" | cut -d " " -f1)
        echo "--> " $newGitHubBranch
        error=""
        source <(sudo -u admin /home/admin/XXsyncScripts.sh ${newGitHubBranch})
        if [ ${#error} -gt 0 ]; then
          whiptail --title "ERROR" --msgbox "${error}" 8 30
        fi
      fi
      patch
      exit 1
      ;;
  esac

}

lnd()
{
  echo "TODO"
  echo "PRESS ENTER to return to MAIN MENU."
  read key
  exit 1
}

clear
case $CHOICE in
  RELEASE)
    release
    ;;
  PATCH)
    patchNotice
    patch
    ;;
  LND)
    lnd
    ;;
esac