#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# config script to init/show/transfer ssh pub keys."
 echo "# -> return pubkey (and will init if needed):"
 echo "# internet.sshpubkey.sh get"
 echo "# -> transfer ssh-pub to a authorized key of remote server:"
 echo "# internet.sshpubkey.sh transfer [REMOTEUSER]@[REMOTESERVER]"
 echo "err='just informational output'"
 exit 1
fi

# 1. parameter MODE
MODE="$1"

# root as default user
# its used for all ssh tunnel/back action

# make sure the ssh keys for that user are initialized
sshKeysExist=$(sudo ls /root/.ssh/id_rsa.pub | grep -c 'id_rsa.pub')
if [ ${sshKeysExist} -eq 0 ]; then
  echo "# generation SSH keys for user root"
  sudo mkdir /root/.ssh 2>/dev/null
  sudo sh -c 'yes y | sudo ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa  -q -N ""'
fi

if [ "${MODE}" == "get" ]; then

  # get ssh pub key and print
  sshPubKey=$(sudo cat /root/.ssh/id_rsa.pub)
  echo "user='root'"
  echo "sshPubKey='${sshPubKey}'"

elif [ "${MODE}" == "transfer" ]; then

  sudo ssh-copy-id $2

else
  echo "err='parameter not known - run with -help'"
fi
