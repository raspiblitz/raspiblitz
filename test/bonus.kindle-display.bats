#!/usr/bin/env bats

# integration tests for kindle-display install/update/uninstall
# based on the bonus.postgresql tests pattern
# runs as root: sudo bats ./bonus.kindle-display.bats

# unconditional cleanup after every test: bats aborts a test at the first
# failing assertion, so in-test cleanup lines may never be reached
teardown() {
  if [ -f /usr/bin/npm.real ]; then
    sudo mv /usr/bin/npm.real /usr/bin/npm
  fi
  if ! grep -q "^SHA256=48a54ae42d4d88cfe52834c2765379ef5ed2bfd9b41090d408e6e8118bd6e8e9" "/home/admin/config.scripts/bonus.kindle-display.sh" 2>/dev/null; then
    sudo sed -i "s/^SHA256=.*/SHA256=48a54ae42d4d88cfe52834c2765379ef5ed2bfd9b41090d408e6e8118bd6e8e9/" /home/admin/config.scripts/bonus.kindle-display.sh
  fi
  sudo rm -f /home/kindledisplay/v1.1.1.tar.gz
}

@test "Testbed preparation" {
  sudo apt-get install -y ufw pngcrush nodejs sudo wget
  sudo mkdir -p /mnt/hdd/app-data
  sudo touch /mnt/hdd/app-data/raspiblitz.conf
  sudo mkdir -p /home/admin
  sudo cp -a ../home.admin/. /home/admin/
  echo 'network=bitcoin' | sudo tee /home/admin/raspiblitz.info
  printf '#!/bin/bash\nif [ "$1" = "get" ]; then echo "state=ready"; fi\nexit 0\n' | sudo tee /home/admin/_cache.sh
  sudo chmod +x /home/admin/_cache.sh
}

@test "checksum mismatch aborts install" {
  # ensure clean state
  run /home/admin/config.scripts/bonus.kindle-display.sh off
  # simulate a manipulated download by breaking the pinned checksum
  sudo sed -i "s/^SHA256=.*/SHA256=deadbeef/" /home/admin/config.scripts/bonus.kindle-display.sh
  run /home/admin/config.scripts/bonus.kindle-display.sh on
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not matching SHA256 checksum"
  [ "$?" -eq 0 ]
  [ ! -f /etc/systemd/system/kindle-display-server.service ]
  sudo rm -rf /home/kindledisplay
  sudo userdel -rf kindledisplay 2>/dev/null || true
}

@test "npm install failure aborts before services" {
  # ensure clean state
  run /home/admin/config.scripts/bonus.kindle-display.sh off
  # simulate a broken npm
  sudo mv /usr/bin/npm /usr/bin/npm.real
  printf '#!/bin/bash\nexit 1\n' | sudo tee /usr/bin/npm
  sudo chmod +x /usr/bin/npm
  run /home/admin/config.scripts/bonus.kindle-display.sh on
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "npm install did not run correctly"
  [ "$?" -eq 0 ]
  [ ! -f /etc/systemd/system/kindle-display-server.service ]
  sudo rm -rf /home/kindledisplay
  sudo userdel -rf kindledisplay 2>/dev/null || true
}

@test "fresh install succeeds" {
  # ensure clean state
  run /home/admin/config.scripts/bonus.kindle-display.sh off
  run /home/admin/config.scripts/bonus.kindle-display.sh on
  [ "$status" -eq 0 ]
  # user and app dir
  run id kindledisplay
  [ "$status" -eq 0 ]
  [ -f /home/kindledisplay/kindle-display/server/package.json ]
  # config values (mempoolExplorer unset -> commented MEMPOOL_BASE_URL)
  [ -f /mnt/hdd/app-data/kindle-display/.env ]
  grep -q '^DISPLAY_SERVER_PORT=3030' /mnt/hdd/app-data/kindle-display/.env
  grep -q '^DISPLAY_RATE1="USD"' /mnt/hdd/app-data/kindle-display/.env
  grep -q '^DISPLAY_RATE2="EUR"' /mnt/hdd/app-data/kindle-display/.env
  grep -q '^DISPLAY_THEME="random"' /mnt/hdd/app-data/kindle-display/.env
  grep -q '^# MEMPOOL_BASE_URL' /mnt/hdd/app-data/kindle-display/.env
  # service units
  [ -f /etc/systemd/system/kindle-display-server.service ]
  [ -f /etc/systemd/system/kindle-display-update.service ]
  [ -f /etc/systemd/system/kindle-display-update.timer ]
  # firewall rule (ufw show added also lists rules while ufw is inactive)
  run sudo ufw show added
  [ $(echo "$output" | grep -c 'kindle-display HTTP') -gt 0 ]
  # blitz conf
  grep -q 'kindleDisplay=on' /mnt/hdd/app-data/raspiblitz.conf
  # service running
  [ "$(sudo systemctl is-active kindle-display-server.service)" = "active" ]
}

