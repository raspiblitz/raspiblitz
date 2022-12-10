#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install PostgreSQL"
 echo "bonus.postgresql.sh [on|off]"
 exit 1
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # https://github.com/rootzoll/raspiblitz/issues/3218
  echo "# Install PostgreSQL"

  sudo apt install -y postgresql
  postgres_datadir="/var/lib/postgresql" # default data dir

  # sudo -u postgres psql -c "show data_directory"
  #  /var/lib/postgresql/13/main
  if [ ! -d $postgres_datadir ]; then
    echo "# Create PostgreSQL data"
    sudo mkdir -p $postgres_datadir/13/main
    sudo chown -R postgres:postgres $postgres_datadir
    # sudo pg_dropcluster 13 main
    sudo pg_createcluster 13 main --start
  fi

  fix_postgres=0
  if [ -L $postgres_datadir ] ; then
     if [ -e $postgres_datadir ] ; then
        echo "# Good link in $postgres_datadir"
     else
        echo "# Broken link in $postgres_datadir"
        fix_postgres=1
     fi
  elif [ -e $postgres_datadir ] ; then
     echo "# Not a link in $postgres_datadir"
     fix_postgres=1
  else
     echo "# Missing Link in $postgres_datadir"
     fix_postgres=1
  fi

  if [ fix_postgres = 1 ] || [ ! -d /mnt/hdd/app-data/postgresql ]; then
    echo "# Move the PostgreSQL data to /mnt/hdd/app-data/postgresql"
    sudo systemctl stop postgresql 2>/dev/null
    sudo rsync -av $postgres_datadir /mnt/hdd/app-data
    sudo mv $postgres_datadir /var/lib/postgresql.bak
    sudo rm -rf $postgres_datadir # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/
  fi
  sudo systemctl enable postgresql
  sudo systemctl start postgresql

  # check if PostgreSQL was installed
  if psql --version; then
    # wait for the postgres server to start
    count=0
    count_max=30
    while ! nc -zv 127.0.0.1 5432 2>/dev/null;
    do
      count=`expr $count + 1`
      echo "sleep $count/$count_max"
      sleep 1
      if [ $count = $count_max ]; then
        sudo systemctl status postgresql
        echo "FAIL - Was not able to start PostgreSQL service"
        exit 1
      fi
    done
    echo "OK PostgreSQL installed"
  else
    echo "FAIL - Was not able to install PostgreSQL"
    echo "ABORT - PostgreSQL install"
    exit 1
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  echo "*** REMOVING POSTGRESQL ***"
  sudo apt remove -y postgresql
  sudo systemctl stop postgresql 2>/dev/null
  sudo systemctl disable postgresql
  echo "OK PostgreSQL removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
