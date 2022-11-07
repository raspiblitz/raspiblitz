#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install PostgreSQL"
 echo "bonus.postgresql.sh [on|off]"
 echo "bonus.postgresql.sh [backup] [database]"
 echo "bonus.postgresql.sh [restore] [database] [user] [password]"
 exit 1
fi

command=$1
db_name=$2
db_user=$3
db_user_pw=$4

# switch on
if [ "$command" = "1" ] || [ "$command" = "on" ]; then
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
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
  fi

  # check if PostgreSQL was installed
  if psql --version; then
    echo "# Installed PostgreSQL $(psql --version)"
  else
    echo "FAIL - Was not able to install PostgreSQL"
    echo "ABORT - PostgreSQL install"
    exit 1
  fi

  exit 0
fi

# switch off
if [ "$command" = "0" ] || [ "$command" = "off" ]; then
  # setting value in raspiblitz config
  echo "*** REMOVING POSTGRESQL ***"
  sudo apt remove -y postgresql
  sudo systemctl stop postgresql
  echo "OK PostgreSQL removed."
  exit 0
fi

# backup
backup_target="/mnt/backup_manual/$db_name"
backup_file="${db_name}_`date +%d`-`date +%m`-`date +%Y`_`date +%H`-`date +%M`_dump"
if [ ! -d $backup_target ]; then
    sudo mkdir -p $backup_target 1>&2
fi

# https://www.postgresql.org/docs/current/backup-dump.html
if [ "$command" = "backup" ] && [ "$db_name" != "" ]; then
  echo "*** BACKUP POSTGRESQL $db_name ***"
  sudo -u postgres pg_dump $db_name > $backup_target/${backup_file}.sql || exit 1
  # Delete old backups (keep last 3 backups)
  sudo ls -tp $backup_target/*.sql | grep -v '/$' | tail -n +4 | tr '\n' '\0' | xargs -0 rm --
  echo "OK database $db_name backup done."
  exit 0
fi

# restore
if [ "$command" = "restore" ] && [ "$db_name" != "" ] && [ "$db_user" != "" ] && [ "$db_user_pw" != "" ]; then
  echo "*** RESTORE POSTGRESQL $db_name ***"
  # find recent backup
  backup_file=$(ls -t $backup_target/*.sql | head -n1)
  if [ ! -e $backup_file ]; then
    echo "FAIL - Database backup not found in ${backup_target}"
    echo "ABORT - PostgreSQL restore"
    exit 1
  fi

  # clean up
  echo "# Clean up old database"
  sudo -u postgres psql -c "drop database $db_name;" || exit 1
  sudo -u postgres psql -c "drop user $db_user;"

  # create database and user
  echo "# Create fresh database"
  sudo -u postgres psql -c "create database $db_name;"
  sudo -u postgres psql -c "create user $db_user with encrypted password '$db_user_pw';"
  sudo -u postgres psql -c "grant all privileges on database $db_name to $db_user;"

  # restore dump
  echo "# Import SQL Dump"
  sudo mkdir -p $backup_target/logs 1>&2
  sudo -u postgres psql $db_name < ${backup_file} > $backup_target/logs/sql_import.log || exit 1
  echo "$backup_target/sql_import.log written"
  echo "OK database $db_name restored."
  exit 0
fi

echo "FAIL - Unknown Parameter $command"
exit 1
