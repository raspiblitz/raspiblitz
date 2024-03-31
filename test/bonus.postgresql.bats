#!/usr/bin/env bats

@test "Start PostgreSQL cluster" {
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
}

@test "Create test database" {
  # run the script
  sudo -u postgres psql -c "CREATE DATABASE testdb TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb TO testuser;"
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  # check if the test database is present
  sudo -u postgres psql -l | grep testdb
  sudo -u postgres psql -l | grep testuser
}

@test "Switch cluster off and move" {
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  PG_VERSION=$(psql -V | awk '{print $3}' | cut -d'.' -f1)
  echo "Detected PostgreSQL version: $PG_VERSION"
  sudo mv /mnt/hdd/app-data/postgresql /mnt/hdd/app-data/postgresql.bak
  sudo mv /mnt/hdd/app-data/postgresql-conf /mnt/hdd/app-data/postgresql-conf.bak
  sudo pg_dropcluster $PG_VERSION main || true
}

@test "Restore pg cluster" {
  sudo mv /mnt/hdd/app-data/postgresql.bak /mnt/hdd/app-data/postgresql
  sudo mv /mnt/hdd/app-data/postgresql-conf.bak /mnt/hdd/app-data/postgresql-conf
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  # check if the test database is present
  sudo -u postgres psql -l | grep testdb
  sudo -u postgres psql -l | grep testuser
}

@test "Switch cluster off and move (2)" {
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  PG_VERSION=$(psql -V | awk '{print $3}' | cut -d'.' -f1)
  echo "Detected PostgreSQL version: $PG_VERSION"
  sudo mv /mnt/hdd/app-data/postgresql /mnt/hdd/app-data/postgresql.bak
  sudo mv /mnt/hdd/app-data/postgresql-conf /mnt/hdd/app-data/postgresql-conf.bak
  sudo pg_dropcluster $PG_VERSION main || true
  sudo pg_dropcluster 13 main || true
}

@test "Restore cluster without config dir" {
  sudo mv /mnt/hdd/app-data/postgresql.bak /mnt/hdd/app-data/postgresql
  sudo rm -rf /etc/postgresql
  sudo rm -rf /mnt/hdd/app-data/postgresql-conf.bak
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh on

  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  # check if the test database is present
  sudo -u postgres psql -l | grep testdb
  sudo -u postgres psql -l | grep testuser
}

@test "Cleanup" {
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  echo "# pg_dropcluster"
  PG_VERSION=$(psql -V | awk '{print $3}' | cut -d'.' -f1)
  echo "Detected PostgreSQL version: $PG_VERSION"
  sudo pg_dropcluster $PG_VERSION main || true
  sudo pg_dropcluster 13 main || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
}

@test "Create PostgreSQL 13 cluster" {
  postgres_datadir="/var/lib/postgresql" # default data dir
  postgres_confdir="/etc/postgresql"     # default conf dir


  # /usr/bin/pg_upgradecluster [OPTIONS] <old version> <cluster name> [<new data directory>]
  if [ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]; then
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
    sudo apt update
  fi
  sudo apt install -y postgresql-13

  # Cleanup existing clusters to avoid "cluster configuration already exists" error
  if sudo pg_lsclusters | grep -q '13 main'; then
    echo "Existing PostgreSQL 13 'main' cluster found, dropping..."
    sudo pg_dropcluster 13 main --stop || true
  fi

  # symlink data dir
  sudo mkdir -p /mnt/hdd/app-data/postgresql
  sudo chown -R postgres:postgres /mnt/hdd/app-data/postgresql # fix ownership
  sudo rm -rf $postgres_datadir                                # not a symlink.. delete it silently
  sudo ln -s /mnt/hdd/app-data/postgresql /var/lib/            # create symlink

  sudo mkdir -p $postgres_datadir/13/main
  sudo chown -R postgres:postgres $postgres_datadir

  sudo pg_createcluster 13 main --start
  # start cluster
  sudo systemctl enable --now postgresql
  sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
}

@test "Create test database in 13" {
  sudo -u postgres psql -c "CREATE DATABASE testdb13 TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser13 WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb13 TO testuser13;"
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  # check if the test database is present
  sudo -u postgres psql -l | grep testdb13
  sudo -u postgres psql -l | grep testuser13
}

@test "Switch cluster 13 off and move" {
  sudo apt remove -y postgresql-13
  ../home.admin/config.scripts/bonus.postgresql.sh off
  echo "# pg_dropcluster"
  PG_VERSION=$(psql -V | awk '{print $3}' | cut -d'.' -f1)
  echo "Detected PostgreSQL version: $PG_VERSION"
  sudo mv /mnt/hdd/app-data/postgresql /mnt/hdd/app-data/postgresql.bak
  sudo pg_dropcluster $PG_VERSION main || true
  sudo pg_dropcluster 13 main || true
}

@test "Recover cluster from 13 without config" {
  sudo mv /mnt/hdd/app-data/postgresql.bak /mnt/hdd/app-data/postgresql
  sudo rm -rf /etc/postgresql
  sudo rm -rf /mnt/hdd/app-data/postgresql-conf.bak
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  # check if the test database is present
  sudo -u postgres psql -l | grep testdb13
  sudo -u postgres psql -l | grep testuser13
}

@test "Create test database (2)" {
  sudo -u postgres psql -c "CREATE DATABASE testdb TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb TO testuser;"
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  # check if the test database is present
  sudo -u postgres psql -l | grep testdb
  sudo -u postgres psql -l | grep testuser
}

@test "Final cleanup" {
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  # check if the script ran successfully
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  echo "# pg_dropcluster"
  PG_VERSION=$(psql -V | awk '{print $3}' | cut -d'.' -f1)
  echo "Detected PostgreSQL version: $PG_VERSION"
  sudo pg_dropcluster $PG_VERSION main || true
  sudo pg_dropcluster 13 main || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
}
