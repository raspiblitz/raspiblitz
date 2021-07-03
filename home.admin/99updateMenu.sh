#!/bin/bash

# load raspiblitz config data
source /home/admin/_version.info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 2>/dev/null

## PROCEDURES

release()
{
  whiptail --title "Update Instructions" --yes-button "Not Now" --no-button "Start Update" --yesno "To update your RaspiBlitz to a new version:

- Download the new SD card image to your laptop:
  https://github.com/rootzoll/raspiblitz
- Flash that SD card image to a new SD card (best)
  or override old SD card after shutdown (fallback) 
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
    /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
    echo
    echo "PRESS ENTER to continue once you're done downloading."
    read key
  else
    clear
    echo "*************************************"
    echo "* JUST MAKING BACKUP TO OLD SD CARD"
    echo "*************************************"
    echo "please wait .."
    sleep 2
    /home/admin/config.scripts/lnd.backup.sh lnd-export
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
  whiptail --title "Patching Notice" --yes-button "Dont Patch" --no-button "Patch Menu" --yesno "This is the possibility to patch your RaspiBlitz:
It means it will sync the program code with the
GitHub repo for your version branch v${codeVersion}.

This can be useful if there are important updates 
in between releases to fix severe bugs. It can also
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
  source <(sudo /home/admin/config.scripts/blitz.github.sh info)

  # Patch Options
  OPTIONS=(PATCH "Patch/Sync RaspiBlitz with GitHub Repo" \
           REPO "Change GitHub Repo to sync with" \
           BRANCH "Change GitHub Branch to sync with" \
           PR "Checkout a PullRequest to test"
	)

  CHOICE=$(whiptail --clear --title "GitHub-User: ${activeGitHubUser} Branch: ${activeBranch}" --menu "" 11 55 4 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  clear
  case $CHOICE in
    PATCH)
      sudo -u admin /home/admin/config.scripts/blitz.github.sh -run
      sleep 4
      whiptail --title " Patching/Syncing " --yes-button "Reboot" --no-button "Skip Reboot" --yesno "  OK patching/syncing done.

  By default a reboot is advised.
  Only skip reboot if you know
  it will work without restart.
      " 11 40
      if [ $? -eq 0 ]; then
        clear
        echo "REBOOT .."
        /home/admin/config.scripts/blitz.shutdown.sh reboot
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
        source <(sudo -u admin /home/admin/config.scripts/blitz.github.sh -clean ${activeBranch} ${newGitHubUser})
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
        source <(sudo -u admin /home/admin/config.scripts/blitz.github.sh ${newGitHubBranch})
        if [ ${#error} -gt 0 ]; then
          whiptail --title "ERROR" --msgbox "${error}" 8 30
        fi
      fi
      patch
      exit 1
      ;;
    PR)
      clear
      echo "..."
      pullRequestID=$(whiptail --inputbox "\nPlease enter the NUMBER of the PullRequest on RaspiBlitz Repo '${activeGitHubUser}'?" 10 46 --title "Checkout PullRequest ID" 3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus = 0 ]; then
        pullRequestID=$(echo "${pullRequestID}" | cut -d " " -f1)
        echo "# --> " $pullRequestID
        cd /home/admin/raspiblitz
        git fetch origin pull/${pullRequestID}/head:pr${pullRequestID}
        error=""
        source <(sudo -u admin /home/admin/config.scripts/blitz.github.sh pr${pullRequestID})
        if [ ${#error} -gt 0 ]; then
          whiptail --title "ERROR" --msgbox "${error}" 8 30
        else
          echo "# update installs .."
          /home/admin/config.scripts/blitz.github.sh -justinstall
        fi
      fi
      exit 1
      ;;
  esac

}

lnd()
{

  # get lnd info
  source <(sudo -u admin /home/admin/config.scripts/lnd.update.sh info)

  # LND Update Options
  OPTIONS=()
  if [ ${lndUpdateInstalled} -eq 0 ]; then
    OPTIONS+=(VERIFIED "Optional LND update to ${lndUpdateVersion}")
  fi
  OPTIONS+=(RECKLESS "Experimental LND update to ${lndLatestVersion}")

  CHOICE=$(whiptail --clear --title "Update LND Options" --menu "" 9 60 2 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  clear
  case $CHOICE in
    VERIFIED)
      if [ ${lndUpdateInstalled} -eq 1 ]; then
        whiptail --title "ALREADY INSTALLED" --msgbox "The LND version ${lndUpdateVersion} is already installed." 8 30
        exit 1
      fi
      whiptail --title "OPTIONAL LND UPDATE" --yes-button "Cancel" --no-button "Update" --yesno "BEWARE on updating to LND v${lndUpdateVersion}:

${lndUpdateComment}

Do you really want to update LND now?
      " 16 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 1
      fi
      # if loop is installed remove
      if [ "${loop}" == "on" ]; then
        sudo -u admin /home/admin/config.scripts/bonus.loop.sh off
      fi
      error=""
      warn=""
      source <(sudo -u admin /home/admin/config.scripts/lnd.update.sh verified)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      else
        # if loop was installed before reinstall
        if [ "${loop}" == "on" ]; then
          sudo -u admin /home/admin/config.scripts/bonus.loop.sh on
        fi
        /home/admin/config.scripts/blitz.shutdown.sh reboot
        sleep 8
      fi
      ;;
    RECKLESS)
      whiptail --title "RECKLESS LND UPDATE to ${lndLatestVersion}" --yes-button "Cancel" --no-button "Update" --yesno "Using the 'RECKLESS' LND update will simply
grab the latest LND release published on the LND GitHub page (also release candidates).

There will be no security checks on signature, etc.

This update mode is only recommended for testing and
development nodes with no serious funding. 

Do you really want to update LND now?
      " 16 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 1
      fi
      error=""
      source <(sudo -u admin /home/admin/config.scripts/lnd.update.sh reckless)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      else
        /home/admin/config.scripts/blitz.shutdown.sh reboot
        sleep 8
      fi
      ;;
  esac
}

bitcoinUpdate() {
  # get bitcoin info
  source <(sudo -u admin /home/admin/config.scripts/bitcoin.update.sh info)

  # bitcoin update options
  OPTIONS=()
  if [ ${bitcoinUpdateInstalled} -eq 0 ]; then
    OPTIONS+=(TESTED "Optional Bitcoin Core update to ${bitcoinVersion}")
  fi
  if [ $installedVersion != $bitcoinLatestVersion ]&&[ ${bitcoinVersion} != ${bitcoinLatestVersion} ];then
    OPTIONS+=(RECKLESS "Untested Bitcoin Core update to ${bitcoinLatestVersion}")
  fi
  OPTIONS+=(CUSTOM "Update Bitcoin Core to a chosen version")
  CHOICE=$(dialog --clear \
                --backtitle "" \
                --title "Bitcoin Core Update Options" \
                --ok-label "Select" \
                --cancel-label "Back" \
                --menu "" \
                9 60 3 \
          "${OPTIONS[@]}" 2>&1 >/dev/tty)

  case $CHOICE in
    TESTED)
      if [ ${bitcoinUpdateInstalled} -eq 1 ]; then
        whiptail --title "ALREADY INSTALLED" \
        --msgbox "The Bitcoin Core version ${bitcoinUpdateVersion} is already installed." 8 30
        exit 1
      fi
      whiptail --title "OPTIONAL Bitcoin Core update" --yes-button "Cancel" --no-button "Update" \
      --yesno "Info on updating to Bitcoin Core v${bitcoinVersion}:

This Bitcoin Core version was tested on this system.
Will verify the binary checksum and signature.

Do you really want to update Bitcoin Core now?
      " 12 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 1
      fi

      error=""
      warn=""
      source <(sudo -u admin /home/admin/config.scripts/bitcoin.update.sh tested)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      else
        sleep 8
      fi
      ;;
    RECKLESS)
      whiptail --title "UNTESTED Bitcoin Core update to ${bitcoinLatestVersion}" --yes-button "Cancel" \
      --no-button "Update" --yesno "Using the 'RECKLESS' Bitcoin Core update will grab
the latest stable Bitcoin Core release published on the Bitcoin Core GitHub page.

This Bitcoin Core version was NOT tested on this system.
Will verify the binary checksum and signature.

Do you really want to update Bitcoin Core now?
      " 16 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 1
      fi
      error=""
      source <(sudo -u admin /home/admin/config.scripts/bitcoin.update.sh reckless)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      else
        sleep 8
      fi
      ;;
    CUSTOM)
      sudo -u admin /home/admin/config.scripts/bitcoin.update.sh custom
      ;;
  esac
}

