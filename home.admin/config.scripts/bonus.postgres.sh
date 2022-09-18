#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to install postgres"
 echo "bonus.postgres.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # check if postgres was installed
  postgresInstalled=$(psql --version 2>/dev/null | grep -c "PostgreSQL")
  if ! [ ${postgresInstalled} -eq 0 ]; then
    echo "# postgres is already installed"
    exit 0
  fi

  echo "# Install postgres"
  sudo apt install -y postgresql

  echo "# Move the postgres data to /mnt/hdd/app-data/postgresql"
  # sudo -u postgres psql -c "show data_directory"
  #  /var/lib/postgresql/13/main
  if [ ! -d /var/lib/postgresql ]; then
    sudo  mkdir -p /var/lib/postgresql/13/main
    sudo chown -R postgres:postgres /var/lib/postgresql
    # sudo pg_dropcluster 13 main
    sudo pg_createcluster 13 main --start
  fi
  sudo systemctl stop postgresql 2>/dev/null
  sudo rsync -av /var/lib/postgresql /mnt/hdd/app-data
  sudo mv /var/lib/postgresql /var/lib/postgresql.bak
  sudo rm -rf /var/lib/postgresql # not a symlink.. delete it silently
  sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/

  sudo systemctl enable postgresql
  sudo systemctl start postgresql

  # check if nodeJS was installed
  postgresInstalled=$(psql --version | grep -c "PostgreSQL")
  if [ ${postgresInstalled} -eq 0 ]; then
    echo "# FAIL - Was not able to install postgres"
    echo "# ABORT - postgres install"
    exit 1
  fi

  echo "# Installed postgres $(psql --version)"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  if ! (whiptail --title " WARNING! " --yesno "\
Do not uninstall if you have any applications installed that rely on postgres.

Existing data in postgres may be lost if a later version of postgres is installed later." 13 42 \
--no-button "Cancel" --yes-button "Continue" --defaultno); then
    echo "Cancelled uninstalling postgres."
  fi

  echo "*** REMOVING postgres ***"
  sudo apt remove -y postgresql-common postgresql-client-common
  echo "OK postgres removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
