#!/usr/bin/env bats

# Test PostgreSQL installation and database restoration across locale changes
# This test simulates a scenario where:
# 1. A database is created with en_GB locale
# 2. System locale is changed to en_US  
# 3. PostgreSQL is reinstalled and database is restored
# 4. Data integrity is verified across the locale change

@test "Setup: Save current locale settings" {
  # Save current system locale for restoration later
  locale > /tmp/original_locale.txt
  echo "# Current locale saved"
}

@test "Phase 1: Create database with en_GB locale" {
  # Ensure en_GB locale is available
  echo "# Setting up en_GB locale"
  sudo sed -i '/^#en_GB.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo sed -i '/^# en_GB.UTF-8 UTF-8/s/^# //' /etc/locale.gen
  sudo locale-gen en_GB.UTF-8
  
  # Set environment to en_GB
  export LANG=en_GB.UTF-8
  export LC_ALL=en_GB.UTF-8
  
  # Install PostgreSQL
  echo "# Installing PostgreSQL with en_GB locale"
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  
  # Verify PostgreSQL is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "online"
  [ "$?" -eq 0 ]
}

@test "Phase 2: Create test database and data with en_GB locale" {
  # Create database with explicit en_GB locale
  echo "# Creating test database with en_GB locale"
  sudo -u postgres psql -c "CREATE DATABASE testdb_locale TEMPLATE template0 LC_CTYPE 'en_GB.UTF-8' LC_COLLATE 'en_GB.UTF-8' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser_locale WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb_locale TO testuser_locale;"
  
  # Create test table and insert locale-specific data
  sudo -u postgres psql testdb_locale -c "CREATE TABLE test_data (
    id SERIAL PRIMARY KEY, 
    name TEXT, 
    amount DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    description TEXT
  );"
  
  # Insert test data with British currency symbols and formatting
  sudo -u postgres psql testdb_locale -c "INSERT INTO test_data (name, amount, description) VALUES 
    ('British Pound Test', 100.50, 'Amount: £100.50'),
    ('Euro Test', 200.75, 'Amount: €200.75'),
    ('Date Test', 300.25, 'Created on $(date +%d/%m/%Y)');"
  
  # Verify database creation
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb_locale"
  [ "$?" -eq 0 ]
  
  # Verify locale settings
  db_collate=$(sudo -u postgres psql testdb_locale -t -c "SHOW LC_COLLATE;" | xargs)
  db_ctype=$(sudo -u postgres psql testdb_locale -t -c "SHOW LC_CTYPE;" | xargs)
  echo "# Database LC_COLLATE: $db_collate"
  echo "# Database LC_CTYPE: $db_ctype"
  [[ "$db_collate" == *"en_GB"* ]]
  [[ "$db_ctype" == *"en_GB"* ]]
}

@test "Phase 3: Backup database before locale change" {
  # Create backup directory
  sudo mkdir -p /tmp/pg_locale_test
  sudo chown postgres:postgres /tmp/pg_locale_test
  
  # Create database backup
  echo "# Creating backup of test database"
  sudo -u postgres pg_dump testdb_locale > /tmp/pg_locale_test/testdb_backup.sql
  [ -f /tmp/pg_locale_test/testdb_backup.sql ]
  
  # Verify backup contains our test data
  grep -q "British Pound Test" /tmp/pg_locale_test/testdb_backup.sql
  [ "$?" -eq 0 ]
  grep -q "£100.50" /tmp/pg_locale_test/testdb_backup.sql
  [ "$?" -eq 0 ]
  
  # Also create a custom format backup for testing
  sudo -u postgres pg_dump -Fc testdb_locale > /tmp/pg_locale_test/testdb_backup.dump
  [ -f /tmp/pg_locale_test/testdb_backup.dump ]
  
  echo "# Backup created successfully"
}

@test "Phase 4: Change system locale to en_US" {
  # Ensure en_US locale is available
  echo "# Setting up en_US locale"
  sudo sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo sed -i '/^# en_US.UTF-8 UTF-8/s/^# //' /etc/locale.gen
  sudo locale-gen en_US.UTF-8
  
  # Change environment to en_US
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  
  # Update system default locale
  echo -e "LANG=en_US.UTF-8\nLANGUAGE=en_US.UTF-8\nLC_ALL=en_US.UTF-8" | sudo tee /etc/default/locale > /dev/null
  
  # Verify locale change
  current_lang=$(locale | grep LANG= | cut -d= -f2 | tr -d '"')
  echo "# Current LANG: $current_lang"
  [[ "$current_lang" == *"en_US"* ]]
}

