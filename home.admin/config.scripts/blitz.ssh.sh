#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz SSH tools"
  echo
  echo "## SSHD SERVICE #######"
  echo "blitz.ssh.sh renew       --> renew the sshd host certs"
  echo "blitz.ssh.sh clear       --> make sure old sshd host certs are cleared"
  echo "blitz.ssh.sh checkrepair --> check sshd & repair just in case"
  echo "blitz.ssh.sh backup      --> copy ssh keys to backup (if exist)"
  echo "blitz.ssh.sh sessions    --> count open sessions"
  echo "blitz.ssh.sh restore [?backup-root]"
  echo "                         --> restore ssh keys from backup (if exist)"
  echo 
  echo "## SSH ROOT USER #######"
  echo "blitz.ssh.sh root-get    --> return root user pubkey"
  echo "blitz.ssh.sh root-transfer [REMOTEUSER]@[REMOTESERVER]"
  echo "                         --> transfer ssh-pub to a authorized key of remote server"
  echo
  exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='missing sudo'"
  exit 1
fi

###################
# RENEW
###################
if [ "$1" = "renew" ]; then
  echo "# *** $0 $1"
  sudo systemctl stop sshd
  sudo rm /etc/ssh/ssh_host_*
  sudo ssh-keygen -A
  sudo dpkg-reconfigure openssh-server
  sudo systemctl start sshd
  exit 0
fi

###################
# CLEAR
###################
if [ "$1" = "clear" ]; then
  echo "# *** $0 $1"
  sudo rm /etc/ssh/ssh_host_*
  echo "# OK: SSHD keyfiles & possible backups deleted"
  exit 0
fi

###################
# SESSIONS
###################
if [ "$1" = "sessions" ]; then
  echo "# *** $0 $1"
  sessionsCount=$(ss | grep -c ":ssh")
  echo "ssh_session_count=${sessionsCount}"
  exit 0
fi

###################
# CHECK & REPAIR
###################
if [ "$1" = "checkrepair" ]; then
  echo "# *** $0 $1"
  
  # check if sshd host keys are missing / need generation
  countKeyFiles=$(ls -la /etc/ssh/ssh_host_* 2>/dev/null | grep -c "/etc/ssh/ssh_host")
  echo "# countKeyFiles(${countKeyFiles})"
  if [ ${countKeyFiles} -lt 8 ]; then
  
    echo "# DETECTED: MISSING SSHD KEYFILES --> Generating new ones"
    systemctl stop ssh
    echo "# ssh-keygen1"
    cd /etc/ssh
    ssh-keygen -A
    systemctl start sshd
    sleep 3

    countKeyFiles=$(ls -la /etc/ssh/ssh_host_* 2>/dev/null | grep -c "/etc/ssh/ssh_host")
    echo "# countKeyFiles(${countKeyFiles})"
    if [ ${countKeyFiles} -lt 8 ]; then
      echo "# FAIL: Was not able to generate new sshd host keys"
    else
      echo "# OK: New sshd host keys generated"
    fi
    
  fi

  # check if SSHD service is NOT running & active
  sshdRunning=$(sudo systemctl status sshd | grep -c "active (running)")
  if [ ${sshdRunning} -eq 0 ]; then
    echo "# DETECTED: SSHD NOT RUNNING --> Try reconfigure & kickstart again"
    sudo dpkg-reconfigure openssh-server
    sudo systemctl restart sshd
    sleep 3
  fi

  # check that SSHD service is running & active
  sshdRunning=$(sudo systemctl status sshd | grep -c "active (running)")
  if [ ${sshdRunning} -eq 1 ]; then
    echo "# OK: SSHD RUNNING"
  fi

  exit 0
fi

DEFAULT_BASEDIR="/mnt/hdd/app-data"

