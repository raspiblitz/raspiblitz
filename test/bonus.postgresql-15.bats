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

@test "Test PostgreSQL with locale change from en_GB to en_US" {
  # Save current locale settings
  original_locale=$(locale | grep LANG= | cut -d= -f2)
  original_lc_all=$(locale | grep LC_ALL= | cut -d= -f2 || echo "")

  # Step 1: Set up system with en_GB locale
  echo "# Setting up en_GB locale"
  sudo sed -i '/^#en_GB.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo sed -i '/^# en_GB.UTF-8 UTF-8/s/^# //' /etc/locale.gen
  sudo locale-gen en_GB.UTF-8
  export LANG=en_GB.UTF-8
  export LC_ALL=en_GB.UTF-8

  # Step 2: Install PostgreSQL with en_GB locale
  echo "# Installing PostgreSQL with en_GB locale"
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]

  # Verify PostgreSQL is running
  run pg_lsclusters
  [ "$status" -eq 0 ]

  # Step 3: Create test database and user with en_GB locale
  echo "# Creating test database with en_GB locale"
  sudo -u postgres psql -c "CREATE DATABASE testdb_locale TEMPLATE template0 LC_CTYPE 'en_GB.UTF-8' LC_COLLATE 'en_GB.UTF-8' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser_locale WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb_locale TO testuser_locale;"

  # Insert test data with locale-specific content
  sudo -u postgres psql testdb_locale -c "CREATE TABLE test_data (id SERIAL PRIMARY KEY, name TEXT, amount DECIMAL(10,2));"
  sudo -u postgres psql testdb_locale -c "INSERT INTO test_data (name, amount) VALUES ('Test £100.50', 100.50);"
  sudo -u postgres psql testdb_locale -c "INSERT INTO test_data (name, amount) VALUES ('Test €200.75', 200.75);"

  # Verify database creation and locale
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb_locale"
  [ "$?" -eq 0 ]

  # Check database locale settings
  db_locale=$(sudo -u postgres psql testdb_locale -t -c "SHOW LC_COLLATE;" | xargs)
  echo "# Database locale: $db_locale"
  [[ "$db_locale" == *"en_GB"* ]]

  # Step 4: Create backup of the test database
  echo "# Creating backup of test database"
  sudo mkdir -p /tmp/pg_locale_test
  sudo -u postgres pg_dump testdb_locale > /tmp/pg_locale_test/testdb_backup.sql
  [ -f /tmp/pg_locale_test/testdb_backup.sql ]

  # Step 5: Change system locale to en_US
  echo "# Changing system locale to en_US"
  sudo sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo sed -i '/^# en_US.UTF-8 UTF-8/s/^# //' /etc/locale.gen
  sudo locale-gen en_US.UTF-8
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8

  # Step 6: Stop PostgreSQL and clean up
  echo "# Stopping PostgreSQL for reinstall"
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]

  # Clean up cluster
  sudo pg_dropcluster 15 main --stop || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*

  # Step 7: Reinstall PostgreSQL with en_US locale
  echo "# Reinstalling PostgreSQL with en_US locale"
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]

  # Verify PostgreSQL is running
  run pg_lsclusters
  [ "$status" -eq 0 ]

  # Step 8: Restore the database from backup
  echo "# Restoring database from backup"
  sudo -u postgres psql -c "CREATE DATABASE testdb_locale TEMPLATE template0 LC_CTYPE 'en_US.UTF-8' LC_COLLATE 'en_US.UTF-8' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser_locale WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb_locale TO testuser_locale;"

  # Restore data
  sudo -u postgres psql testdb_locale < /tmp/pg_locale_test/testdb_backup.sql

  # Step 9: Verify data integrity after locale change
  echo "# Verifying data integrity after locale change"
  run sudo -u postgres psql testdb_locale -t -c "SELECT COUNT(*) FROM test_data;"
  echo "$output" | grep -q "2"
  [ "$?" -eq 0 ]

  # Verify specific data
  run sudo -u postgres psql testdb_locale -t -c "SELECT name FROM test_data WHERE amount = 100.50;"
  echo "$output" | grep -q "Test £100.50"
  [ "$?" -eq 0 ]

  # Check new database locale settings
  new_db_locale=$(sudo -u postgres psql testdb_locale -t -c "SHOW LC_COLLATE;" | xargs)
  echo "# New database locale: $new_db_locale"
  [[ "$new_db_locale" == *"en_US"* ]]

  # Step 10: Test database operations work correctly
  echo "# Testing database operations"
  sudo -u postgres psql testdb_locale -c "INSERT INTO test_data (name, amount) VALUES ('Test \$300.25', 300.25);"
  run sudo -u postgres psql testdb_locale -t -c "SELECT COUNT(*) FROM test_data;"
  echo "$output" | grep -q "3"
  [ "$?" -eq 0 ]

  # Cleanup test files
  sudo rm -rf /tmp/pg_locale_test

  # Restore original locale if it was set
  if [ -n "$original_locale" ]; then
    export LANG="$original_locale"
  fi
  if [ -n "$original_lc_all" ]; then
    export LC_ALL="$original_lc_all"
  fi

  echo "# Locale change test completed successfully"
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
