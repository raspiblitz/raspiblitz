#!/bin/bash

# NOTE: Like the nodeJS frame work docker can be used to run additional apps
# the goal is that you can run a basic RaspiBlitz install without Docker
# but if you want to run certain special apps they can switch Docker on

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install Docker"
 echo "blitz.docker.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "### 1) INSTALL Docker ###"

  # check if Docker is installed
  isInstalled=$(docker -v 2>/dev/null | grep -c "docker version")
  if [ ${isInstalled} -eq 1 ]; then
    echo "# Docker already installed"
    exit 0
  fi

  ## run easy install script provided by Docker
  ## its a copy from https://get.docker.com
  #sudo chmod +x /home/admin/assets/get-docker.sh
  #sudo /home/admin/assets/get-docker.sh

  # https://github.com/rootzoll/raspiblitz/issues/2074#issuecomment-819435910
  # dependencies
  sudo apt-get update
  sudo apt-get install -y \
   apt-transport-https \
   ca-certificates \
   curl \
   gnupg \
   lsb-release

  # add the docker repo
  if ! gpg /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  fi
  echo \
   "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
   $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update

  # install docker
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io

  # add the default user to the docker group
  sudo usermod -aG docker admin

  echo "### 2) INSTALL docker-compose ###"

  # add docker compose
  sudo pip3 install docker-compose
  # add bash completion  https://docs.docker.com/compose/completion/
  sudo curl \
   -L https://raw.githubusercontent.com/docker/compose/1.29.0/contrib/completion/bash/docker-compose \
   -o /etc/bash_completion.d/docker-compose

  echo "### 3) Symlink the working directory to the SSD"
  sudo systemctl stop docker
  sudo systemctl stop docker.socket
  sudo mv /var/lib/docker /mnt/hdd/
  sudo ln -s  /mnt/hdd/docker /var/lib/docker
  sudo systemctl start docker
  sudo systemctl start docker.socket

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set docker "on"
  echo "# Docker install done"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set docker "off"
  echo "*** REMOVING Docker & docker-compose ***"
  sudo pip3 uninstall -y docker-compose
  sudo apt-get purge -y docker-ce docker-ce-cli containerd.io
  echo "# Docker remove done"
  exit 0
fi

echo "error='wrong parameter'"
exit 1