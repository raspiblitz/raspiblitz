#!/bin/bash

# NOTE: Like the nodeJS frame work docker can be used to run additional apps
# the goal is that you can run a basic RaspiBlitz install without docker
# but if you want to run certain special apps they can switch docker on

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install docker"
 echo "blitz.docker.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "### 1) INSTALL docker ###"

  # check if docker is installed
  isInstalled=$(docker -v 2>/dev/null | grep -c "Docker version")
  if [ ${isInstalled} -eq 1 ]; then
    echo "# docker already installed"
    exit 0
  fi

  # run easy install script provided by docker
  # its a copy from https://get.docker.com
  sudo chmod +x /home/admin/assets/get-docker.sh
  sudo /home/admin/assets/get-docker.sh

  # add admin user
  sudo usermod -aG docker admin

  # start docker service
  sudo systemctl start docker
  sleep 6

  echo "### 2) INSTALL docker-compose ###"

  # add docker compose
  sudo pip3 install docker-compose

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set docker "on"
  echo "# docker install done"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set docker "off"
  echo "*** REMOVING docker & docker-compose ***"
  sudo pip3 uninstall -y docker-compose
  sudo apt-get purge -y docker-ce docker-ce-cli
  echo "# docker remove done"
  exit 0
fi

echo "error='wrong parameter'"
exit 1