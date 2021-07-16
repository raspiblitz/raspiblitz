#!/bin/bash

# keeps the password in memory between restarts: /dev/shm/.${netprefix}cln.pw
# see the reasoning: https://github.com/ElementsProject/lightning#hd-wallet-encryption
# does not store the password on disk unless auto-unlock is enabled
# autounlock password is in /root/.${netprefix}cln.pw

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]||\
  ! echo "$@" | grep -Eq "new|seed|unlock|lock|encrypt|decrypt|autounlock-on|autounlock-off|change-password" ;then
  echo
  echo "# create new wallet or import seed"
  echo "# unlock/lock, encrypt, decrypt, set autounlock or change password for the hsm_secret"
  echo
  echo "# usage:"
  echo "# Create new wallet"
  echo "# cln.hsmtool.sh [new] [mainnet|testnet|signet] [?seedPassword]"  
  echo "# cln.hsmtool.sh [new-force] [mainnet|testnet|signet] [?seedPassword]"  
  echo "# There will be no seedPassword(passphrase) used by default"
  echo "# new-force will delete any old wallet and will work without dialog"
  echo
  echo "# cln.hsmtool.sh [seed] [mainnet|testnet|signet] [\"space-separated-seed-words\"] [?seedPassword]"  
  echo "# cln.hsmtool.sh [seed-force] [mainnet|testnet|signet] [\"space-separated-seed-words\"] [?seedPassword]"  
  echo "# the new hsm_secret will be not encrypted if no NewPassword is given"
  echo "# seed-force will delete any old wallet and will work without dialog"
  echo
  echo "# cln.hsmtool.sh [unlock|lock] <mainnet|testnet|signet>"
  echo "# cln.hsmtool.sh [encrypt|decrypt] <mainnet|testnet|signet>"
  echo "# cln.hsmtool.sh [autounlock-on|autounlock-off] <mainnet|testnet|signet>"
  echo
  echo "# cln.hsmtool.sh [change-password] <mainnet|testnet|signet> <NewPassword>"
  echo
  exit 1
fi

source /mnt/hdd/raspiblitz.conf
source <(/home/admin/config.scripts/network.aliases.sh getvars cln $2)
hsmSecretPath="/home/bitcoin/.lightning/${CLNETWORK}/hsm_secret"

# password file is on the disk if encrypted and auto-unlock is enabled
passwordFile=/dev/shm/.${netprefix}cln.pw
if grep -Eq "${netprefix}clnEncryptedHSM=on" /mnt/hdd/raspiblitz.conf;then
  if grep -Eq "${netprefix}clnAutoUnlock=on" /mnt/hdd/raspiblitz.conf;then
    passwordFile=/root/${netprefix}cln.pw
  fi
fi

# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}clnEncryptedHSM=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}clnEncryptedHSM=off" >> /mnt/hdd/raspiblitz.conf
fi
# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}clnAutoUnlock=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}clnAutoUnlock=off" >> /mnt/hdd/raspiblitz.conf
fi

