#!/usr/bin/env bats

@test "Start PostgreSQL cluster" {
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
}

@test "Create test database" {
  sudo -u postgres psql -c "CREATE DATABASE testdb TEMPLATE template0 LC_CTYPE 'C' LC_COLLATE 'C' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb TO testuser;"
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb"
  [ "$?" -eq 0 ]
  echo "$output" | grep -q "testuser"
  [ "$?" -eq 0 ]
}

@test "Switch cluster off and move" {
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  # check if PostgreSQL cluster is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  sudo mv /mnt/hdd/app-data/postgresql /mnt/hdd/app-data/postgresql.bak
  sudo mv /mnt/hdd/app-data/postgresql-conf /mnt/hdd/app-data/postgresql-conf.bak
  if echo "${output}" | grep "15 main"; then
    run sudo pg_dropcluster 15 main --stop
    [ "$status" -eq 0 ]
  fi
}

@test "Restore pg cluster" {
  sudo mv /mnt/hdd/app-data/postgresql.bak /mnt/hdd/app-data/postgresql
  sudo mv /mnt/hdd/app-data/postgresql-conf.bak /mnt/hdd/app-data/postgresql-conf
  # run the script
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  # check the database
  run pg_lsclusters
  [ "$status" -eq 0 ]
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb"
  [ "$?" -eq 0 ]
  echo "$output" | grep -q "testuser"
  [ "$?" -eq 0 ]
}

@test "Switch cluster off and move (2)" {
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  run pg_lsclusters
  [ "$status" -eq 0 ]
  sudo mv /mnt/hdd/app-data/postgresql /mnt/hdd/app-data/postgresql.bak
  sudo mv /mnt/hdd/app-data/postgresql-conf /mnt/hdd/app-data/postgresql-conf.bak
  if echo "${output}" | grep "15 main"; then
    run sudo pg_dropcluster 15 main --stop
    [ "$status" -eq 0 ]
  fi

}

@test "Restore cluster without config dir" {
  sudo mv /mnt/hdd/app-data/postgresql.bak /mnt/hdd/app-data/postgresql
  sudo rm -rf /etc/postgresql
  sudo rm -rf /mnt/hdd/app-data/postgresql-conf.bak
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  run pg_lsclusters
  [ "$status" -eq 0 ]
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb"
  [ "$?" -eq 0 ]
  echo "$output" | grep -q "testuser"
  [ "$?" -eq 0 ]
}

@test "Cleanup" {
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  run pg_lsclusters
  [ "$status" -eq 0 ]
  sudo pg_dropcluster 15 main --stop || true
  sudo pg_dropcluster 13 main --stop || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
}
