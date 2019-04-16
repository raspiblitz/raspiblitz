#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# config script to init/show/transfer ssh pub keys."
 echo "# To init and return pubkey as data:"
 echo "# internet.sshpubkey.sh get"
 echo "# To init and transfer ssh-pub to a authorizedkey of remote server:"
 echo "# internet.sshpubkey.sh transfer [REMOTEUSER]@[REMOTESERVER]"
 echo "err='just informational output'"
 exit 1
fi

# 1. parameter MODE
MODE="$1"

# root as default user 
# its used for all ssh tunnel/back action
USER="root"

# make sure the ssh keys for that user are initialized
sshKeysExist=$(sudo -u ${USER} ls ~/.ssh/id_rsa.pub | grep -c 'id_rsa.pub')
if [ ${sshKeysExist} -eq 0 ]; then
  echo "# generation SSH keys for user ${USER}"
  sudo -u ${USER} mkdir ~/.ssh
  sudo sh -c 'yes y | sudo -u ${USER} ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa  -q -N ""'
fi

if [ "${MODE}" == "get" ]; then

  # get ssh pub key and print
  sshPubKey=$(sudo -u ${USER} cat ~/.ssh/id_rsa.pub)
  echo "user='${USER}'"
  echo "sshPubKey='${sshPubKey}'"

elif [ "${MODE}" == "transfer" ]; then

  sudo sh -c 'yes yes | sudo -u ${USER} ssh-copy-id $2'

else
  echo "err='paremeter not known - run with -help'"
fi


