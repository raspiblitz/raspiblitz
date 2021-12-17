#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz SSH tools"
  echo "blitz.ssh.sh renew       --> renew the sshd host certs"
  echo "blitz.ssh.sh clear       --> make sure old sshd host certs are cleared"
  echo "blitz.ssh.sh checkrepair --> check sshd & repair just in case"
  echo "blitz.ssh.sh backup      --> copy ssh keys to backup (if exist)"
  echo "blitz.ssh.sh sessions    --> count open sessions"
  echo "blitz.ssh.sh restore [?backup-root] --> restore ssh keys from backup (if exist)"
  exit 1
fi

DEFAULTBACKUPBASEDIR="/mnt/hdd/ssh"

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='missing sudo'"
  exit 1
fi

###################
# RENEW
###################
if [ "$1" = "renew" ]; then
  echo "# *** $0 renew"
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
  echo "# *** $0 clear"
  sudo rm /etc/ssh/ssh_host_*
  echo "# OK: SSHD keyfiles & possible backups deleted"
  exit 0
fi

###################
# SESSIONS
###################
if [ "$1" = "sessions" ]; then
  echo "# *** $0 sessions"
  sessionsCount=$(ss | grep -c ":ssh")
  echo "ssh_session_count=${sessionsCount}"
  exit 0
fi

###################
# CHECK & REPAIR
###################
if [ "$1" = "checkrepair" ]; then
  echo "# *** $0 checkrepair"
  
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

###################
# BACKUP
###################
if [ "$1" = "backup" ]; then
  echo "# *** $0 backup"
    echo "# backup dir: ${DEFAULTBACKUPBASEDIR}"

    # backup sshd host keys
    sudo rm -r $DEFAULTBACKUPBASEDIR/sshd 2>/dev/null # delete backups if exist
    sudo mkdir $DEFAULTBACKUPBASEDIR/sshd 2>/dev/null # copy to backups if exist
    sudo cp -a /etc/ssh $DEFAULTBACKUPBASEDIR/sshd 2>/dev/null # copy to backups if exist

    # backup root use ssh keys
    sudo rm -r $DEFAULTBACKUPBASEDIR/root_backup 2>/dev/null
    sudo mkdir $DEFAULTBACKUPBASEDIR/root_backup 2>/dev/null
    sudo cp -a /root/.ssh $DEFAULTBACKUPBASEDIR/root_backup 2>/dev/null

    if [ -d "${DEFAULTBACKUPBASEDIR}/sshd" ] && [ -d "${DEFAULTBACKUPBASEDIR}/root_backup" ]; then
      echo "# OK - ssh keys backup done"
    else
      echo "error='ssh keys backup failed - backup location may not exist'"
    fi
  exit 0
fi

###################
# RESTORE
###################
if [ "$1" = "restore" ]; then
  echo "# *** $0 restore"

    # second parameter (optional)
    ALTBACKUPBASEDIR=$2
    if [ "${ALTBACKUPBASEDIR}" != "" ]; then
      DEFAULTBACKUPBASEDIR="${ALTBACKUPBASEDIR}"
    fi

    echo "# backup dir: ${DEFAULTBACKUPBASEDIR}"
    if [ -d "${DEFAULTBACKUPBASEDIR}/sshd" ] && [ -d "${DEFAULTBACKUPBASEDIR}/root_backup" ]; then

      # restore sshd host keys
      sudo rm /etc/ssh/*
      sudo cp -a $DEFAULTBACKUPBASEDIR/sshd/* /etc/ssh/
      sudo chown -R root:root /etc/ssh
      sudo dpkg-reconfigure openssh-server
      sudo systemctl restart sshd

      # restore root use keys
      sudo rm -r /root/.ssh 2>/dev/null
      sudo cp -a $DEFAULTBACKUPBASEDIR/root_backup /root/.ssh 2>/dev/null
      sudo chown -R root:root /root/.ssh 2>/dev/null

      echo "# OK - ssh keys restore done"
    else
      echo "error='ssh keys backup not found'"
    fi
  exit 0
fi

echo "error='unknown parameter'"
exit 1
