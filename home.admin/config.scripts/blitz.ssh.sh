#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "RaspiBlitz SSH tools"
  echo "blitz.ssh.sh renew       --> renew the sshd host certs"
  echo "blitz.ssh.sh clear       --> make sure old sshd host certs are cleared"
  echo "blitz.ssh.sh checkrepair --> check sshd & repair just in case"
  echo "blitz.ssh.sh backup      --> copy ssh keys to backup (if exist)"
  echo "blitz.ssh.sh restore     --> restore ssh keys from backup (if exist)"
  exit 1
fi

DEFAULTBACKUPBASEDIR="/mnt/hdd" # compiles to /mnt/hdd/ssh

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='missing sudo'"
  exit 1
fi

###################
# RENEW
###################
if [ "$1" = "renew" ]; then
  echo "# *** blitz.ssh.sh renew"
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
  echo "# *** blitz.ssh.sh clear"
  sudo rm /etc/ssh/ssh_host_*
  echo "# OK: SSHD keyfiles & possible backups deleted"
  exit 0
fi

###################
# CHECK & REPAIR
###################
if [ "$1" = "checkrepair" ]; then
  echo "# *** blitz.ssh.sh checkrepair"

  # check if sshd host keys are missing / need generation
  countKeyFiles=$(sudo ls -la /etc/ssh/ssh_host_* 2>/dev/null | grep -c "/etc/ssh/ssh_host")
  echo "# countKeyFiles(${countKeyFiles})"
  if [ ${countKeyFiles} -lt 8 ]; then
  
    echo "# DETECTED: MISSING SSHD KEYFILES --> Generating new ones"
    sudo ls -la /etc/ssh
    sudo systemctl stop sshd
    sudo ssh-keygen -A
    sudo dpkg-reconfigure openssh-server
    sudo systemctl start sshd
    sleep 3

    sudo ls -la /etc/ssh
    countKeyFiles=$(sudo ls -la /etc/ssh/ssh_host_* 2>/dev/null | grep -c "/etc/ssh/ssh_host")
    echo "# countKeyFiles(${countKeyFiles})"
    if [ ${countKeyFiles} -lt 8 ]; then
      echo "# FAIL: Was not able to generate new sshd host keys"
    else
      echo "# OK: New sshd host leys generated"
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
  echo "# *** blitz.ssh.sh backup"
    echo "# backup dir: ${DEFAULTBACKUPBASEDIR}/ssh"

    # backup sshd host keys
    sudo rm -r $DEFAULTBACKUPBASEDIR/ssh 2>/dev/null # delete backups if exist
    sudo cp -r /etc/ssh $DEFAULTBACKUPBASEDIR/ssh 2>/dev/null # copy to backups if exist

    # backup root use ssh keys
    sudo rm -r $DEFAULTBACKUPBASEDIR/ssh/root_backup 2>/dev/null
    sudo cp -r /root/.ssh $DEFAULTBACKUPBASEDIR/ssh/root_backup 2>/dev/null

    if [ -d "${DEFAULTBACKUPBASEDIR}/ssh" ]; then
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
  echo "# *** blitz.ssh.sh restore"
    echo "# backup dir: ${DEFAULTBACKUPBASEDIR}/ssh"
    if [ -d "${DEFAULTBACKUPBASEDIR}/ssh" ]; then

      # restore sshd host keys
      sudo rm /etc/ssh/*
      sudo cp -r $DEFAULTBACKUPBASEDIR/ssh/* /etc/ssh/
      sudo chown -R root:root /etc/ssh
      sudo dpkg-reconfigure openssh-server
      sudo systemctl restart sshd

      # restore root use keys
      sudo rm -r /root/.ssh 2>/dev/null
      sudo cp -r $DEFAULTBACKUPBASEDIR/ssh/root_backup /root/.ssh 2>/dev/null
      sudo chown -R root:root /root/.ssh 2>/dev/null

      echo "# OK - ssh keys restore done"
    else
      echo "error='ssh keys backup not found'"
    fi
  exit 0
fi

echo "error='unknown parameter'"
exit 1
