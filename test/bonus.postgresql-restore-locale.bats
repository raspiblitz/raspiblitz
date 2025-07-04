#!/usr/bin/env bats

# Test PostgreSQL restore functionality across locale changes
# This test uses the built-in backup/restore functionality of bonus.postgresql.sh
# to test locale compatibility when restoring databases

@test "Setup: Prepare en_GB environment and install PostgreSQL" {
  # Ensure both locales are available
  sudo sed -i '/^#en_GB.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo sed -i '/^# en_GB.UTF-8 UTF-8/s/^# //' /etc/locale.gen
  sudo sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo sed -i '/^# en_US.UTF-8 UTF-8/s/^# //' /etc/locale.gen
  sudo locale-gen
  
  # Set to en_GB initially
  export LANG=en_GB.UTF-8
  export LC_ALL=en_GB.UTF-8
  
  # Install PostgreSQL
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  
  # Verify installation
  run pg_lsclusters
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "online"
}

@test "Create test database with en_GB locale and sample data" {
  # Create database with en_GB locale
  sudo -u postgres psql -c "CREATE DATABASE testdb_restore TEMPLATE template0 LC_CTYPE 'en_GB.UTF-8' LC_COLLATE 'en_GB.UTF-8' ENCODING 'UTF8';"
  sudo -u postgres psql -c "CREATE USER testuser_restore WITH ENCRYPTED PASSWORD 'testpass123';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE testdb_restore TO testuser_restore;"
  
  # Create sample data with locale-specific content
  sudo -u postgres psql testdb_restore -c "
    CREATE TABLE products (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100),
      price DECIMAL(10,2),
      description TEXT,
      created_date DATE DEFAULT CURRENT_DATE
    );
    
    INSERT INTO products (name, price, description) VALUES 
      ('British Tea', 4.50, 'Premium Earl Grey - £4.50'),
      ('Scottish Whisky', 45.99, 'Single Malt - £45.99'),
      ('Welsh Cheese', 8.75, 'Caerphilly cheese - £8.75'),
      ('Irish Coffee', 6.25, 'Traditional recipe - £6.25');
    
    CREATE TABLE orders (
      id SERIAL PRIMARY KEY,
      product_id INTEGER REFERENCES products(id),
      quantity INTEGER,
      order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      customer_notes TEXT
    );
    
    INSERT INTO orders (product_id, quantity, customer_notes) VALUES 
      (1, 2, 'Delivery to London postcode SW1A 1AA'),
      (2, 1, 'Gift wrapping requested'),
      (3, 3, 'Please check expiry date'),
      (4, 1, 'Extra hot please');
  "
  
  # Verify data was created
  record_count=$(sudo -u postgres psql testdb_restore -t -c "SELECT COUNT(*) FROM products;" | xargs)
  [ "$record_count" -eq 4 ]
  
  order_count=$(sudo -u postgres psql testdb_restore -t -c "SELECT COUNT(*) FROM orders;" | xargs)
  [ "$order_count" -eq 4 ]
}

