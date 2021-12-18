#!/bin/bash

# keeps the password in memory between restarts: /dev/shm/.${netprefix}cl.pw
# see the reasoning: https://github.com/ElementsProject/lightning#hd-wallet-encryption
# does not store the password on disk unless auto-unlock is enabled
# autounlock password is in /home/bitcoin/.${netprefix}cl.pw

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]||\
  ! echo "$@" | grep -Eq "new|seed|unlock|lock|encrypt|decrypt|autounlock-on|autounlock-off|change-password" ;then
  echo
  echo "Create new wallet or import seed"
  echo "Unlock/lock, encrypt, decrypt, set autounlock or change password for the hsm_secret"
  echo
  echo "Usage:"
  echo "Create new wallet:"
  echo "cl.hsmtool.sh [new] [mainnet|testnet|signet] [?seedPassword]"  
  echo "cl.hsmtool.sh [new-force] [mainnet|testnet|signet] [?seedPassword]"  
  echo "There will be no seedPassword(passphrase) used by default"
  echo "new-force will delete any old wallet and will work without dialog"
  echo
  echo "cl.hsmtool.sh [seed] [mainnet|testnet|signet] [\"space-separated-seed-words\"] [?seedPassword]"  
  echo "cl.hsmtool.sh [seed-force] [mainnet|testnet|signet] [\"space-separated-seed-words\"] [?seedPassword]"  
  echo "The new hsm_secret will be not encrypted if no NewPassword is given"
  echo "seed-force will delete any old wallet and will work without dialog"
  echo
  echo "cl.hsmtool.sh [unlock|lock] <mainnet|testnet|signet>"
  echo "cl.hsmtool.sh [encrypt|decrypt] <mainnet|testnet|signet>"
  echo "cl.hsmtool.sh [autounlock-on|autounlock-off] <mainnet|testnet|signet>"
  echo
  echo "cl.hsmtool.sh [change-password] <mainnet|testnet|signet> <NewPassword>"
  echo
  exit 1
fi

source /mnt/hdd/raspiblitz.conf
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)
hsmSecretPath="/home/bitcoin/.lightning/${CLNETWORK}/hsm_secret"

# password file is on the disk if encrypted and auto-unlock is enabled
passwordFile=/dev/shm/.${netprefix}cl.pw
if grep -Eq "${netprefix}clEncryptedHSM=on" /mnt/hdd/raspiblitz.conf;then
  if grep -Eq "${netprefix}clAutoUnlock=on" /mnt/hdd/raspiblitz.conf;then
    passwordFile=/home/bitcoin/${netprefix}cl.pw
  fi
fi

# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}clEncryptedHSM=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}clEncryptedHSM=off" >> /mnt/hdd/raspiblitz.conf
fi
# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}clAutoUnlock=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}clAutoUnlock=off" >> /mnt/hdd/raspiblitz.conf
fi

#############
# Functions #
#############
function passwordToFile() {
  if [ $# -gt 0 ];then
    text="$1"
  else
    text="Type or paste the decryption passwordC for the $CHAIN C-lightning wallet"
  fi
  # write password into a file in memory
  # trap to delete on any exit
  trap 'rm -f $data' EXIT
  # get password
  data=$(mktemp -p /dev/shm/)

  dialog --clear \
   --backtitle "Enter password" \
   --title "Enter password" \
   --insecure \
   --passwordbox "$text" 8 52 2> "$data"
  # make decison
  pressed=$?
  case $pressed in
    0)
      sudo touch $passwordFile
      sudo chmod 600 $passwordFile
      sudo chown bitcoin:bitcoin $passwordFile
      sudo -u bitcoin tee $passwordFile 1>/dev/null < "$data"
      shred "$data";;
    1)
      shred "$data"
      shred -uvz $passwordFile
      echo "# Cancelled"
      exit 1;;
    255)
      shred "$data"
      shred -uvz $passwordFile
      [ -s "$data" ] && cat "$data" || echo "# ESC pressed."
      exit 1;;
  esac
}