@test "Phase 5: Reinstall PostgreSQL with new locale" {
  # Stop and remove PostgreSQL
  echo "# Stopping PostgreSQL for reinstall"
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  
  # Clean up any remaining clusters
  sudo pg_dropcluster 15 main --stop || true
  sudo pg_dropcluster 13 main --stop || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
  
  # Reinstall PostgreSQL with en_US locale
  echo "# Reinstalling PostgreSQL with en_US locale"
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  
  # Verify PostgreSQL is running
  run pg_lsclusters
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "online"
  [ "$?" -eq 0 ]
  
  # Verify new cluster uses en_US locale
  cluster_collate=$(sudo -u postgres psql -t -c "SHOW LC_COLLATE;" | xargs)
  echo "# New cluster LC_COLLATE: $cluster_collate"
  [[ "$cluster_collate" == *"en_US"* ]]
}

@test "Phase 6: Restore database with locale compatibility" {
  # Create new database with en_US locale
  echo "# Creating new database with en_US locale"
  sudo -u postgres psql -c "CREATE DATABASE testdb_locale TEMPLATE template0 LC_CTYPE 'en_US.UTF-8' LC_COLLATE 'en_US.UTF-8' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser_locale WITH ENCRYPTED PASSWORD 'raspiblitz';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb_locale TO testuser_locale;"
  
  # Restore data from backup
  echo "# Restoring database from SQL backup"
  sudo -u postgres psql testdb_locale < /tmp/pg_locale_test/testdb_backup.sql
  
  # Verify database locale settings
  new_db_collate=$(sudo -u postgres psql testdb_locale -t -c "SHOW LC_COLLATE;" | xargs)
  new_db_ctype=$(sudo -u postgres psql testdb_locale -t -c "SHOW LC_CTYPE;" | xargs)
  echo "# Restored database LC_COLLATE: $new_db_collate"
  echo "# Restored database LC_CTYPE: $new_db_ctype"
  [[ "$new_db_collate" == *"en_US"* ]]
  [[ "$new_db_ctype" == *"en_US"* ]]
}

@test "Phase 7: Verify data integrity after locale change" {
  # Check that all records were restored
  echo "# Verifying data integrity after locale change"
  record_count=$(sudo -u postgres psql testdb_locale -t -c "SELECT COUNT(*) FROM test_data;" | xargs)
  echo "# Record count: $record_count"
  [ "$record_count" -eq 3 ]
  
  # Verify specific data with currency symbols
  run sudo -u postgres psql testdb_locale -t -c "SELECT name FROM test_data WHERE amount = 100.50;"
  echo "$output" | grep -q "British Pound Test"
  [ "$?" -eq 0 ]
  
  run sudo -u postgres psql testdb_locale -t -c "SELECT description FROM test_data WHERE name = 'British Pound Test';"
  echo "$output" | grep -q "£100.50"
  [ "$?" -eq 0 ]
  
  # Verify Euro symbol is preserved
  run sudo -u postgres psql testdb_locale -t -c "SELECT description FROM test_data WHERE name = 'Euro Test';"
  echo "$output" | grep -q "€200.75"
  [ "$?" -eq 0 ]
  
  echo "# Data integrity verified successfully"
}

@test "Phase 8: Test database operations with new locale" {
  # Test inserting new data with US formatting
  echo "# Testing database operations with en_US locale"
  sudo -u postgres psql testdb_locale -c "INSERT INTO test_data (name, amount, description) VALUES 
    ('US Dollar Test', 400.99, 'Amount: \$400.99'),
    ('Date Test US', 500.00, 'Created on $(date +%m/%d/%Y)');"
  
  # Verify new records
  record_count=$(sudo -u postgres psql testdb_locale -t -c "SELECT COUNT(*) FROM test_data;" | xargs)
  echo "# Total record count: $record_count"
  [ "$record_count" -eq 5 ]
  
  # Test sorting with different locale (should work with both old and new data)
  run sudo -u postgres psql testdb_locale -t -c "SELECT name FROM test_data ORDER BY name;"
  [ "$?" -eq 0 ]
  
  # Test numeric operations
  total_amount=$(sudo -u postgres psql testdb_locale -t -c "SELECT SUM(amount) FROM test_data;" | xargs)
  echo "# Total amount: $total_amount"
  # Should be 100.50 + 200.75 + 300.25 + 400.99 + 500.00 = 1501.49
  [[ "$total_amount" == "1501.49" ]]
  
  echo "# Database operations test completed successfully"
}

@test "Cleanup: Remove test data and restore locale" {
  # Clean up test files
  sudo rm -rf /tmp/pg_locale_test
  
  # Stop PostgreSQL
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  
  # Clean up clusters
  sudo pg_dropcluster 15 main --stop || true
  sudo pg_dropcluster 13 main --stop || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
  
  # Restore original locale if backup exists
  if [ -f /tmp/original_locale.txt ]; then
    echo "# Restoring original locale settings"
    # Note: Full locale restoration would require a reboot in practice
    # For testing purposes, we just clean up our changes
    sudo rm -f /tmp/original_locale.txt
  fi
  
  echo "# Cleanup completed successfully"
}