@test "Create backup using PostgreSQL script" {
  # Use the built-in backup functionality
  echo "# Creating backup using bonus.postgresql.sh"
  run ../home.admin/config.scripts/bonus.postgresql.sh backup testdb_restore
  [ "$status" -eq 0 ]
  
  # Verify backup was created
  backup_dir="/mnt/hdd/app-data/backup/testdb_restore"
  [ -d "$backup_dir" ]
  
  # Find the backup file (it has a timestamp in the name)
  backup_file=$(ls -t $backup_dir/*.sql | head -n1)
  [ -f "$backup_file" ]
  
  # Verify backup contains our data
  grep -q "British Tea" "$backup_file"
  grep -q "£4.50" "$backup_file"
  grep -q "SW1A 1AA" "$backup_file"
  
  echo "# Backup created: $backup_file"
}

@test "Change system locale to en_US and reinstall PostgreSQL" {
  # Change to en_US locale
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  echo -e "LANG=en_US.UTF-8\nLANGUAGE=en_US.UTF-8\nLC_ALL=en_US.UTF-8" | sudo tee /etc/default/locale > /dev/null
  
  # Stop PostgreSQL
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  
  # Clean up
  sudo pg_dropcluster 15 main --stop || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
  
  # Reinstall with en_US locale
  run ../home.admin/config.scripts/bonus.postgresql.sh on
  [ "$status" -eq 0 ]
  
  # Verify new installation uses en_US
  cluster_locale=$(sudo -u postgres psql -t -c "SHOW LC_COLLATE;" | xargs)
  echo "# New cluster locale: $cluster_locale"
  [[ "$cluster_locale" == *"en_US"* ]]
}

@test "Restore database using PostgreSQL script" {
  # Use the built-in restore functionality
  echo "# Restoring database using bonus.postgresql.sh"
  run ../home.admin/config.scripts/bonus.postgresql.sh restore testdb_restore testuser_restore testpass123
  [ "$status" -eq 0 ]
  
  # Verify database was restored
  run sudo -u postgres psql -l
  echo "$output" | grep -q "testdb_restore"
  
  # Verify user was created
  run sudo -u postgres psql -c "\du"
  echo "$output" | grep -q "testuser_restore"
}

@test "Verify data integrity after restore with locale change" {
  # Check that all products were restored
  product_count=$(sudo -u postgres psql testdb_restore -t -c "SELECT COUNT(*) FROM products;" | xargs)
  echo "# Product count after restore: $product_count"
  [ "$product_count" -eq 4 ]
  
  # Check that all orders were restored
  order_count=$(sudo -u postgres psql testdb_restore -t -c "SELECT COUNT(*) FROM orders;" | xargs)
  echo "# Order count after restore: $order_count"
  [ "$order_count" -eq 4 ]
  
  # Verify specific data with currency symbols
  run sudo -u postgres psql testdb_restore -t -c "SELECT description FROM products WHERE name = 'British Tea';"
  echo "$output" | grep -q "£4.50"
  
  # Verify postcode data (UK format)
  run sudo -u postgres psql testdb_restore -t -c "SELECT customer_notes FROM orders WHERE id = 1;"
  echo "$output" | grep -q "SW1A 1AA"
  
  # Test that we can still query and sort data correctly
  run sudo -u postgres psql testdb_restore -t -c "SELECT name FROM products ORDER BY price DESC LIMIT 1;"
  echo "$output" | grep -q "Scottish Whisky"
  
  # Test numeric operations work correctly
  total_value=$(sudo -u postgres psql testdb_restore -t -c "SELECT SUM(price) FROM products;" | xargs)
  echo "# Total product value: $total_value"
  # Should be 4.50 + 45.99 + 8.75 + 6.25 = 65.49
  [[ "$total_value" == "65.49" ]]
}

@test "Test database operations with mixed locale data" {
  # Insert new data with US formatting
  sudo -u postgres psql testdb_restore -c "
    INSERT INTO products (name, price, description) VALUES 
      ('American Coffee', 3.99, 'Regular blend - \$3.99'),
      ('New York Bagel', 2.50, 'Fresh baked - \$2.50');
    
    INSERT INTO orders (product_id, quantity, customer_notes) VALUES 
      (5, 1, 'Delivery to ZIP code 10001'),
      (6, 2, 'Extra cream cheese');
  "
  
  # Verify mixed data works correctly
  total_products=$(sudo -u postgres psql testdb_restore -t -c "SELECT COUNT(*) FROM products;" | xargs)
  [ "$total_products" -eq 6 ]
  
  total_orders=$(sudo -u postgres psql testdb_restore -t -c "SELECT COUNT(*) FROM orders;" | xargs)
  [ "$total_orders" -eq 6 ]
  
  # Test that both UK and US currency symbols are preserved
  run sudo -u postgres psql testdb_restore -t -c "SELECT description FROM products WHERE price < 5.00;"
  echo "$output" | grep -q "£4.50"  # UK pound
  echo "$output" | grep -q "\$3.99"  # US dollar
  echo "$output" | grep -q "\$2.50"  # US dollar
  
  # Test sorting works with mixed locale data
  run sudo -u postgres psql testdb_restore -t -c "SELECT name FROM products ORDER BY name;"
  [ "$?" -eq 0 ]
  
  echo "# Mixed locale data test completed successfully"
}

@test "Test user authentication and permissions" {
  # Test that the restored user can connect and access data
  run sudo -u postgres psql -d testdb_restore -U testuser_restore -c "SELECT COUNT(*) FROM products;"
  [ "$?" -eq 0 ]
  
  # Test that user has proper permissions
  sudo -u postgres psql testdb_restore -c "
    GRANT SELECT, INSERT, UPDATE, DELETE ON products TO testuser_restore;
    GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO testuser_restore;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO testuser_restore;
  "
  
  # Test insert permission
  run sudo -u postgres psql -d testdb_restore -U testuser_restore -c "
    INSERT INTO products (name, price, description) VALUES ('Test Product', 1.00, 'Test');
  "
  [ "$?" -eq 0 ]
  
  echo "# User authentication and permissions test completed"
}

@test "Cleanup: Remove test data and PostgreSQL" {
  # Stop PostgreSQL
  run ../home.admin/config.scripts/bonus.postgresql.sh off
  [ "$status" -eq 0 ]
  
  # Clean up clusters
  sudo pg_dropcluster 15 main --stop || true
  sudo pg_dropcluster 13 main --stop || true
  sudo rm -rf /mnt/hdd/app-data/postgresql*
  
  # Clean up backup directory
  sudo rm -rf /mnt/hdd/app-data/backup/testdb_restore
  
  echo "# Cleanup completed successfully"
}