@test "update skips when current" {
  run /home/admin/config.scripts/bonus.kindle-display.sh update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ALREADY UPDATED"
  [ "$?" -eq 0 ]
  if echo "$output" | grep -q "# install .."; then
    echo "unexpected redownload happened"
    false
  fi
}

@test "upgrade with existing config migrates .env" {
  # add legacy settings that the new version must drop
  sudo sh -c 'echo "DISPLAY_FORCE_TOR=true" >> /mnt/hdd/app-data/kindle-display/.env'
  sudo sh -c 'echo "DISPLAY_BITCOIN_RPC_USER=olduser" >> /mnt/hdd/app-data/kindle-display/.env'
  # fake an outdated installed version
  sudo sed -i 's/"version": ".*"/"version": "0.5.3"/' /home/kindledisplay/kindle-display/server/package.json
  run /home/admin/config.scripts/bonus.kindle-display.sh update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "UPDATED"
  [ "$?" -eq 0 ]
  # known values kept, legacy settings dropped
  grep -q '^DISPLAY_RATE1="USD"' /mnt/hdd/app-data/kindle-display/.env
  grep -q '^DISPLAY_RATE2="EUR"' /mnt/hdd/app-data/kindle-display/.env
  grep -q '^DISPLAY_THEME="random"' /mnt/hdd/app-data/kindle-display/.env
  if grep -q '^DISPLAY_FORCE_TOR=' /mnt/hdd/app-data/kindle-display/.env; then
    echo "legacy DISPLAY_FORCE_TOR was not dropped"
    false
  fi
  if grep -q '^DISPLAY_BITCOIN_RPC_USER=' /mnt/hdd/app-data/kindle-display/.env; then
    echo "legacy DISPLAY_BITCOIN_RPC_USER was not dropped"
    false
  fi
  [ -f /mnt/hdd/app-data/kindle-display/.env.backup ]
  [ ! -d /home/kindledisplay/kindle-display-backup ]
  [ "$(sudo systemctl is-active kindle-display-server.service)" = "active" ]
}

@test "uninstall removes everything" {
  run /home/admin/config.scripts/bonus.kindle-display.sh off
  [ "$status" -eq 0 ]
  [ ! -f /etc/systemd/system/kindle-display-server.service ]
  [ ! -f /etc/systemd/system/kindle-display-update.service ]
  [ ! -f /etc/systemd/system/kindle-display-update.timer ]
  [ ! -f /mnt/hdd/app-data/kindle-display/.env ]
  run id kindledisplay
  [ "$status" -ne 0 ]
  [ ! -d /home/kindledisplay ]
  # firewall rule removed (ufw show added also lists rules while ufw is inactive)
  run sudo ufw show added
  [ $(echo "$output" | grep -c 'kindle-display HTTP') -eq 0 ]
  grep -q 'kindleDisplay=off' /mnt/hdd/app-data/raspiblitz.conf
  # idempotent
  run /home/admin/config.scripts/bonus.kindle-display.sh off
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not installed"
  [ "$?" -eq 0 ]
}

@test "service start failure aborts with cleanup" {
  # baseline install
  run /home/admin/config.scripts/bonus.kindle-display.sh on
  [ "$status" -eq 0 ]
  # simulate a broken npm start
  sudo mv /usr/bin/npm /usr/bin/npm.real
  printf '#!/bin/bash\nif [ "$1" = "start" ]; then exit 1; fi\nexec /usr/bin/npm.real "$@"\n' | sudo tee /usr/bin/npm
  sudo chmod +x /usr/bin/npm
  # force the update flow with the failing start
  sudo sed -i 's/"version": ".*"/"version": "0.5.3"/' /home/kindledisplay/kindle-display/server/package.json
  run /home/admin/config.scripts/bonus.kindle-display.sh update
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "failed to start"
  [ "$?" -eq 0 ]
  # units removed, conf off, backup kept for rollback
  [ ! -f /etc/systemd/system/kindle-display-server.service ]
  grep -q 'kindleDisplay=off' /mnt/hdd/app-data/raspiblitz.conf
  run /home/admin/config.scripts/bonus.kindle-display.sh off
  sudo rm -rf /home/kindledisplay
  sudo userdel -rf kindledisplay 2>/dev/null || true
}

@test "Testbed cleanup" {
  sudo userdel -rf kindledisplay 2>/dev/null || true
  sudo rm -rf /home/kindledisplay
  sudo rm -rf /mnt/hdd/app-data/kindle-display
  sudo rm -f /etc/systemd/system/kindle-display-server.service
  sudo rm -f /etc/systemd/system/kindle-display-update.service
  sudo rm -f /etc/systemd/system/kindle-display-update.timer
  sudo rm -f /home/admin/kindle-display-server.service /home/admin/kindle-display-update.service /home/admin/kindle-display-update.timer /home/admin/kindle-display.env
}
