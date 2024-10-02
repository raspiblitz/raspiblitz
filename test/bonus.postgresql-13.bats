#!/usr/bin/env bats

@test "Create PostgreSQL 13 cluster" {
  postgres_datadir="/var/lib/postgresql" # default data dir
  postgres_confdir="/etc/postgresql"     # default conf dir
  if [ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]; then
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
    sudo apt-get update
  fi
  sudo apt-get install -y postgresql-13

  # avoid failure in github action
  sudo pg_createcluster 13 main || true
  sudo pg_ctlcluster 13 main start

  sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
}

@test "Create test database in 13" {
  sudo -u postgres psql -c "CREATE DATABASE testdb13 TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser13 WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb13 TO testuser13;"
  run pg_lsclusters
  [ "$status" -eq 0 ]
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb13"
  [ "$?" -eq 0 ]
  echo "$output" | grep -q "testuser13"
  [ "$?" -eq 0 ]
}

@test "Switch cluster 13 off and move" {
  sudo apt-get remove -y postgresql-13
  sudo apt-get remove -y postgresql-15
  sudo apt-get remove -y postgresql
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  sudo mkdir -p /mnt/hdd/app-data/
  sudo mv /var/lib/postgresql /mnt/hdd/app-data/
  run sudo ls /mnt/hdd/app-data/postgresql/13
  [ "$status" -eq 0 ]
  sudo mv /mnt/hdd/app-data/postgresql /mnt/hdd/app-data/postgresql.bak
  run sudo pg_dropcluster 13 main --stop
  [ "$status" -eq 0 ]
}

@test "Recover cluster from 13 without config" {
  sudo mv /mnt/hdd/app-data/postgresql.bak /mnt/hdd/app-data/postgresql
  sudo rm -rf /etc/postgresql
  sudo rm -rf /mnt/hdd/app-data/postgresql-conf.bak
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  run pg_lsclusters
  # check that no 13 cluster is present
  [ $(echo "$output" | grep -c "13  main") -eq 0 ]
  # check that pg 15 cluster is present
  echo "$output" | grep -q "15  main"
  [ "$?" -eq 0 ]
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb13"
  [ "$?" -eq 0 ]
  echo "$output" | grep -q "testuser13"
  [ "$?" -eq 0 ]
}

@test "Create test database (2)" {
  sudo -u postgres psql -c "CREATE DATABASE testdb15 TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser15 WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb15 TO testuser15;"
  run pg_lsclusters
  [ "$status" -eq 0 ]
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb15"
  [ "$?" -eq 0 ]
  echo "$output" | grep -q "testuser15"
  [ "$?" -eq 0 ]
}

@test "Final cleanup" {
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  run pg_lsclusters
  [ "$status" -eq 0 ]
  sudo pg_dropcluster 15 main --stop || true
  sudo pg_dropcluster 13 main --stop || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
  sudo apt-get remove -y postgresql-13
  sudo apt-get remove -y postgresql-15
  sudo apt-get remove -y postgresql
}