# quick call by parameter
if [ "$1" == "github" ]; then
  patch
  exit 0
fi

# Basic Options Menu
HEIGHT=10 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=55
CHOICE_HEIGHT=4 # 1 line / OPTIONS
OPTIONS=(
RELEASE "RaspiBlitz Release Update/Recovery"
PATCH "Patch RaspiBlitz v${codeVersion}"
LND "Interim LND Update Options"
BITCOIN "Bitcoin Core Update Options"
)

if [ "${bos}" == "on" ]; then
  OPTIONS+=(BOS "Update Balance of Satoshis")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
if [ "${thunderhub}" == "on" ]; then
  OPTIONS+=(THUB "Update ThunderHub")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
if [ "${specter}" == "on" ]; then
  OPTIONS+=(SPECTER "Update Cryptoadvance Specter")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
if [ "${rtlWebinterface}" == "on" ]; then
  OPTIONS+=(RTL "Update RTL")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
if [ "${sphinxrelay}" == "on" ]; then
  OPTIONS+=(SPHINX "Update Sphinx Server Relay")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
if [ "${pyblock}" == "on" ]; then
  OPTIONS+=(PYBLOCK "Update PyBLOCK")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
if [ "${mempoolExplorer}" == "on" ]; then
  OPTIONS+=(MEMPOOL "Update Mempool Explorer")
fi
if [ "${runBehindTor}" == "on" ]; then
  OPTIONS+=(TOR "Update Tor from the source code")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi

CHOICE=$(dialog --clear \
                --backtitle "" \
                --title "Update Options" \
                --ok-label "Select" \
                --cancel-label "Main menu" \
                --menu "" \
          $HEIGHT $WIDTH $CHOICE_HEIGHT \
          "${OPTIONS[@]}" 2>&1 >/dev/tty)

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
  BITCOIN)
    bitcoinUpdate
    ;;
  BOS)
    /home/admin/config.scripts/bonus.bos.sh update
    ;;
  THUB)
    /home/admin/config.scripts/bonus.thunderhub.sh update
    ;;
  SPECTER)
    /home/admin/config.scripts/bonus.cryptoadvance-specter.sh update
    ;;
  RTL)
    /home/admin/config.scripts/bonus.rtl.sh update
    ;;
  SPHINX)
    /home/admin/config.scripts/bonus.sphinxrelay.sh update
    ;;
  PYBLOCK)
    /home/admin/config.scripts/bonus.pyblock.sh update
    ;;
  TOR)
    sudo /home/admin/config.scripts/internet.tor.sh update  
    ;;
  MEMPOOL)
    /home/admin/config.scripts/bonus.mempool.sh update 
    ;;
esac
