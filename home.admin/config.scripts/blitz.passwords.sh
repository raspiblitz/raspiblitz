#!/bin/bash

# command info
if [ "$1" == "" ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a passwords A,B,C & D"
 echo "blitz.passwords.sh set a [?newpassword] "
 echo "blitz.passwords.sh set b [?newpassword] "
 echo "blitz.passwords.sh set c [?oldpassword] [?newpassword] " # will change lnd & core lightning if installed
 echo "blitz.passwords.sh check [a|b|c] [passwordToCheck]"
 echo "or just as a password enter dialog (result as file)"
 echo "blitz.passworda.sh set [x] [text] [result-file] [?empty-allowed]"
 exit 1
fi

# prepare hased password storage
hashedPasswordSalt=""
hashedPasswordStoragePath="/mnt/hdd/app-data/passwords"
if [ $(df | grep -c "/mnt/hdd") -gt 0 ]; then
  # check if path & salt file exists
  if [ $(sudo ls ${hashedPasswordStoragePath}/salt.txt | grep -c "salt.txt") -eq 0 ]; then
    echo "# creating salt & hashedPasswordStoragePath ..."
    mkdir -p ${hashedPasswordStoragePath}
    echo "$RANDOM-$(date +%N)" | shasum -a 512 | cut -d " " -f1 | cut -c 1-16 > ${hashedPasswordStoragePath}/salt.txt
    chmod 660 ${hashedPasswordStoragePath}/salt.txt
    chown -R admin:admin ${hashedPasswordStoragePath}
  else
    echo "# salt file exists"
  fi
  hashedPasswordSalt=$(sudo cat ${hashedPasswordStoragePath}/salt.txt)
  echo "# hashedPasswordSalt(${hashedPasswordSalt})"
else
  echo "# hashedPasswordSalt - not available yet (no HDD yet)"
fi 

############################
# CHECKING PASSWORDS
############################

if [ "$1" == "check" ]; then

  # brute force protection (just effective to oustide callers)
  # if there was another try within last minute add another 3 seconds delay protection
  source <(/home/admin/_cache.sh meta system_password_bruteforceprotection)
  /home/admin/_cache.sh set system_password_bruteforceprotection on 60
  if [ "${value}" == "on" ] && [ "${stillvalid}" == "1" ]; then
    echo "# multiple tries within last minute - respond slow"
    sleep 5 # advanced brute force protection
  else
    echo "# first try within last minute - respond fast"
    sleep 1 # basic brute force protection
  fi

  typeOfPassword=$2
  if [ "${typeOfPassword}" != "a" ] && [ "${typeOfPassword}" != "b" ] && [ "${typeOfPassword}" != "c" ]; then
    echo "error='unknown password to check'"
    echo "correct=0"
    exit 1
  fi

  passwordToCheck=$3
  clearedPassword=$(echo "${passwordToCheck}" | tr -dc '[:alnum:]-.' | tr -d ' ')
  if [ ${#clearedPassword} -lt ${#passwordToCheck} ]; then
    echo "error='password to check contains unvalid chars'"
    echo "correct=0"
    exit 1
  fi
  
  passwordHashSystem=$(sudo cat ${hashedPasswordStoragePath}/${typeOfPassword}.hash 2>/dev/null)
  passwordHashTest=$(mkpasswd -m sha-512 "${passwordToCheck}" -S "${hashedPasswordSalt:0:16}")
  #echo "# passwordToCheck(${passwordToCheck})"
  #echo "# passwordHashSystem(${passwordHashSystem})"
  #echo "# hashedPasswordSalt(${hashedPasswordSalt})"
  #echo "# passwordHashTest(${passwordHashTest})"
  if [ ${#passwordHashSystem} -eq 0 ]; then
    echo "error='password cannot be checked - no hash available'"
    echo "correct=0"
    exit 1
  fi

  if [ "${passwordHashSystem}" == "${passwordHashTest}" ]; then
    echo "correct=1"
  else
    echo "correct=0"
  fi
  exit

fi 


############################
# SETTING PASSWORDS
############################

# check if started with sudo
echo "runningUser='$EUID'"
if [ "$EUID" -ne 0 ]; then 
  echo "error='need user root'"
  exit 1
fi

if [ "$1" != "set" ]; then
    echo "error='unkown parameter'"
    exit 1
fi

# load raspiblitz config (if available)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then
  network="bitcoin"
fi
if [ ${#chain} -eq 0 ]; then
  chain="main"
fi

# 1. parameter [?a|b|c]
abcd=$2

# run interactive if no further parameters
reboot=0;
OPTIONS=()
if [ ${#abcd} -eq 0 ]; then
    reboot=1;
    emptyAllowed=1
    OPTIONS+=(A "Master Login Password")
    OPTIONS+=(B "RPC/App Password")
    if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
      OPTIONS+=(C "LND Lightning Wallet Password")
    fi
    if [ "${cl}" == "on" ] && [ "${clEncryptedHSM}" == "on" ]; then
      OPTIONS+=(CL "Core Lightning Wallet Password")
    fi
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz" \
                --title "Set Password" \
                --menu "Which password to change?" \
                11 50 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        A)
          abcd='a';
          ;;
        B)
          abcd='b';
          ;;
        C)
          abcd='c';
          ;;
        D)
          abcd='d';
          ;;
        CL)
          abcd='cl';
          ;;
        *)
          exit 0
          ;;
    esac
fi

############################
# PASSWORD A
if [ "${abcd}" = "a" ]; then

  if [ "${hashedPasswordSalt}" == "" ]; then
    echo "error='hdd not mounted yet - cannot set/check blitz passwords yet'"
    echo "correct=0"
    exit 1
  fi

  newPassword=$3

  # if no password given by parameter - ask by dialog
  if [ ${#newPassword} -eq 0 ]; then
    clear

    # ask user for new password A (first time)
    password1=$(whiptail --passwordbox "\nSet new Admin/SSH Password A:\n(min 8chars, 1word, chars+number, no specials)" 10 52 "" --title "Password A" --backtitle "RaspiBlitz - Setup" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ]; then
      if [ ${emptyAllowed} -eq 0 ]; then
        echo "# CANCEL not possible"
        sleep 2
      else
        exit 0
      fi
    fi

    # ask user for new password A (second time)
    password2=$(whiptail --passwordbox "\nRe-Enter Password A:\n(This is new password to login per SSH)" 10 52 "" --title "Password A" --backtitle "RaspiBlitz - Setup" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ]; then
      if [ ${emptyAllowed} -eq 0 ]; then
        echo "# CANCEL not possible"
        sleep 2
      else
        exit 0
      fi
    fi

    # check if passwords match
    if [ "${password1}" != "${password2}" ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Passwords dont Match\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set a
      exit 0
    fi

    # password zero
    if [ ${#password1} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password cannot be empty\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set a
      exit 0
    fi

    # check that password does not contain bad characters
    clearedResult=$(echo "${password1}" | tr -dc '[:alnum:]-.' | tr -d ' ')
    if [ ${#clearedResult} != ${#password1} ] || [ ${#clearedResult} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Contains bad characters (spaces, special chars)\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set a
      exit 0
    fi

    # password longer than 8
    if [ ${#password1} -lt 8 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password length under 8\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set a
      exit 0
    fi

    # use entered password now as parameter
    newPassword="${password1}"

  fi  

  # store password hash
  mkpasswd -m sha-512 "${newPassword}" -S "${hashedPasswordSalt:0:16}" > ${hashedPasswordStoragePath}/a.hash
  chown admin:admin ${hashedPasswordStoragePath}/a.hash
  chmod 660 ${hashedPasswordStoragePath}/a.hash

  # change user passwords and then change hostname
  echo "pi:$newPassword" | sudo chpasswd
  echo "root:$newPassword" | sudo chpasswd
  echo "bitcoin:$newPassword" | sudo chpasswd
  echo "admin:$newPassword" | sudo chpasswd
  sleep 1

  echo "# OK - password A changed for user pi, root, admin & bitcoin"
  echo "error=''"

############################
# PASSWORD B
elif [ "${abcd}" = "b" ]; then

  if [ "${hashedPasswordSalt}" == "" ]; then
    echo "error='hdd not mounted yet - cannot set/check blitz passwords yet'"
    echo "correct=0"
    exit 1
  fi

  newPassword=$3

  # if no password given by parameter - ask by dialog
  if [ ${#newPassword} -eq 0 ]; then
    clear

    # ask user for new password B (first time)
    password1=$(whiptail --passwordbox "\nPlease enter your new Password B:\n(min 8chars, 1word, chars+number, no specials)" 10 52 "" --title "Password B" --backtitle "RaspiBlitz - Setup" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ]; then
      if [ "${emptyAllowed}" == "0" ]; then
        echo "# CANCEL not possible"
        sleep 2
      else
        exit 0
      fi
    fi

    # ask user for new password B (second time)
    password2=$(whiptail --passwordbox "\nRe-Enter Password B:\n" 10 52 "" --title "Password B" --backtitle "RaspiBlitz - Setup" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ]; then
      if [ "${emptyAllowed}" == "0" ]; then
        echo "# CANCEL not possible"
        sleep 2
      else
        exit 0
      fi
    fi

    # check if passwords match
    if [ "${password1}" != "${password2}" ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Passwords dont Match\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set b
      exit 0
    fi

    # password zero
    if [ ${#password1} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password cannot be empty\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set b
      exit 0
    fi

    # check that password does not contain bad characters
    clearedResult=$(echo "${password1}" | tr -dc '[:alnum:]-.' | tr -d ' ')
    if [ ${#clearedResult} != ${#password1} ] || [ ${#clearedResult} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Contains bad characters (spaces, special chars)\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set b
      exit 0
    fi

    # password longer than 8
    if [ ${#password1} -lt 8 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password length under 8\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set b
      exit 0
    fi

    # use entered password now as parameter
    newPassword="${password1}"
  fi

  # store password hash
  mkpasswd -m sha-512 "${newPassword}" -S "${hashedPasswordSalt:0:16}" > ${hashedPasswordStoragePath}/b.hash
  chown admin:admin ${hashedPasswordStoragePath}/b.hash
  chmod 660 ${hashedPasswordStoragePath}/b.hash

  # change in assets (just in case this is used on setup)
  sed -i "s/^rpcpassword=.*/rpcpassword=${newPassword}/g" /home/admin/assets/${network}.conf 2>/dev/null

  # change in real configs
  sed -i "s/^rpcpassword=.*/rpcpassword=${newPassword}/g" /mnt/hdd/${network}/${network}.conf 2>/dev/null
  sed -i "s/^rpcpassword=.*/rpcpassword=${newPassword}/g" /home/admin/.${network}/${network}.conf 2>/dev/null

  # dont reboot - starting either services manually below or they get restarted thru
  # systemd dependencies like on bitcoind (Partof=...) after all configs changed
  reboot=0;

  echo "# restart bitcoind"
  sudo systemctl restart ${network}d

  # NOTE: now other bonus apps configs that need passwordB need to be adapted manually
  # bonus apps that use a "prestart" will adapt themselves on service

  # electrs
  if [ "${ElectRS}" == "on" ]; then
    echo "# changing the RPC password for ELECTRS"
    RPC_USER=$(cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
    sudo sed -i "s/^auth = \"$RPC_USER.*\"/auth = \"$RPC_USER:${newPassword}\"/g" /home/electrs/.electrs/config.toml
    echo "# restarting electrs"
    sudo systemctl restart electrs.service
  fi

  # BTCPayServer
  if [ "${BTCPayServer}" == "on" ]; then
    echo "# changing the RPC password for BTCPAYSERVER"
    sudo sed -i "s/^btc.rpc.password=.*/btc.rpc.password=${newPassword}/g" /home/btcpay/.nbxplorer/Main/settings.config
    echo "# restarting btcpay server"
    sudo systemctl restart btcpayserver.service
  fi

  # JoinMarket
  if [ "${joinmarket}" == "on" ]; then
    echo "# changing the RPC password for JOINMARKET"
    sudo sed -i "s/^rpc_password =.*/rpc_password = ${newPassword}/g" /home/joinmarket/.joinmarket/joinmarket.cfg
    echo "# changing the password for the 'joinmarket' user"
    echo "joinmarket:${newPassword}" | sudo chpasswd
    echo "# restarting jopinmarket API"
    sudo systemctl restart joinmarket-api.service
  fi

  # ThunderHub
  if [ "${thunderhub}" == "on" ]; then
    echo "# changing the password for ThunderHub"
    sudo sed -i "s/^masterPassword:.*/masterPassword: '${newPassword}'/g" /mnt/hdd/app-data/thunderhub/thubConfig.yaml
    echo "# restarting thunderhub.service"
    sudo systemctl restart thunderhub.service
  fi

  # LIT
  if [ "${lit}" == "on" ]; then
    echo "# changing the password for LIT"
    sudo sed -i "s/^uipassword=.*/uipassword=${newPassword}/g" /mnt/hdd/app-data/.lit/lit.conf
    sudo sed -i "s/^faraday.bitcoin.password=.*/faraday.bitcoin.password=${newPassword}/g" /mnt/hdd/app-data/.lit/lit.conf
    echo "# restarting litd.service"
    sudo systemctl restart litd.service
  fi

  # i2pd
  if [ "${i2pd}" == "on" ]; then
    echo "# changing the password for i2pd"
    sudo sed -i "s/^pass = .*/pass = ${newPassword}/g" /etc/i2pd/i2pd.conf
    echo "# restarting i2pd.service"
    sudo systemctl restart i2pd.service
  fi

  # LNDg
  if [ "${lndg}" == "on" ]; then
    echo "# changing the password for lndg"
    /home/admin/config.scripts/bonus.lndg.sh set-password "${newPassword}"
    echo "# restarting lndg services"
    sudo systemctl restart jobs-lndg.service
    sudo systemctl restart rebalancer-lndg.service
    sudo systemctl restart htlc-stream-lndg.service
  fi

  # mempool Explorer
  if [ "${mempoolExplorer}" == "on" ]; then
    echo "# changing the password for mempool Explorer"
    sudo jq ".CORE_RPC.PASSWORD=\"${newPassword}\"" /home/mempool/mempool/backend/mempool-config.json > /var/cache/raspiblitz/mempool-config.json
    sudo mv /var/cache/raspiblitz/mempool-config.json /home/mempool/mempool/backend/mempool-config.json
    sudo chown mempool:mempool /home/mempool/mempool/backend/mempool-config.json
    echo "# restarting mempool.service"
    sudo systemctl restart mempool.service
  fi

  # elements
  if [ "${elements}" == "on" ]; then
    echo "# changing the password for elements"
    sudo sed -i "s/^rpcpassword=.*/rpcpassword=${newPassword}/g" /home/elements/.elements/elements.conf
    sudo sed -i "s/^mainchainrpcpassword=.*/mainchainrpcpassword=${newPassword}/g" /home/elements/.elements/elements.conf
    echo "# restarting elementsd.service"
    sudo systemctl restart elementsd.service
  fi

  echo "# OK -> RPC Password B changed"
  sleep 3

############################
# PASSWORD C
# will change both (lnd & core lightning) if installed
elif [ "${abcd}" = "c" ]; then

  if [ "${hashedPasswordSalt}" == "" ]; then
    echo "error='hdd not mounted yet - cannot set/check blitz passwords yet'"
    echo "correct=0"
    exit 1
  fi

  oldPassword=$3
  newPassword=$4

  if [ "${oldPassword}" == "" ]; then
    # ask user for old password c
    clear
    oldPassword=$(whiptail --passwordbox "\nEnter old Password C:\n" 10 52 "" --title "Old Password C" --backtitle "RaspiBlitz - Passwords" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ] || [ "${oldPassword}" == "" ]; then
      # calling recursive repeat
      sudo /home/admin/config.scripts/blitz.passwords.sh set c
    fi
    echo "# OK ... processing"
  fi

  if [ "${newPassword}" == "" ]; then
    clear

    # ask user for new password c
    newPassword=$(whiptail --passwordbox "\nEnter new Password C:\n" 10 52 "" --title "New Password C" --backtitle "RaspiBlitz - Passwords" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ] || [ "${newPassword}" == "" ]; then
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set c ${oldPassword}
      exit 0
    fi
    # check new password does not contain bad characters
    clearedResult=$(echo "${newPassword}" | tr -dc '[:alnum:]-.' | tr -d ' ')
    if [ ${#clearedResult} != ${#newPassword} ] || [ ${#clearedResult} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Contains bad characters (spaces, special chars)" 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.password.sh set c ${oldPassword}
      exit 0
    fi
    # check new password longer than 8
    if [ ${#newPassword} -lt 8 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password length under 8" 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.password.sh set c ${oldPassword}
      exit 0
    fi

    # ask user to retype new password c
    newPassword2=$(whiptail --passwordbox "\nEnter again new Password C:\n" 10 52 "" --title "New Password C (repeat)" --backtitle "RaspiBlitz - Passwords" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ] || [ "${newPassword}" == "" ]; then
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set c ${oldPassword}
      exit 0
    fi
    echo "# OK ... processing"
    # check if passwords match
    if [ "${newPassword}" != "${newPassword2}" ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Passwords dont Match" 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set c ${oldPassword}
      exit 0
    fi
    echo "# OK ... processing"
  fi

  # CHANGE LND WALLET PASSWORD
  if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then

    echo "# CHANGE LND - PASSWORD C (only mainnet)"

    source <(/home/admin/config.scripts/lnd.autounlock.sh status)
    if [ "${autoUnlock}" == "on" ]; then
      echo "# Make sure Auto-Unlocks off"
      sudo /home/admin/config.scripts/lnd.autounlock.sh off
    fi

    echo "# LND needs to be restarted to lock wallet first .. (please wait)"
    sudo systemctl restart lnd
    sleep 2

    err=""
    source <(sudo /home/admin/config.scripts/lnd.initwallet.py change-password mainnet $oldPassword $newPassword)
    if [ "${err}" != "" ]; then
      echo "error='Was not able to change password'"
      sleep 2
      exit 0
    fi

    if [ "${autoUnlock}" == "on" ]; then
      echo "# Make sure Auto-Unlocks on"
      sudo /home/admin/config.scripts/lnd.autounlock.sh on "${newPassword}"
    fi

    echo "# Password changed"

  else
    echo "# LND not installed/active"
  fi

  # CHANGE CORE LIGHTNING WALLET PASSWORD
  if [ "${cl}" == "on" ] && [ "${clEncryptedHSM}" == "on" ]; then

    echo "# CHANGE CORE LIGHTNING - PASSWORD C (only mainnet)"

    sudo /home/admin/config.scripts/cl.hsmtool.sh change-password mainnet $oldPassword $newPassword
    #TODO: test success

  else
    echo "# CORE LIGHTNING not installed/active/encrypted"
  fi

  # store password hash (either for lnd or core lightning)
  mkpasswd -m sha-512 "${newPassword}" -S "${hashedPasswordSalt:0:16}" > ${hashedPasswordStoragePath}/c.hash
  chown admin:admin ${hashedPasswordStoragePath}/c.hash
  chmod 660 ${hashedPasswordStoragePath}/c.hash

  # final user output
  echo ""
  echo "#OK"
  echo "error=''"

############################
# PASSWORD X
elif [ "${abcd}" = "x" ]; then

    emptyAllowed=0
    if [ "$5" == "empty-allowed" ]; then
      emptyAllowed=1
    fi

    # second parameter is the flexible text
    text=$3
    resultFile=$4
    shred -u "$4" 2>/dev/null

    # ask user for new password (first time)
    password1=$(whiptail --passwordbox "\n${text}:\n(min 8chars, 1word, chars+number, no specials)" 10 52 "" --backtitle "RaspiBlitz" 3>&1 1>&2 2>&3)

    # ask user for new password A (second time)
    password2=""
    if [ ${#password1} -gt 0 ]; then
      password2=$(whiptail --passwordbox "\nRe-Enter the Password:\n(to test if typed in correctly)" 10 52 "" --backtitle "RaspiBlitz" 3>&1 1>&2 2>&3)
    fi

    # check if passwords match
    if [ "${password1}" != "${password2}" ]; then
      dialog --backtitle "RaspiBlitz" --msgbox "FAIL -> Passwords dont Match\nPlease try again ..." 6 52
      # calling recursive repeat
      /home/admin/config.scripts/blitz.passwords.sh set x "$3" "$4" "$5"
      exit 0
    fi

    if [ ${emptyAllowed} -eq 0 ]; then

      # password zero
      if [ ${#password1} -eq 0 ]; then
        dialog --backtitle "RaspiBlitz" --msgbox "FAIL -> Password cannot be empty\nPlease try again ..." 6 52
        # calling recursive repeat
        /home/admin/config.scripts/blitz.passwords.sh set x "$3" "$4" "$5"
        exit 0
      fi

      # check that password does not contain bad characters
      clearedResult=$(echo "${password1}" | tr -dc '[:alnum:]-.' | tr -d ' ')
      if [ ${#clearedResult} != ${#password1} ] || [ ${#clearedResult} -eq 0 ]; then
        dialog --backtitle "RaspiBlitz" --msgbox "FAIL -> Contains bad characters (spaces, special chars)\nPlease try again ..." 6 62
        # calling recursive repeat
        /home/admin/config.scripts/blitz.password.sh set x "$3" "$4" "$5"
        exit 0
      fi

      # password longer than 8
      if [ ${#password1} -lt 8 ]; then
        dialog --backtitle "RaspiBlitz" --msgbox "FAIL -> Password length under 8\nPlease try again ..." 6 52
        # calling recursive repeat
        /home/admin/config.scripts/blitz.passwords.sh set x "$3" "$4" "$5"
        exit 0
      fi

    fi

    # store result is file
    echo "${password1}" > "${resultFile}"

else
  echo "# FAIL: there is no password '${abcd}' (reminder: use lower case)"
  echo "error='no password ${abcd}'"
  exit 0
fi

# when started with menu ... reboot when done
if [ "${reboot}" == "1" ]; then
  echo "# Now rebooting to activate changes ..."
  sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
fi
