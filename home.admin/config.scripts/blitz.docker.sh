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

  echo
  echo "### 1) INSTALL Docker ###"

  # check if Docker is installed
  if docker -v 2>/dev/null ; then
    echo "# Docker is already installed"
    docker -v
    docker compose version
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
   "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
   $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update

  # install docker
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io

  # add the default user to the docker group
  # https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user
  sudo usermod -aG docker admin

  echo
  echo "### 2) INSTALL docker compose ###"

  # # add docker compose
  # sudo pip3 install docker-compose
  # # add bash completion  https://docs.docker.com/compose/completion/
  # sudo curl \
  #  -L https://raw.githubusercontent.com/docker/compose/1.29.0/contrib/completion/bash/docker-compose \
  #  -o /etc/bash_completion.d/docker-compose

  # https://docs.docker.com/compose/cli-command/#install-on-linux
  DockerComposeVersion=2.0.0
  # DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  # mkdir -p $DOCKER_CONFIG/cli-plugins
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  sudo curl -SL "https://github.com/docker/compose/releases/download/v${DockerComposeVersion}/docker-compose-linux-$(dpkg --print-architecture)" \
   -o /usr/local/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

  # switch docker-compose to docker compose
  # curl -fL https://raw.githubusercontent.com/docker/compose-switch/master/install_on_linux.sh | sudo sh
  COMPOSE_SWITCH_VERSION="v1.0.4"
  COMPOSE_SWITCH_URL="https://github.com/docker/compose-switch/releases/download/${COMPOSE_SWITCH_VERSION}/docker-compose-linux-$(dpkg --print-architecture)"
  if ! docker compose version 2>&1 >/dev/null; then
    echo "Docker Compose V2 is not installed"
    exit 1
  fi
  sudo curl -fL $COMPOSE_SWITCH_URL -o /usr/local/bin/compose-switch
  sudo chmod +x /usr/local/bin/compose-switch
  COMPOSE=$(command -v docker-compose)
  if [ "$COMPOSE" = /usr/local/bin/docker-compose ]; then
    # This is a manual installation of docker-compose
    # so, safe for us to rename binary
    sudo mv /usr/local/bin/docker-compose /usr/local/bin/docker-compose-v1
    COMPOSE=/usr/local/bin/docker-compose-v1
  fi
  ALTERNATIVES="update-alternatives"
  if ! command -v $ALTERNATIVES; then
    ALTERNATIVES=alternatives
  fi
  echo "Configuring docker-compose alternatives"
  if [ -n "$COMPOSE" ]; then
    sudo $ALTERNATIVES --install /usr/local/bin/docker-compose docker-compose $COMPOSE 1
  fi
  sudo $ALTERNATIVES --install /usr/local/bin/docker-compose docker-compose /usr/local/bin/compose-switch 99
  echo "'docker-compose' is now set to run Compose V2"
  echo "use '$ALTERNATIVES --config docker-compose' if you want to switch back to Compose V1"

  echo
  echo "### 3) Symlink the working directory to the SSD"
  sudo systemctl stop docker
  sudo systemctl stop docker.socket

  # keep the docker dir on the OS drive if the disk is ZFS - needs special config
   isZFS=$(zfs list 2>/dev/null | grep -c "/mnt/hdd")
  if [ "${isZFS}" -eq 0 ]; then
    sudo mv -f /var/lib/docker /mnt/hdd/
    sudo ln -s /mnt/hdd/docker /var/lib/docker
  # move to a different partition or configure docker with ZFS
  # https://docs.docker.com/storage/storagedriver/zfs-driver/#configure-docker-with-the-zfs-storage-driver
  #else
  #  sudo mv -f /var/lib/docker /home/admin/
  #  sudo ln -s /home/admin/docker /var/lib/docker
  fi
  sudo systemctl start docker
  sudo systemctl start docker.socket

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set docker "on"
  echo "# Docker install done"
  docker -v
  docker compose version
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set docker "off"
  echo "*** REMOVING Docker & docker-compose ***"
  sudo pip3 uninstall -y docker-compose
  sudo rm /usr/local/lib/docker/cli-plugins/docker-compose
  sudo rm /usr/local/bin/docker-compose-v1
  sudo rm /usr/local/bin/compose-switch
  sudo apt-get purge -y docker-ce docker-ce-cli containerd.io
  echo "# Docker remove done"
  exit 0
fi

echo "error='wrong parameter'"
exit 1