#############
# Functions #
#############
function passwordToFile() {
  if [ $# -gt 0 ];then
    text="$1"
  else
    text="Type or paste the decryption password for the $CHAIN C-lightning wallet"
  fi
  # write password into a file in memory
  # get password
  data=$(mktemp -p /dev/shm/)
  # trap it
  trap 'rm -f $data' 0 1 2 5 15
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
      sudo tee $passwordFile 1>/dev/null < "$data"
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
  sudo shred -uvz $passwordFile
}

function encryptHSMsecret() {
  walletPassword=$3
  if [ ${#walletPassword} -eq 0 ];then
    # ask for password in dialog if $walletPassword is not given in $3
    sudo /home/admin/config.scripts/blitz.setpassword.sh x \
      "Enter the password to encrypt the C-lightning wallet file (hsm_secret)" \
      "$passwordFile"
    sudo chmod 600 $passwordFile
    walletPassword=$(sudo cat $passwordFile)
  fi  
  (echo $walletPassword; echo $walletPassword) | sudo -u bitcoin \
    /home/bitcoin/lightning/tools/hsmtool encrypt \
    $hsmSecretPath || exit 1
  # setting value in raspiblitz config
  sudo sed -i \
    "s/^${netprefix}clnEncryptedHSM=.*/${netprefix}clnEncryptedHSM=on/g" \
    /mnt/hdd/raspiblitz.conf
  echo "# Encrypted the hsm_secret for C-lightning $CHAIN"
}

function decryptHSMsecret() {
  if [ ! -f $passwordFile ];then
    passwordToFile
  else
    echo "# Getting the password from $passwordFile"
  fi
  sudo cat $passwordFile | sudo -u bitcoin \
    /home/bitcoin/lightning/tools/hsmtool decrypt \
    $hsmSecretPath || exit 1
  shredPasswordFile
  # setting value in raspiblitz config
  sudo sed -i \
    "s/^${netprefix}clnEncryptedHSM=.*/${netprefix}clnEncryptedHSM=off/g" \
    /mnt/hdd/raspiblitz.conf
  echo "# Decrypted the hsm_secret for C-lightning $CHAIN"
}

###########
# Options #
########### 
if [ "$1" = "new" ] || [ "$1" = "new-force" ] || [ "$1" = "seed" ] || [ "$1" = "seed-force" ]; then

  # check/delete existing wallet
  if [ "$1" = "new-force" ] || [ "$1" = "seed-force" ]; then
    echo "# deleting any old wallet ..."
    sudo rm $hsmSecretPath
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
    #TODO seedwords to cln.backup.sh seed-export-gui
    /home/admin/config.scripts/cln.backup.sh seed-export-gui "${seedwords6x4}"
  elif [ "$1" = "new-force" ]; then
    # get 24 words
    source <(python /home/admin/config.scripts/blitz.mnemonic.py generate)
    echo "seedwords='${seedwords}'"
    echo "seedwords6x4='${seedwords6x4}'"
  elif [ "$1" = "seed" ] || [ "$1" = "seed-force" ]; then
    #TODO get seedwords from cln.backup.sh seed-import-gui [$RESULTFILE]
    seedwords="$3"
    seedpassword="$4"
  fi

  # pass to 'hsmtool generatehsm hsm_secret'
  if [ ${#seedpassword} -eq 0 ]; then
    (echo "0"; echo "${seedwords}"; echo) | sudo -u bitcoin /home/bitcoin/lightning/tools/hsmtool "generatehsm" $hsmSecretPath 1>&2
  else
    # pass to 'hsmtool generatehsm hsm_secret' - confirm seedPassword
    (echo "0"; echo "${seedwords}"; echo "$seedpassword"; echo "$seedpassword") | sudo -u bitcoin /home/bitcoin/lightning/tools/hsmtool "generatehsm" $hsmSecretPath 1>&2
  fi
  exit 0
  
elif [ "$1" = "unlock" ]; then
  # getpassword
  if [ $(sudo journalctl -n5 -u ${netprefix}lightningd | \
    grep -c 'encrypted-hsm: Could not read pass from stdin.') -gt 0 ];then
    if [ -f $passwordFile ];then
      echo "# Wrong passwordFile is present"
    else
      echo "# No passwordFile is present"
    fi
    passwordToFile
    sudo systemctl restart ${netprefix}lightningd

  # configure --encrypted-hsm 
  elif [ $(sudo journalctl -n5 -u ${netprefix}lightningd | \
    grep -c 'hsm_secret is encrypted, you need to pass the \--encrypted-hsm startup option.') -gt 0 ];then
    echo "# The hsm_secret encrypted, but unlock is not configured"
    passwordToFile
    # setting value in raspiblitz config
    sudo sed -i \
      "s/^${netprefix}clnEncryptedHSM=.*/${netprefix}clnEncryptedHSM=on/g" \
      /mnt/hdd/raspiblitz.conf
    /home/admin/config.scripts/cln.install-service.sh $CHAIN
  fi

  # check if unlocked
  attempt=0
  while [ $($lightningcli_alias getinfo | grep -c '"id":') -eq 0 ];do
    if [ $(sudo journalctl -n5 -u ${netprefix}lightningd | \
      grep -c 'Wrong password for encrypted hsm_secret.') -gt 0 ];then
      echo "# Wrong password"
      sudo rm -f $passwordFile
      passwordToFile "Wrong password - type the decryption password for the $CHAIN C-lightning wallet"
      sudo systemctl restart ${netprefix}lightningd
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
  walletPassword=$3
  encryptHSMsecret $walletPassword

elif [ "$1" = "decrypt" ]; then
  decryptHSMsecret

elif [ "$1" = "autounlock-on" ]; then
  if grep -Eq "${netprefix}clnEncryptedHSM=on" /mnt/hdd/raspiblitz.conf;then
    echo "# Moving the password from $passwordFile"
    sudo -u bitcoin mv /dev/shm/.${netprefix}cln.pw /root/.${netprefix}cln.pw
  else
    passwordFile=/root/.${netprefix}cln.pw
    passwordToFile
  fi
  # setting value in raspiblitz config
  sudo sed -i \
    "s/^${netprefix}clnAutoUnlock=.*/${netprefix}clnEncryptedHSM=on/g" \
    /mnt/hdd/raspiblitz.conf
  echo "# Autounlock is on for C-lightning $CHAIN"

elif [ "$1" = "autounlock-off" ]; then
  sudo -u bitcoin mv /root/.${netprefix}cln.pw /dev/shm/.${netprefix}cln.pw
  # setting value in raspiblitz config
  sudo sed -i \
    "s/^${netprefix}clnAutoUnlock=.*/${netprefix}clnEncryptedHSM=off/g" \
    /mnt/hdd/raspiblitz.conf
  echo "# Autounlock is off for C-lightning $CHAIN"

elif [ "$1" = "change-password" ]; then
  decryptHSMsecret || exit 1
  walletPassword=$3
  if ! encryptHSMsecret "$walletPassword"; then
    echo "# Warning: the hsm_secret is left unencrypted."
    echo "# To fix run:"
    echo "/home/admin/config.scripts/cln.hsmtool encrypt $2"
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

# set the lightnind service file after all choices
/home/admin/config.scripts/cln.install-service.sh $CHAIN
