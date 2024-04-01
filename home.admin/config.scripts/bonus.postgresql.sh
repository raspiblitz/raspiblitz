#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to install PostgreSQL"
  echo "bonus.postgresql.sh [on|off]"
  echo "bonus.postgresql.sh [backup] [database]"
  echo "bonus.postgresql.sh [restore] [database] [user] [password]"
  echo "bonus.postgresql.sh [info]"
  exit 1
fi

command=$1
db_name=$2
db_user=$3
db_user_pw=$4
db_backupfile=$5

# switch on
if [ "$command" = "1" ] || [ "$command" = "on" ]; then
  echo "# Install PostgreSQL"
  sudo apt install -y postgresql

  PG_VERSION=$(psql -V | awk '{print $3}' | cut -d'.' -f1)
  echo "Detected PostgreSQL version: $PG_VERSION"

  postgres_datadir="/var/lib/postgresql" # default data dir
  postgres_confdir="/etc/postgresql"     # default conf dir

  sudo systemctl stop postgresql
  sudo systemctl stop postgresql@$PG_VERSION-main

  if [ ! -d /mnt/hdd/app-data/postgresql ]; then
    # there is no old data

    # symlink conf dir
    sudo mkdir -p /mnt/hdd/app-data/postgresql-conf/postgresql
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf # fix ownership
    sudo mv $postgres_confdir /etc/postgresql.bak                     # backup new empty dir
    sudo rm -rf $postgres_confdir                                     # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/     # create symlink

    # symlink data dir
    sudo mkdir -p /mnt/hdd/app-data/postgresql
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql # fix ownership
    sudo mv $postgres_datadir /var/lib/postgresql.bak            # backup new empty dir
    sudo rm -rf $postgres_datadir                                # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/            # create symlink

    echo "# Create PostgreSQL data"
    sudo mkdir -p $postgres_datadir/$PG_VERSION/main
    sudo chown -R postgres:postgres $postgres_datadir

    echo "# Create cluster"
    sudo pg_createcluster $PG_VERSION main --start

  elif [ -d /mnt/hdd/app-data/postgresql/$PG_VERSION/main ]; then
    if [ -d /mnt/hdd/app-data/postgresql-conf ]; then
      # symlink conf dir
      sudo mkdir -p /mnt/hdd/app-data/postgresql-conf/postgresql
      sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf # fix ownership
      sudo mv $postgres_confdir /etc/postgresql.bak                     # backup new empty dir
      sudo rm -rf $postgres_confdir                                     # not a symlink.. delete it silently
      sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/     # create symlink
    else
      # generate new cluster and use default config
      echo "# Create PostgreSQL data"
      sudo mkdir -p $postgres_datadir/$PG_VERSION/main
      sudo chown -R postgres:postgres $postgres_datadir
      sudo pg_createcluster $PG_VERSION main --start
      echo "Setting default password for postgres user"
      # start cluster temporarily
      sudo systemctl start postgresql
      sudo systemctl start@$PG_VERSION-main
      sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
      sudo systemctl stop postgresql
      sudo systemctl stop postgresql@$PG_VERSION-main
      # move and symlink conf dir
      sudo mkdir -p /mnt/hdd/app-data/postgresql-conf
      sudo mv /etc/postgresql /mnt/hdd/app-data/postgresql-conf/
      sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf
      sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/ # create symlink
    fi

    # symlink data dir
    sudo mkdir -p /mnt/hdd/app-data/postgresql
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql # fix ownership
    sudo mv $postgres_datadir /var/lib/postgresql.bak            # backup new empty dir
    sudo rm -rf $postgres_datadir                                # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/            # create symlink

    sudo chown -R postgres:postgres $postgres_datadir
    sudo pg_createcluster $PG_VERSION main --start

  elif [ -d /mnt/hdd/app-data/postgresql/13/main ]; then
    # if there is old data for pg 13 start and upgrade cluster
    # /usr/bin/pg_upgradecluster [OPTIONS] <old version> <cluster name> [<new data directory>]
    if [ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]; then
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
      echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
      sudo apt update
    fi
    sudo apt install -y postgresql-13 || exit 1
    sudo systemctl stop postgresql
    sudo systemctl stop postgresql@13-main
    if [ -d /mnt/hdd/app-data/postgresql-conf ]; then
      # symlink conf dir
      sudo mkdir -p /mnt/hdd/app-data/postgresql-conf/postgresql
      sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf # fix ownership
      sudo mv $postgres_confdir /etc/postgresql.bak                     # backup new empty dir
      sudo rm -rf $postgres_confdir                                     # not a symlink.. delete it silently
      sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/     # create symlink
    else
      # generate new cluster and use default config
      echo "# Create PostgreSQL data"
      sudo mkdir -p $postgres_datadir/13/main
      sudo chown -R postgres:postgres $postgres_datadir
      # start cluster temporarily
      sudo systemctl start postgresql
      if ! pg_lsclusters | grep "13 main"; then
        sudo pg_createcluster 13 main --start
      fi
      echo "Setting default password for postgres user"
      sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
      sudo systemctl stop postgresql
      sudo systemctl stop postgresql@13-main
      # move and symlink conf dir
      sudo mkdir -p /mnt/hdd/app-data/postgresql-conf
      sudo mv /etc/postgresql /mnt/hdd/app-data/postgresql-conf/
      sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf
      sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/ # create symlink
      sudo chown -R postgres:postgres $postgres_confdir
    fi

    # symlink data dir
    sudo mkdir -p /mnt/hdd/app-data/postgresql
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql # fix ownership
    sudo mv $postgres_datadir /var/lib/postgresql.bak            # backup new empty dir
    sudo rm -rf $postgres_datadir                                # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/            # create symlink

    sudo chown -R postgres:postgres $postgres_datadir
    sudo systemctl start postgresql
    sudo systemctl start postgresql@13-main
    sudo pg_createcluster 13 main --start

    sudo pg_upgradecluster 13 main $postgres_datadir/$PG_VERSION/main || exit 1
    sudo systemctl disable --now postgresql@13-main
    sudo apt remove -y postgresql-13
  fi

  # start cluster
  sudo systemctl enable --now postgresql

  # check if PostgreSQL was installed
  if psql --version; then
    echo "# wait for the postgresql server to start"
    count=0
    count_max=30
    while ! nc -zv 127.0.0.1 5432 2>/dev/null; do
      count=$((count + 1))
      echo "sleep $count/$count_max"
      sleep 1
      if [ $count = $count_max ]; then
        sudo systemctl status postgresql
        echo "FAIL - Was not able to start PostgreSQL service"
        sudo systemctl status postgresql@$PG_VERSION-main.service
        exit 1
      fi
    done
    echo "Setting default password for postgres user"
    sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
    echo "OK PostgreSQL installed"
  else
    echo "FAIL - Was not able to install PostgreSQL"
    echo "ABORT - PostgreSQL install"
    exit 1
  fi

  exit 0
