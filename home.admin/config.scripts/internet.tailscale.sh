#!/bin/sh

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script to install Tailscale"
  echo "# internet.tailscale.sh state"
  echo "# internet.tailscale.sh on"
  echo "# internet.tailscale.sh menu"
  echo "# internet.tailscale.sh off <--delete-data|--keep-data>"
  exit 0
fi

if [ "$1" = "on" ]; then

  # check if tailscale is already installed
  if [ "$(systemctl is-active tailscaled)" = "active" ]; then
    echo "# Tailscale is already running"
    exit 0
  fi

  # get debian release codename
  . /etc/os-release
  if [ -z "$VERSION_CODENAME" ]; then
    echo "error='missing VERSION_CODENAME in /etc/os-release'"
    exit 1
  fi

  echo "# Installing Tailscale"

  # backup tailscale library if exists
  if [ -d /var/lib/tailscale ]; then
    if [ ! -d /mnt/hdd/app-data/tailscale ]; then
      echo "# Moving the Tailscale data to disk"
      sudo mv /var/lib/tailscale /mnt/hdd/app-data/tailscale
    else
      echo "# Backing up /var/lib/tailscale to /var/lib/tailscale.backup"
      sudo mv /var/lib/tailscale /var/lib/tailscale.backup
    fi
  fi

  # add tailscale repository if not already added
  if [ ! -f /etc/apt/sources.list.d/tailscale.list ]; then
    echo "# Adding Tailscale repository"
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/$VERSION_CODENAME.noarmor.gpg" -o /tmp/tailscale-archive-keyring.gpg && sudo mv /tmp/tailscale-archive-keyring.gpg /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/$VERSION_CODENAME.tailscale-keyring.list" -o /tmp/tailscale-keyring.list && sudo mv /tmp/tailscale-keyring.list /etc/apt/sources.list.d/tailscale.list
  else
    echo "# Tailscale repository already added"
  fi

  # install tailscale
  sudo apt-get update
  sudo apt-get install -y tailscale tailscale-archive-keyring

  # move tailscale state to HDD
  sudo systemctl stop tailscaled
  sudo systemctl disable tailscaled
  sudo rm -rf /var/lib/tailscale
  sudo mkdir -p /mnt/hdd/app-data/tailscale
  sudo cp /lib/systemd/system/tailscaled.service /etc/systemd/system/
  sudo sed -i 's|--state=/var/lib/tailscale/tailscaled.state|--state=/mnt/hdd/app-data/tailscale/tailscaled.state|' /etc/systemd/system/tailscaled.service
  sudo systemctl enable tailscaled
  sudo systemctl start tailscaled

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set tailscale on

  echo "# Grace period for Tailscale to start ... 10 seconds"
  sleep 10

  echo
  echo "##############################"
  echo "# Installation complete!"
  echo "# To config or see state of tailscale call:"
  echo "# /home/admin/config.scripts/internet.tailscale.sh menu"

  exit 0
fi

if [ "$1" = "off" ]; then

  echo "# Removing Tailscale"
  sudo systemctl disable --now tailscaled
  sudo apt purge -y tailscale

  # get delete data status - either by parameter or if not set by user dialog
  deleteData=""
  if [ "$2" = "--delete-data" ]; then
    deleteData="1"
  fi
  if [ "$2" = "--keep-data" ]; then
    deleteData="0"
  fi
  if [ -z "$deleteData" ]; then
    if (whiptail --title "Delete Data?" --yes-button "Keep Data" --no-button "Delete Data" --yesno "Do you want to delete all data related to Tailscale?" 0 0); then
      deleteData="0"
    else
      deleteData="1"
    fi
  fi

  # execute on delete data
  if [ "$deleteData" = "1" ]; then
    echo "# Removing Tailscale data"
    sudo rm -rf /mnt/hdd/app-data/tailscale
  else
    echo "# Tailscale data is preserved on the disk (if exist)"
  fi

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set tailscale off

  echo "# Removed Tailscale"
  exit 0
fi

# gather status if tailscale
installed=0
backend_state=""
status=$(sudo tailscale status --json 2>/dev/null)
if [ -n "$status" ]; then
  installed=1
  backend_state=$(echo "$status" | jq -r '.BackendState' 2>/dev/null)
  login_name=$(echo "$status" | jq -r '.User[] | .LoginName' 2>/dev/null)
fi

if [ "$1" = "status" ]; then

  echo "# Tailscale Status"
  echo "installed=${installed}"
  echo "state=${backend_state}"

  # get login URL if needed
  login_url=""
  if [ "$backend_state" = "NeedsLogin" ]; then
    login_url=$(sudo timeout 3s tailscale login --nickname RaspiBlitz 2>&1 | grep https:// | awk '{$1=$1; print}')
  fi
  echo "login_url=${login_url}"

  exit 0
fi

if [ "$1" = "menu" ]; then

  # exit if tailscale is not installed
  if [ ${installed} -eq 0 ]; then
    echo "# Tailscale is not installed"
    exit 0
  fi

  # if tailscale needs login
  if [ "$backend_state" = "NeedsLogin" ]; then
    echo "# Tailscale needs login"

    # while loop until user selects cancel in whiptail
    while :
    do

      # get tailscale login URL
      login_url=$(sudo timeout 3s sudo tailscale login --nickname RaspiBlitz 2>&1 | grep https:// | awk '{$1=$1; print}')
      if [ -z "$login_url" ]; then
        echo "# Error getting login URL"
        sleep 3
        exit 1
      fi

      # ask user to login
      if (whiptail --title "Tailscale Login Needed" --yes-button "Test Login" --no-button "Cancel Login" --yesno "To connect your RaspiBlitz with Tailscale open the following Url in your browser:\n${login_url}\n\nIf you connected this device to Tailscale successfully, choose 'Test Login'" 0 0); then
        # check if tailscale is now logged in
        status=$(sudo tailscale status --json 2>/dev/null)
        backend_state=$(echo "$status" | jq -r '.BackendState' 2>/dev/null)
        if [ "$backend_state" = "NeedsLogin" ]; then
          echo "# Tailscale still needs login"
        else
          echo "# OK Tailscale is logged in"
          whiptail --msgbox "Tailscale is now connected" 0 0
          break
        fi
      else
        echo "# Cancelled Tailscale login"
        sleep 2
        break
      fi
    done
    exit 0
  else
    echo "# Tailscale state is '${backend_state}'"
    whiptail --msgbox "Tailscale state on RaspiBlitz is '${backend_state}'.\n\nFor details login with '${login_name}' to Tailscale service:\nhttps://login.tailscale.com\n\nOr use the command in the terminal:\nsudo tailscale status" 0 0
  fi
  exit 0
fi