###################
# BACKUP
###################
if [ "$1" = "backup" ]; then
    echo "# *** $0 $1"

    # backup sshd host keys
    echo "# backup sshd keys to $DEFAULT_BASEDIR/sshd"
    mkdir -p $DEFAULT_BASEDIR/sshd
    sudo rm -rf $DEFAULT_BASEDIR/sshd/*
    sudo cp -a /etc/ssh $DEFAULT_BASEDIR/sshd

    # backup root use ssh keys
    if [ $(sudo ls /root/.ssh/id_rsa.pub 2>/dev/null | grep -c 'id_rsa.pub') -gt 0 ]; then
      echo "# backup root ssh keys to $DEFAULT_BASEDIR/ssh-root"
      mkdir -p $DEFAULT_BASEDIR/ssh-root
      sudo rm -rf $DEFAULT_BASEDIR/ssh-root/*
      sudo cp -a /root/.ssh $DEFAULT_BASEDIR/ssh-root
    else
      echo "# no /root/.ssh/id_rsa.pub - dont backup"
    fi

  exit 0
fi

###################
# RESTORE
###################
if [ "$1" = "restore" ]; then
    echo "# *** $0 $1"

    # source directory can be changed by second parameter
    ALT_BASEDIR=$2
    if [ "${ALT_BASEDIR}" != "" ]; then
       DEFAULT_BASEDIR="${ALT_BASEDIR}"
    fi

    # restore sshd keys
    if [ $(sudo ls ${DEFAULT_BASEDIR}/sshd/ssh_host_rsa_key 2>/dev/null | grep -c "ssh_host_rsa_key") -gt 0 ]; then
      echo "# restore sshd host keys from: $DEFAULT_BASEDIR/sshd"
      sudo rm -rf /etc/ssh/*
      sudo cp -a $DEFAULT_BASEDIR/sshd/* /etc/ssh/
      sudo chown -R root:root /etc/ssh
      sudo dpkg-reconfigure openssh-server
      sudo systemctl restart sshd
      echo "# OK - sshd keys restore done"
    else
      echo "error='sshd keys backup not found'"
      exit 1
    fi

    # restore root ssh keys
    if [ $(sudo ls ${DEFAULT_BASEDIR}/ssh-root/id_rsa.pub 2>/dev/null | grep -c 'id_rsa.pub') -gt 0 ]; then
      echo "# restore root use keys from: $DEFAULT_BASEDIR/ssh-root"
      sudo rm -rf /root/.ssh
      sudo mkdir /root/.ssh
      sudo cp -a $DEFAULT_BASEDIR/ssh-root/* /root/.ssh
      sudo chown -R root:root /root/.ssh
      echo "# OK - ssh-root keys restore done"
    else
      echo "# INFO - ssh-root keys backup not available"
    fi
    
  exit 0
fi

###################
# ROOT GET
###################
if [ "$1" = "root-get" ]; then
  echo "# *** $0 $1"

  # make sure the ssh keys for that user are initialized
  sshKeysExist=$(sudo ls /root/.ssh/id_rsa.pub | grep -c 'id_rsa.pub')
  if [ ${sshKeysExist} -eq 0 ]; then
    echo "# generation SSH keys for user root"
    sudo mkdir /root/.ssh 2>/dev/null
    sudo sh -c 'yes y | sudo ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa  -q -N ""'
  fi

  # get ssh pub key and print
  sshPubKey=$(sudo cat /root/.ssh/id_rsa.pub)
  echo "user='root'"
  echo "sshPubKey='${sshPubKey}'"
  exit 0
fi

###################
# ROOT TRANSFER
###################
if [ "$1" = "root-transfer" ]; then
  echo "# *** $0 $1"

  # check second parameter
  if [ "$2" == "" ]; then
    echo "# please enter as second parameter: [REMOTEUSER]@[REMOTESERVER]"
    echo "error='missing parameter'"
    exit 1
  fi

  sudo ssh-copy-id $2
  exit 0
fi

echo "error='unknown parameter'"
exit 1
