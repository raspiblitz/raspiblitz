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

PG_VERSION=15
echo "# Using the default PostgreSQL version: $PG_VERSION"

# Function to verify socket-only configuration
function verify_socket_config() {
  echo "# Verifying socket-only configuration"
  
  # Check that TCP is not listening
  if sudo netstat -tlnp 2>/dev/null | grep -q ":5432 "; then
    echo "⚠️  WARNING: PostgreSQL is still listening on TCP port 5432"
    echo "   This may indicate socket configuration was not applied correctly"
  else
    echo "✅ PostgreSQL is not listening on TCP port 5432 (good)"
  fi
  
  # Check that socket exists
  if [ -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
    echo "✅ Unix socket exists at /var/run/postgresql/.s.PGSQL.5432"
  else
    echo "❌ Unix socket not found - PostgreSQL may not be running correctly"
  fi
  
  # Test socket connection
  if sudo -u postgres psql -h /var/run/postgresql -c "SELECT version();" >/dev/null 2>&1; then
    echo "✅ Socket connection test successful"
  else
    echo "❌ Socket connection test failed"
  fi
}

# Function to apply socket configuration to existing cluster
function apply_socket_config() {
  echo "# Applying socket-only configuration"
  
  # Configure postgresql.conf for socket-only access
  # First, uncomment any existing listen_addresses line and set to empty
  sudo sed -i -E "s/^[[:space:]]*#?[[:space:]]*listen_addresses[[:space:]]*=.*/listen_addresses = ''/" /etc/postgresql/$PG_VERSION/main/postgresql.conf
  
  # Ensure unix_socket_directories is set
  sudo sed -i -E "s/^[[:space:]]*#?[[:space:]]*unix_socket_directories[[:space:]]*=.*/unix_socket_directories = '\/var\/run\/postgresql'/" /etc/postgresql/$PG_VERSION/main/postgresql.conf
  
  # Add socket permissions if not present
  if ! sudo grep -q "unix_socket_permissions" /etc/postgresql/$PG_VERSION/main/postgresql.conf; then
    echo "unix_socket_permissions = '0770'" | sudo tee -a /etc/postgresql/$PG_VERSION/main/postgresql.conf
  fi
  if ! sudo grep -q "unix_socket_group" /etc/postgresql/$PG_VERSION/main/postgresql.conf; then
    echo "unix_socket_group = 'postgres'" | sudo tee -a /etc/postgresql/$PG_VERSION/main/postgresql.conf
  fi
  
  # Update pg_hba.conf for socket-only access
  if sudo grep -q "^host" /etc/postgresql/$PG_VERSION/main/pg_hba.conf; then
    sudo cp /etc/postgresql/$PG_VERSION/main/pg_hba.conf /etc/postgresql/$PG_VERSION/main/pg_hba.conf.backup
    sudo sed -i '/^host/s/^/#/' /etc/postgresql/$PG_VERSION/main/pg_hba.conf
  fi
}

# Function to retrieve postgres password (Password B)
function load_postgres_password() {
  # Load password B from bitcoin.conf (standard Bitcoin RPC password)
  if [ -f "/mnt/hdd/app-data/bitcoin/bitcoin.conf" ]; then
    PASSWORDB=$(grep rpcpassword /mnt/hdd/app-data/bitcoin/bitcoin.conf | cut -d'=' -f2 | tr -d ' ')
  fi

  # check if password B was loaded
  if [ -z "$PASSWORDB" ]; then
    echo "FAIL - PASSWORDB not found in bitcoin.conf" >&2
    exit 1
  fi
}

# switch on
if [ "$command" = "1" ] || [ "$command" = "on" ]; then

  # Install PostgreSQL client package first (needed for version check)
  if ! command -v psql &> /dev/null; then
    echo "# Installing PostgreSQL client package"
    if [ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]; then
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
      echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
      sudo apt update
    fi
    sudo apt install -y postgresql-client-$PG_VERSION
  fi

  # check if PostgreSQL server is already installed
  if dpkg -l | grep -q "postgresql-$PG_VERSION" && [ -d "/etc/postgresql/$PG_VERSION" ]; then
    echo "# PostgreSQL $PG_VERSION server is already installed"
    echo "# Applying socket configuration to existing installation"
    apply_socket_config
    echo "# Restarting PostgreSQL to apply socket configuration"
    sudo systemctl restart postgresql
    sudo systemctl restart postgresql@$PG_VERSION-main
  else
    echo "# Install PostgreSQL server"
    if [ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]; then
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
      echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
      sudo apt update
    fi
    sudo apt install -y postgresql-$PG_VERSION
  fi

  # make sure en_GB locale is available for now - see #4893
  echo "# temp fixing locale"
  sudo sed -i '/^#en_GB.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo sed -i '/^# en_GB.UTF-8 UTF-8/s/^# //' /etc/locale.gen
  sudo locale-gen

  postgres_datadir="/var/lib/postgresql" # default data dir
  postgres_confdir="/etc/postgresql"     # default conf dir

  sudo systemctl stop postgresql
  sudo systemctl stop postgresql@$PG_VERSION-main

  if [ ! -d /mnt/hdd/app-data/postgresql ]; then
    echo "# There is no old pg data"
    # symlink conf dir
    sudo mkdir -p /mnt/hdd/app-data/postgresql-conf/postgresql
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf      # fix ownership
    sudo mv $postgres_confdir /etc/postgresql.bak.$(date +'%Y%m%d_%H%M%S') # backup new empty dir
    sudo rm -rf $postgres_confdir                                          # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/          # create symlink

    # symlink data dir
    sudo mkdir -p /mnt/hdd/app-data/postgresql
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql               # fix ownership
    sudo mv $postgres_datadir /var/lib/postgresql.bak.$(date +'%Y%m%d_%H%M%S') # backup new empty dir
    sudo rm -rf $postgres_datadir                                              # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/                          # create symlink

    echo "# Create PostgreSQL $PG_VERSION data"
    sudo mkdir -p $postgres_datadir/$PG_VERSION/main
    sudo chown -R postgres:postgres $postgres_datadir

    echo "# Create cluster"
    if ! sudo pg_lsclusters | grep -q "$PG_VERSION.*main"; then
      sudo pg_createcluster $PG_VERSION main
    else
      echo "# Cluster already exists, skipping creation"
    fi
    
    # Configure socket-only access
    echo "# Configure socket-only access for security"
    apply_socket_config
    
    sudo pg_ctlcluster $PG_VERSION main start

  elif [ -d /mnt/hdd/app-data/postgresql/$PG_VERSION/main ]; then
    echo "# There is old data for $PG_VERSION, restoring ..."
    if [ -d /mnt/hdd/app-data/postgresql-conf ]; then
      # symlink conf dir
      sudo mkdir -p /mnt/hdd/app-data/postgresql-conf/postgresql
      sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf      # fix ownership
      sudo mv $postgres_confdir /etc/postgresql.bak.$(date +'%Y%m%d_%H%M%S') # backup new empty dir
      sudo rm -rf $postgres_confdir                                          # not a symlink.. delete it silently
      sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/          # create symlink
    else
      # generate new cluster and use default config
      echo "# Create $PG_VERSION config"
      sudo mkdir -p $postgres_datadir/$PG_VERSION/main
      sudo chown -R postgres:postgres $postgres_datadir
      if ! sudo pg_lsclusters | grep -q "$PG_VERSION.*main"; then
        sudo pg_createcluster $PG_VERSION main
        sudo pg_ctlcluster $PG_VERSION main start
      fi
      # start cluster temporarily
      sudo systemctl start postgresql
      sudo systemctl start postgresql@$PG_VERSION-main
      echo "Setting default password for postgres user"
      load_postgres_password
      sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$PASSWORDB';"
      sudo systemctl stop postgresql
      sudo systemctl stop postgresql@$PG_VERSION-main
      # move and symlink conf dir
      sudo mkdir -p /mnt/hdd/app-data/postgresql-conf
      sudo mv /etc/postgresql /mnt/hdd/app-data/postgresql-conf/
      sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf
      sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/ # create symlink
      sudo chown -R postgres:postgres $postgres_confdir
    fi

    # symlink data dir
    sudo mkdir -p /mnt/hdd/app-data/postgresql
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql               # fix ownership
    sudo mv $postgres_datadir /var/lib/postgresql.bak.$(date +'%Y%m%d_%H%M%S') # backup new empty dir
    sudo rm -rf $postgres_datadir                                              # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/                          # create symlink

    sudo chown -R postgres:postgres $postgres_datadir
    sudo systemctl start postgresql
    sudo systemctl start postgresql@13-main
    if ! sudo pg_lsclusters | grep -q "$PG_VERSION.*main"; then
      sudo pg_createcluster $PG_VERSION main
      sudo pg_ctlcluster $PG_VERSION main start
    fi

  elif [ -d /mnt/hdd/app-data/postgresql/13/main ]; then
    echo "# There is old data for pg 13, start and upgrade cluster ..."
    sudo apt install -y postgresql-13 || exit 1
    sudo systemctl stop postgresql
    sudo systemctl stop postgresql@13-main
    if [ -d /mnt/hdd/app-data/postgresql-conf ]; then
      # symlink conf dir
      sudo mkdir -p /mnt/hdd/app-data/postgresql-conf/postgresql
      sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql-conf      # fix ownership
      sudo mv $postgres_confdir /etc/postgresql.bak.$(date +'%Y%m%d_%H%M%S') # backup new empty dir
      sudo rm -rf $postgres_confdir                                          # not a symlink.. delete it silently
      sudo ln -s /mnt/hdd/app-data/postgresql-conf/postgresql /etc/          # create symlink
    else
      # generate new cluster and use default config
      echo "# Create pg 13 config"
      sudo mkdir -p $postgres_datadir/13/main
      sudo chown -R postgres:postgres $postgres_datadir
      # start cluster temporarily
      sudo systemctl start postgresql
      if ! sudo pg_lsclusters | grep -q "13.*main"; then
        sudo pg_createcluster 13 main
        sudo pg_ctlcluster 13 main start
      fi
      echo "# Setting default password for postgres user"
      load_postgres_password
      sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$PASSWORDB';"
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
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql               # fix ownership
    sudo mv $postgres_datadir /var/lib/postgresql.bak.$(date +'%Y%m%d_%H%M%S') # backup new empty dir
    sudo rm -rf $postgres_datadir                                              # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/                          # create symlink

    sudo chown -R postgres:postgres $postgres_datadir
    sudo systemctl start postgresql
    sudo systemctl start postgresql@13-main
    if ! sudo pg_lsclusters | grep -q "13.*main"; then
      sudo pg_createcluster 13 main
      sudo pg_ctlcluster 13 main start
    fi

    if [ -d /mnt/hdd/app-data/postgresql/$PG_VERSION ] || pg_lsclusters | grep -q "$PG_VERSION  main"; then
      echo "# backup /mnt/hdd/app-data/postgresql/$PG_VERSION"
      now=$(date +"%Y_%m_%d_%H%M%S")
      sudo mv /mnt/hdd/app-data/postgresql/$PG_VERSION /mnt/hdd/app-data/postgresql/$PG_VERSION-backup-$now
      echo "# Drop empty pg 15 cluster"
      sudo pg_dropcluster $PG_VERSION main
    fi

    echo "# Make sure postgresql-$PG_VERSION is installed"
    sudo apt install -y postgresql-$PG_VERSION
    # /usr/bin/pg_upgradecluster [OPTIONS] <old version> <cluster name> [<new data directory>]
    sudo pg_upgradecluster 13 main $postgres_datadir/$PG_VERSION/main || exit 1
    sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql/$PG_VERSION
    
    # Configure socket-only access for upgraded cluster
    echo "# Configure socket-only access for upgraded cluster"
    apply_socket_config
    
    echo "# backup /mnt/hdd/app-data/postgresql/13"
    now=$(date +"%Y_%m_%d_%H%M%S")
    sudo mv /mnt/hdd/app-data/postgresql/13 /mnt/hdd/app-data/postgresql/13-backup-$now
    sudo pg_dropcluster 13 main
    sudo systemctl disable --now postgresql@13-main
    sudo apt remove -y postgresql-13

    if sudo cat /etc/postgresql/$PG_VERSION/main/postgresql.conf | grep 5433; then
      echo "# Switch port back to 5432"
      sudo sed -i 's/port = 5433/port = 5432/' /etc/postgresql/$PG_VERSION/main/postgresql.conf
      echo "# Restart posgresql.service"
      sudo systemctl restart postgresql
    fi
  fi

  # start cluster
  sudo systemctl enable postgresql
  sudo systemctl start postgresql
  sudo systemctl enable postgresql@$PG_VERSION-main
  sudo systemctl start postgresql@$PG_VERSION-main

  # check if PostgreSQL was installed
  if psql --version; then
    echo "# wait for the postgresql server to start"
    count=0
    count_max=30
    while ! sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" >/dev/null 2>&1; do
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
    load_postgres_password
    sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$PASSWORDB';"
    echo "OK PostgreSQL installed with socket-only access"
    
    # Verify socket-only configuration
    verify_socket_config
    
    exit 0
  else
    echo "FAIL - Was not able to install PostgreSQL"
    echo "ABORT - PostgreSQL install"
    exit 1
  fi
fi

# switch off
if [ "$command" = "0" ] || [ "$command" = "off" ]; then
  echo "*** REMOVING POSTGRESQL ***"
  sudo systemctl disable --now postgresql
  sudo systemctl disable --now postgresql@$PG_VERSION-main
  sudo systemctl disable --now postgresql@13-main
  sudo apt remove -y postgresql
  if dpkg -l | grep -q "postgresql-13"; then
    sudo apt remove -y postgresql-13
  fi
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
