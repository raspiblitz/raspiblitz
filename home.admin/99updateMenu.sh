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
    exit 0
  fi

  if [ "${lightning}" != "" ]; then

    whiptail --title "Lightning Data Backup" --yes-button "Download Backup" --no-button "Skip" --yesno "
Before we start the RaspiBlitz Update process,
its recommended to make a backup of all your Lightning
Channel Data and download that file to your laptop.

Do you want to download Lightning Data Backup now?
      " 12 62
    if [ $? -eq 0 ]; then
      if [ "${lightning}" == "lnd" ] || [ "${lnd}" = "on" ]; then
        clear
        echo "***********************************"
        echo "* PREPARING THE LND BACKUP DOWNLOAD"
        echo "***********************************"
        echo "please wait .."
        /home/admin/config.scripts/lnd.compact.sh interactive
        /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
        echo
        echo "PRESS ENTER to continue once you're done downloading."
        read key
      fi
      if [ "${lightning}" == "cl" ] || [ "${cl}" = "on" ]; then
        clear
        echo "*******************************************"
        echo "* PREPARING THE CORE LIGHTNING BACKUP DOWNLOAD"
        echo "*******************************************"
        echo "please wait .."
        /home/admin/config.scripts/cl.backup.sh cl-export-gui
        echo
        echo "PRESS ENTER to continue once you're done downloading."
        read key
      fi
    else
      clear
      echo "*****************************************"
      echo "* JUST MAKING A BACKUP TO THE OLD SD CARD"
      echo "*****************************************"
      echo "please wait .."
      sleep 2
      if [ "${lightning}" == "lnd" ] || [ "${lnd}" = "on" ]; then
        /home/admin/config.scripts/lnd.backup.sh lnd-export
      fi
      if [ "${lightning}" == "cl" ] || [ "${cl}" = "on" ]; then
        /home/admin/config.scripts/cl.backup.sh cl-export
      fi
      sleep 3
    fi
  fi

  whiptail --title "READY TO UPDATE?" --yes-button "START UPDATE" --no-button "Cancel" --yesno "If you start the update: The RaspiBlitz will power down.
Once the LCD is white and no LEDs are blinking anymore:

- Remove the Power from RaspiBlitz
- Exchange the old with the new SD card
- Connect Power back to the RaspiBlitz
- Login again per SSH or WebUI

Do you have the SD card with the new version image ready
and do you WANT TO START UPDATE NOW?
      " 16 62

  if [ $? -eq 1 ]; then
    dialog --title " Update Canceled " --msgbox "