fi

# switch off
if [ "$command" = "0" ] || [ "$command" = "off" ]; then
  echo "*** REMOVING POSTGRESQL ***"
  sudo systemctl disable --now postgresql
  sudo systemctl disable --now postgresql@$PG_VERSION-main
  sudo systemctl disable --now postgresql@13-main
  sudo apt remove -y postgresql
  echo "# remove symlink /var/lib/postgresql"
  sudo rm /var/lib/postgresql
  sudo rm /etc/postgresql
  exit 0
fi

# backup
backup_target="/mnt/hdd/app-data/backup/$db_name"
backup_file="${db_name}_$(date +%d)-$(date +%m)-$(date +%Y)_$(date +%H)-$(date +%M)_dump"
if [ ! -d $backup_target ]; then
  sudo mkdir -p $backup_target 1>&2
fi

# https://www.postgresql.org/docs/current/backup-dump.html
if [ "$command" = "backup" ] && [ "$db_name" != "" ]; then
  echo "*** BACKUP POSTGRESQL $db_name ***"
  sudo -u postgres pg_dump $db_name >$backup_target/${backup_file}.sql || exit 1
  # Delete old backups (keep last 3 backups)
  sudo chown -R admin:admin $backup_target
  ls -tp $backup_target/*.sql | grep -v '/$' | tail -n +4 | tr '\n' '\0' | xargs -0 rm -- 2>/dev/null
  echo "OK - backup finished, file saved as $backup_target/${backup_file}.sql"
  exit 0
fi

# restore
if [ "$command" = "restore" ] && [ "$db_name" != "" ] && [ "$db_user" != "" ] && [ "$db_user_pw" != "" ]; then
  echo "*** RESTORE POSTGRESQL $db_name ***"
  # find recent backup
  if [ "$db_backupfile" != "" ]; then
    backup_file=$db_backupfile
  else
    backup_file=$(ls -t $backup_target/*.sql | head -n1)
  fi

  if [ ! -e $backup_file ]; then
    echo "FAIL - sql file to restore not found in ${backup_target}"
    exit 1
  else
    echo "Start restore from backup ${backup_file}"
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
  sudo chown -R postgres:postgres $backup_file
  sudo -u postgres psql $db_name <${backup_file} >$backup_target/logs/sql_import.log || exit 1
  echo "$backup_target/sql_import.log written"
  echo "OK - database $db_name restored from ${backup_file}"
  exit 0
fi

if [ "$command" = "info" ]; then
  check=$(sudo -u postgres psql -c "show data_directory;" | grep data_directory)
  if [ "$check" = "" ]; then
    echo "show data_directory failed, PostgreSQL not installed?!"
    exit 1
  else
    sudo -u postgres psql -c "show data_directory;"
    sudo -u postgres psql -c "SELECT datname FROM pg_database;"
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $command"
exit 1