function shredPasswordFile() {
  echo
  echo "# Shredding the passwordFile"
  echo
  if [ -f /dev/shm/.${netprefix}cl.pw ];then
    sudo shred -uvz /dev/shm/.${netprefix}cl.pw
  fi
  if [ -f /home/bitcoin/${netprefix}cl.pw ];then
    sudo shred -uvz /home/bitcoin/${netprefix}cl.pw
  fi
}

function encryptHSMsecret() {
  walletPassword=$3
  if [ ${#walletPassword} -eq 0 ];then
    # ask for password in dialog if $walletPassword is not given in $3
    sudo /home/admin/config.scripts/blitz.setpassword.sh x \
     "Enter the password C to encrypt the C-lightning wallet file (hsm_secret)" \
     "$passwordFile"
    sudo chown bitcoin:bitcoin $passwordFile
    sudo chmod 600 $passwordFile
    walletPassword=$(sudo cat $passwordFile)
  fi  
  (echo $walletPassword; echo $walletPassword) | \
   sudo -u bitcoin lightning-hsmtool encrypt $hsmSecretPath || exit 1
  # setting value in raspiblitz.conf
  sudo sed -i \
    "s/^${netprefix}clEncryptedHSM=.*/${netprefix}clEncryptedHSM=on/g" \
    /mnt/hdd/raspiblitz.conf
  echo "# Encrypted the hsm_secret for C-lightning $CHAIN"
}

function decryptHSMsecret() {
 
  # check if encrypted
  trap 'rm -f "$output"' EXIT
  output=$(mktemp -p /dev/shm/)
  echo "test" | sudo -u bitcoin lightning-hsmtool decrypt "$hsmSecretPath" \
   2> "$output"
  if [ "$(grep -c "hsm_secret is not encrypted" < "$output")" -gt 0 ];then
    echo "# The hsm_secret is not encrypted"
    shredPasswordFile
    echo "# Continue to record in the raspiblitz.conf"
  else
    # setting value in raspiblitz.conf
    sudo sed -i \
     "s/^${netprefix}clEncryptedHSM=.*/${netprefix}clEncryptedHSM=on/g" \
     /mnt/hdd/raspiblitz.conf
    if [ -f $passwordFile ];then
      echo "# Getting the password from $passwordFile"
    else
      passwordToFile
    fi
    if sudo cat $passwordFile | sudo -u bitcoin lightning-hsmtool decrypt \
     "$hsmSecretPath"; then
      echo "# Decrypted successfully"
    else
      # unlock manually
      /home/admin/config.scripts/cl.hsmtool.sh unlock
      # attempt to decrypt again
      sudo cat $passwordFile | sudo -u bitcoin lightning-hsmtool decrypt \
       "$hsmSecretPath" || echo "# Couldn't decrypt"; exit 1
    fi
  fi
  shredPasswordFile
  # setting value in raspiblitz config
  sudo sed -i \
   "s/^${netprefix}clEncryptedHSM=.*/${netprefix}clEncryptedHSM=off/g" \
   /mnt/hdd/raspiblitz.conf
  echo "# Decrypted the hsm_secret for C-lightning $CHAIN"
}

###########
# Options #
########### 
if [ "$1" = "new" ] || [ "$1" = "new-force" ] || [ "$1" = "seed" ] || [ "$1" = "seed-force" ]; then

  # make sure /home/bitcoin/.lightning/bitcoin exists (when lightningd was not run yet)
  if ! sudo ls  /home/bitcoin/.lightning/bitcoin; then
    sudo -u bitcoin mkdir -p /home/bitcoin/.lightning/bitcoin/
  fi

  # check/delete existing wallet
  if [ "$1" = "new-force" ] || [ "$1" = "seed-force" ]; then
    echo "# deleting any old wallet ..."
    sudo rm $hsmSecretPath 2>/dev/null
  else
    if sudo ls $hsmSecretPath 2>1 1>/dev/null; then
      echo "# The hsm_secret is already present at $hsmSecretPath."
      exit 0
    fi
  fi

  # check for https://github.com/trezor/python-mnemonic
  if [ $(pip list | grep -c mnemonic) -eq 0 ];then
    pip install mnemonic==0.19 1>/dev/null
  fi

  if [ "$1" = "new" ]; then
    seedPassword="$3"
    # get 24 words
    source <(python /home/admin/config.scripts/blitz.mnemonic.py generate)
    #TODO seedwords to cl.backup.sh seed-export-gui
    /home/admin/config.scripts/cl.backup.sh seed-export-gui "${seedwords6x4}"
  elif [ "$1" = "new-force" ]; then
    # get 24 words
    source <(python /home/admin/config.scripts/blitz.mnemonic.py generate)
    echo "seedwords='${seedwords}'"
    echo "seedwords6x4='${seedwords6x4}'"
  elif [ "$1" = "seed" ] || [ "$1" = "seed-force" ]; then
    #TODO get seedwords from cl.backup.sh seed-import-gui [$RESULTFILE]
    seedwords="$3"
    seedpassword="$4"
  fi

  # place the seedwords to /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info
  sudo touch /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info
  sudo chown bitcoin:bitcoin /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info
  sudo chmod 600 /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info
  echo "
# This file was placed by cl.hsmtool.sh .
# Contains the seed words from which the hsm_secret in the same directory was generated
seedwords='${seedwords}'
seedwords6x4='${seedwords6x4}'
# Will be removed safely when the hsm_secret is encrypted.
" | sudo -u bitcoin tee /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info

  # pass to 'hsmtool generatehsm hsm_secret'
  if [ ${#seedpassword} -eq 0 ]; then
    (echo "0"; echo "${seedwords}"; echo) | sudo -u bitcoin lightning-hsmtool \
     "generatehsm" $hsmSecretPath 1>&2
  else
    # pass to 'hsmtool generatehsm hsm_secret' - confirm seedPassword
    (echo "0"; echo "${seedwords}"; echo "$seedpassword"; echo "$seedpassword")\
     | sudo -u bitcoin lightning-hsmtool "generatehsm" $hsmSecretPath 1>&2
  fi

  echo "# Re-init the backup plugin with the new wallet"
  /home/admin/config.scripts/cl-plugin.backup.sh on $CHAIN

  exit 0

elif [ "$1" = "unlock" ]; then
  # check if unlocked
  attempt=0
  justUnlocked=0
  while [ $($lightningcli_alias getinfo 2>&1 | grep -c '"id":') -eq 0 ];do
    clError=$(sudo journalctl -n5 -u ${netprefix}lightningd)
    
    # getpassword
    if [ $(echo "${clError}" | \
      grep -c 'encrypted-hsm: Could not read pass from stdin.') -gt 0 ];then
      if [ ${justUnlocked} -eq 0 ];then 
        if [ -f $passwordFile ];then
          echo "# Wrong passwordFile is present"
        else
          echo "# No passwordFile is present"
        fi
        passwordToFile
        sudo systemctl restart ${netprefix}lightningd
        justUnlocked=1
      else
        echo "# Waiting to unlock wallet (2) ... "
        sleep 5
      fi

    # configure --encrypted-hsm 
    elif [ $(echo "${clError}" | \
      grep -c 'hsm_secret is encrypted, you need to pass the --encrypted-hsm startup option.') -gt 0 ];then

        echo "# The hsm_secret is encrypted, but unlock is not configured"
        passwordToFile
        # setting value in raspiblitz config
        sudo sed -i \
          "s/^${netprefix}clEncryptedHSM=.*/${netprefix}clEncryptedHSM=on/g" \
          /mnt/hdd/raspiblitz.conf
        /home/admin/config.scripts/cl.install-service.sh $CHAIN
    
    # get new password 
    elif [ $(echo "${clError}" | \
      grep -c 'Wrong password for encrypted hsm_secret.') -gt 0 ];then
      echo "# Wrong password"
      sudo rm -f $passwordFile
      passwordToFile "Wrong password - type the decryption password for the $CHAIN C-lightning wallet"
      sudo systemctl restart ${netprefix}lightningd
    
    # fail
    elif [ $attempt -eq 12 ];then
      echo "# Failed to unlock the ${netprefix}lightningd wallet - giving up after 1 minute"
      echo "# Check: sudo journalctl -u ${netprefix}lightningd"
      exit 1
    fi
    echo "# Waiting to unlock wallet ... "
    sleep 5
    attempt=$((attempt+1))
  done
  echo "# Ok the ${netprefix}lightningd wallet is unlocked"
  exit 0

elif [ "$1" = "lock" ]; then
  shredPasswordFile
  sudo systemctl restart ${netprefix}lightningd
  exit 0

elif [ "$1" = "encrypt" ]; then
  if [ -f  /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info ];then
    source <(sudo -u bitcoin cat /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info)
    if [ ${#seedwords6x4} -gt 0 ];then
      # show the words one last time
      ack=0
      while [ ${ack} -eq 0 ]
      do
        whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "The backup of seedwords will be deleted, make sure you wrote them down. Store these numbered 24 words in a safe location:\n\n${seedwords6x4}" 13 76
        whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
        if [ $? -eq 1 ]; then
          ack=1
        fi
      done
      deletedWhen="deleted when the hsm_secret was encrypted"
    else
      deletedWhen="not available any more"
    fi
    # delete seedwords.info
    sudo -u bitcoin shred /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info
  fi
  echo "
# This file is placed by cl.hsmtool.sh .
# The seed words from which the hsm_secret in the same directory was generated
# were $deletedWhen.
# The words cannot be generated from the hsm_secret (one way function).
# If you don't have the words the hsm_secret can be still backed up in hex:
# https://lightning.readthedocs.io/BACKUP.html#hsm-secret 
" | sudo -u bitcoin tee /home/bitcoin/.lightning/${CLNETWORK}/seedwords.info
  # encrypt
  walletPassword=$3
  encryptHSMsecret $walletPassword

elif [ "$1" = "decrypt" ]; then
  decryptHSMsecret

elif [ "$1" = "autounlock-on" ]; then
  if grep -Eq "${netprefix}clEncryptedHSM=on" /mnt/hdd/raspiblitz.conf;then
    echo "# Moving the password from $passwordFile to /home/bitcoin/.${netprefix}cl.pw"
    sudo -u bitcoin mv /dev/shm/.${netprefix}cl.pw /home/bitcoin/.${netprefix}cl.pw
  else
    passwordFile=/home/bitcoin/.${netprefix}cl.pw
    passwordToFile
  fi
  # setting value in raspiblitz config
  sudo sed -i \
   "s/^${netprefix}clAutoUnlock=.*/${netprefix}clAutoUnlock=on/g" \
   /mnt/hdd/raspiblitz.conf
  echo "# Autounlock is on for C-lightning $CHAIN"

elif [ "$1" = "autounlock-off" ]; then
  if [ -f /home/bitcoin/${netprefix}cl.pw ];then
    sudo cp /home/bitcoin/.${netprefix}cl.pw /dev/shm/.${netprefix}cl.pw
    sudo shred -uzv /home/bitcoin/.${netprefix}cl.pw
    sudo chmod 600 /dev/shm/.${netprefix}cl.pw
    sudo chown bitcoin:bitcoin /dev/shm/.${netprefix}cl.pw
  fi
  # setting value in raspiblitz config
  sudo sed -i \
   "s/^${netprefix}clAutoUnlock=.*/${netprefix}clAutoUnlock=off/g" \
   /mnt/hdd/raspiblitz.conf
  echo "# Autounlock is off for C-lightning $CHAIN"

elif [ "$1" = "change-password" ]; then
  decryptHSMsecret || exit 1
  walletPassword=$3
  if ! encryptHSMsecret "$walletPassword"; then
    echo "# Warning: the hsm_secret is left unencrypted."
    echo "# To fix run:"
    echo "/home/admin/config.scripts/cl.hsmtool encrypt $2"
    exit 1
  fi
  exit 0

elif [ "$1" = "check" ]; then
  # TODO
  # dumponchaindescriptors <path/to/hsm_secret> [network]
  # get current descriptors
  sudo -u bitcoin /home/bitcoin/lightning/tools/hsmtool dumponchaindescriptors \
   /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret $CLNETWORK
  # get seed to compare


else
  echo "# Unknown option - exiting script"
  exit 1
fi

# set the lightningd service file after all choices unless exited before
/home/admin/config.scripts/cl.install-service.sh $CHAIN