OK. RaspiBlitz will NOT update now.
      " 7 39
    sudo systemctl start lnd 2>/dev/null
    sudo systemctl start lightningd 2>/dev/null
    exit 0
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
    exit 0
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

  CHOICE=$(whiptail --clear --title " GitHub user:${activeGitHubUser} branch:${activeBranch} (${commitHashShort})" --menu "" 11 60 4 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  clear
  case $CHOICE in
    PATCH)
      echo
      echo "#######################################################"
      echo "### UPDATE BLITZ --> SCRIPTS (code)"
      /home/admin/config.scripts/blitz.github.sh -run
      echo
      echo "#######################################################"
      echo "### UPDATE BLITZ --> API"
      sudo /home/admin/config.scripts/blitz.web.api.sh update-code
      echo
      echo "#######################################################"
      echo "### UPDATE BLITZ --> WEBUI"
      sudo /home/admin/config.scripts/blitz.web.ui.sh update
      sleep 5
      whiptail --title " Patching/Syncing " --yes-button "Reboot" --no-button "Skip Reboot" --yesno "  OK patching/syncing done.

  By default a reboot is advised.
  Only skip reboot if you know
  it will work without restart.
      " 11 40
      if [ $? -eq 0 ]; then
        clear
        echo "REBOOT .."
        sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
        sleep 8
        exit 1
      else
        echo "SKIP REBOOT .."
        exit 0
      fi
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
        source <(sudo -u admin /home/admin/config.scripts/blitz.github.sh ${activeBranch} ${newGitHubUser})
        if [ ${#error} -gt 0 ]; then
          whiptail --title "ERROR" --msgbox "${error}" 8 30
        fi
      fi
      patch all
      exit 0
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
      patch all
      exit 0
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
      exit 0
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
        exit 0
      fi
      whiptail --title "OPTIONAL LND UPDATE" --yes-button "Cancel" --no-button "Update" --yesno "BEWARE on updating to LND v${lndUpdateVersion}:

${lndUpdateComment}

Do you really want to update LND now?
      " 16 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 0
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
        whiptail \
         --title " LND update " \
         --yes-button "Reboot" \
         --no-button "Skip Reboot" \
         --yesno \
"OK LND update is done.

By default a reboot is advised to sync macaroons and the TLS certificate.
Consider rebooting later manually if encountering any problems.
      " 12 50
        if [ $? -eq 0 ]; then
          clear
          echo "# REBOOT .."
          sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
          sleep 8
          exit 1
        else
          echo "# SKIP REBOOT"
          echo "# starting the lnd.service .."
          sudo systemctl start lnd
          exit 0
        fi
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
        exit 0
      fi
      error=""
      source <(sudo -u admin /home/admin/config.scripts/lnd.update.sh reckless)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      else
        whiptail \
         --title " LND update " \
         --yes-button "Reboot" \
         --no-button "Skip Reboot" \
         --yesno \
"OK LND update is done.

By default a reboot is advised to sync macaroons and the TLS certificate.
Consider rebooting later manually if encountering any problems.
      " 12 50
        if [ $? -eq 0 ]; then
          clear
          echo "# REBOOT .."
          sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
          sleep 8
          exit 1
        else
          echo "# SKIP REBOOT"
          echo "# starting the lnd.service .."
          sudo systemctl start lnd
          exit 0
        fi
        sleep 8
      fi
      ;;
  esac
}

cl()
{

  # get cl info
  source <(sudo -u admin /home/admin/config.scripts/cl.update.sh info)

  # Core Lightning Update Options
  OPTIONS=()
  if [ ${clUpdateInstalled} -eq 0 ]; then
    OPTIONS+=(VERIFIED "Optional Core Lightning update to ${clUpdateVersion}")
  fi
  OPTIONS+=(RECKLESS "Experimental Core Lightning update to ${clLatestVersion}")

  CHOICE=$(whiptail --clear --title "Update Core Lightning Options" --menu "" 9 60 2 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  clear
  case $CHOICE in
    VERIFIED)
      if [ ${clUpdateInstalled} -eq 1 ]; then
        whiptail --title "ALREADY INSTALLED" --msgbox "The Core Lightning version ${clUpdateVersion} is already installed." 8 30
        exit 0
      fi
      whiptail --title "OPTIONAL Core Lightning UPDATE" --yes-button "Cancel" --no-button "Update" --yesno "BEWARE on updating to Core Lightning v${clUpdateVersion}:

${clUpdateComment}

Do you really want to update Core Lightning now?
      " 16 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 0
      fi
      error=""
      warn=""
      source <(sudo -u admin /home/admin/config.scripts/cl.update.sh verified)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      else
        echo "# Core Lightning was updated successfully"
        exit 0
      fi
      ;;
    RECKLESS)
      whiptail --title "RECKLESS Core Lightning UPDATE to ${clLatestVersion}" --yes-button "Cancel" --no-button "Update" \
      --yesno "Using the 'RECKLESS' Core Lightning update will download the latest Core Lightning release published on the Core Lightning GitHub page.

The update was not tested as a part of the release.

This update mode is only recommended for testing and
development nodes with no serious funding.

Do you really want to update Core Lightning now?
      " 16 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 0
      fi
      error=""
      source <(sudo -u admin /home/admin/config.scripts/cl.update.sh reckless)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      else
        echo "# Core Lightning was updated successfully"

        # unlock or fix issues from the logs
        /home/admin/config.scripts/cl.hsmtool.sh unlock ${chain}net

        exit 0
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
        exit 0
      fi
      whiptail --title "OPTIONAL Bitcoin Core update" --yes-button "Cancel" --no-button "Update" \
      --yesno "Info on updating to Bitcoin Core v${bitcoinVersion}:

This Bitcoin Core version was tested on this system.
Will verify the binary checksum and signature.

Do you really want to update Bitcoin Core now?
      " 12 58
      if [ $? -eq 0 ]; then
        echo "# cancel update"
        exit 0
      fi

      error=""
      warn=""
      sudo -u admin /home/admin/config.scripts/bitcoin.update.sh tested
      whiptail \
        --title " Bitcoin Core update " \
        --yes-button "Reboot" \
        --no-button "Skip Reboot" \
        --yesno \
"OK Bitcoin Core update is done.

By default a reboot is advised.
      " 9 40
      if [ $? -eq 0 ]; then
        clear
        echo "# REBOOT .."
        sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
        sleep 8
        exit 1
      else
        echo "# SKIP REBOOT"
        echo "# starting the bitcoind.service .."
        sudo systemctl start bitcoind
        exit 0
      fi
      sleep 8
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
        exit 0
      fi
      error=""
      source <(sudo -u admin /home/admin/config.scripts/bitcoin.update.sh reckless)
      if [ ${#error} -gt 0 ]; then
        whiptail --title "ERROR" --msgbox "${error}" 8 30
      fi
      whiptail \
        --title " Bitcoin Core update " \
        --yes-button "Reboot" \
        --no-button "Skip Reboot" \
        --yesno \
"OK Bitcoin Core update is done.

By default a reboot is advised.
      " 9 40
      if [ $? -eq 0 ]; then
        clear
        echo "REBOOT .."
        sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
        sleep 8
        exit 1
      else
        echo "# SKIP REBOOT"
        echo "# starting the bitcoind.service .."
        sudo systemctl start bitcoind
        exit 0
      fi
      sleep 8
      ;;
    CUSTOM)
      sudo -u admin /home/admin/config.scripts/bitcoin.update.sh custom
      whiptail \
        --title " Bitcoin Core update " \
        --yes-button "Reboot" \
        --no-button "Skip Reboot" \
        --yesno \
"OK Bitcoin Core update is done.

By default a reboot is advised.
      " 9 40
      if [ $? -eq 0 ]; then
        clear
        echo "# REBOOT .."
        sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
        sleep 8
        exit 1
      else
        echo "# SKIP REBOOT"
        echo "# starting the bitcoind.service .."
        sudo systemctl start bitcoind
        exit 0
      fi
      sleep 8
      ;;
  esac
}

# quick call by parameter
if [ "$1" == "github" ]; then
  patch all
  exit 0
fi

# Basic Options Menu
WIDTH=55
OPTIONS=()
OPTIONS+=(RELEASE "RaspiBlitz Release Update/Recovery")
OPTIONS+=(PATCH "Patch RaspiBlitz v${codeVersion}")
OPTIONS+=(BITCOIN "Bitcoin Core Update Options")

if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(LND "Interim LND Update Options")
fi

if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(CL "Interim Core Lightning Update Options")
fi

if [ "${bos}" == "on" ]; then
  OPTIONS+=(BOS "Update Balance of Satoshis")
fi

if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(ELECTRS "Update Electrs")
fi

if [ "${RTL}" == "on" ]||[ "${cRTL}" == "on" ]; then
  OPTIONS+=(RTL "Update RTL")
fi

if [ "${thunderhub}" == "on" ]; then
  OPTIONS+=(THUB "Update ThunderHub")
fi

if [ "${lndg}" == "on" ]; then
  OPTIONS+=(LNDG "Update LNDg")
fi

## Disabled for now until the base image has Python 3.10
if [ "${specter}" == "on" ]; then
  OPTIONS+=(SPECTER "Update Specter Desktop")
fi

if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(BTCPAY "Update BTCPayServer")
fi

if [ "${sphinxrelay}" == "on" ]; then
  OPTIONS+=(SPHINX "Update Sphinx Server Relay")
fi

if [ "${mempoolExplorer}" == "on" ]; then
  OPTIONS+=(MEMPOOL "Update Mempool Explorer")
fi

if [ "${jam}" == "on" ]; then
  OPTIONS+=(JAM "Update Jam (JoinMarket WebUI)")
fi

if [ "${runBehindTor}" == "on" ]; then
  OPTIONS+=(TOR "Update Tor from the Torproject repo")
fi

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICE=$(dialog --clear \
                --backtitle "" \
                --title " Update Options " \
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
    patch all
    ;;
  LND)
    lnd
    ;;
  CL)
    cl
    ;;
  BITCOIN)
    bitcoinUpdate
    ;;
  BOS)
    /home/admin/config.scripts/bonus.bos.sh update
    ;;
  ELECTRS)
    /home/admin/config.scripts/bonus.electrs.sh update
    ;;
  RTL)
    /home/admin/config.scripts/bonus.rtl.sh update
    ;;
  THUB)
    /home/admin/config.scripts/bonus.thunderhub.sh update
    ;;
  LNDG)
    /home/admin/config.scripts/bonus.lndg.sh update
    ;;
  SPECTER)
    /home/admin/config.scripts/bonus.specter.sh update
    ;;
  BTCPAY)
    /home/admin/config.scripts/bonus.btcpayserver.sh update
    ;;
  SPHINX)
    /home/admin/config.scripts/bonus.sphinxrelay.sh update
    ;;
  TOR)
    sudo /home/admin/config.scripts/tor.network.sh update
    ;;
  MEMPOOL)
    /home/admin/config.scripts/bonus.mempool.sh update
    ;;
  JAM)
    /home/admin/config.scripts/bonus.jam.sh update
    ;;
esac
