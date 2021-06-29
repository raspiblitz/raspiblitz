#!/bin/bash

# keep password in memory: /dev/shm/.${netprefix}cln.pw
# do not store password on disk unless auto-unlock is enabled
# autounlock password is in /root/.${netprefix}cln.pw

# sudo journalctl -n5 -u ${netprefix}lightningd | grep -c \
# error when encrypted hsm not called with --encrypted-hsm in systemd:
# "hsm_secret is encrypted, you need to pass the --encrypted-hsm startup option."

# error when the passwordFile is misisng:
# '--encrypted-hsm: Could not read pass from stdin.'


# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]||\
  ! echo "$@" | grep -Eq "unlock|encrypt|decrypt|autounlock-on|autounlock-off" ;then
  echo
  echo "unlock, encrypt, decrypt or set autounlock for the hsm_secret"
  echo
  echo "usage:"
  echo "cln.hsmtool.sh [unlock] [testnet|mainnet|signet]"
  echo "cln.hsmtool.sh [encrypt|decrypt] [testnet|mainnet|signet]"
  echo "cln.hsmtool.sh [autounlock-on|autounlock-off] [testnet|mainnet|signet]"
  echo
  exit 1
fi

source /mnt/hdd/raspiblitz.conf
source <(/home/admin/config.scripts/network.aliases.sh getvars cln $2)

passwordFile=/dev/shm/.${netprefix}cln.pw
if grep -Eq "${netprefix}clnEncryptedHSM=on" /mnt/hdd/raspiblitz.conf;then
  if grep -Eq "${netprefix}clnAutoUnlock=on" /mnt/hdd/raspiblitz.conf;then
    passwordFile=/root/${netprefix}cln.pw
  fi
fi

function passwordToFile() {
  # write password into a file (to be shredded)
  # get password
  data=$(mktemp -p /dev/shm/)
  # trap it
  trap 'rm -f $data' 0 1 2 5 15
  dialog --clear \
   --backtitle "Enter password" \
   --title "Enter password" \
   --insecure \
   --passwordbox "Type or paste the C-lightning wallet decryption password" 8 52 2> "$data"
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

if [ "$1" = "unlock" ]; then
  if [ $(sudo journalctl -n5 -u ${netprefix}lightningd | \
    grep -c 'encrypted-hsm: Could not read pass from stdin.') -gt 0 ];then
    echo "# No / wrong passwordFile present"
    passwordToFile
    sudo systemctl restart ${netprefix}lightningd
    exit 0
  elif [ $(sudo journalctl -n5 -u ${netprefix}lightningd | \
    grep -c 'hsm_secret is encrypted, you need to pass the \--encrypted-hsm startup option.') -gt 0 ];then
    echo "# The hsm_secret encrypted"
    passwordToFile
    # setting value in raspiblitz config
    sudo sed -i \
      "s/^${netprefix}clnEncryptedHSM=.*/${netprefix}clnEncryptedHSM=on/g" \
      /mnt/hdd/raspiblitz.conf
    # needs the service to be refreshed -> end of script
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

if [ "$1" = "encrypt" ]; then
  sudo /home/admin/config.scripts/blitz.setpassword.sh x \
    "Enter the password to encrypt the C-lightning wallet file (hsm_secret)" \
    "$passwordFile"
  sudo chmod 600 $passwordFile
  sudo chown bitcoin:bitcoin $passwordFile
  (sudo cat $passwordFile;sudo cat $passwordFile) | sudo -u bitcoin \
    /home/bitcoin/lightning/tools/hsmtool encrypt \
    /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret || exit 1
  # setting value in raspiblitz config
  sudo sed -i \
    "s/^${netprefix}clnEncryptedHSM=.*/${netprefix}clnEncryptedHSM=on/g" \
    /mnt/hdd/raspiblitz.conf
  echo "# Encrypted the hsm_secret for C-lightning $CHAIN"

elif [ "$1" = "decrypt" ]; then
  if [ ! -f $passwordFile ];then
    passwordToFile
  else
    echo "# Getting the password from $passwordFile"
  fi
  sudo cat $passwordFile | sudo -u bitcoin \
    /home/bitcoin/lightning/tools/hsmtool decrypt \
    /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret || exit 1
  shredPasswordFile
  # setting value in raspiblitz config
  sudo sed -i \
    "s/^${netprefix}clnEncryptedHSM=.*/${netprefix}clnEncryptedHSM=off/g" \
    /mnt/hdd/raspiblitz.conf
  echo "# Decrypted the hsm_secret for C-lightning $CHAIN"

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
fi

# set the lightnind service file after all choices
/home/admin/config.scripts/cln.install-service.sh $CHAIN
