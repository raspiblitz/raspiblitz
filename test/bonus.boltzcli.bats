#!/usr/bin/env bats

setup() {
  # check if CLN or LND is available (boltzcli requires a lightning node)
  local has_cln=0
  local has_lnd=0
  
  run sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/config getinfo 2>/dev/null
  if [ "$status" -eq 0 ]; then
    has_cln=1
  fi
  
  run sudo -u bitcoin /usr/local/bin/lncli getinfo 2>/dev/null
  if [ "$status" -eq 0 ]; then
    has_lnd=1
  fi
  
  if [ "$has_cln" -eq 0 ] && [ "$has_lnd" -eq 0 ]; then
    skip "No Lightning node available (CLN or LND required)"
  fi
}

@test "Install Boltz Client" {
  # run the install script
  run ../home.admin/config.scripts/bonus.boltzcli.sh on
  [ "$status" -eq 0 ]
  # check if service is enabled
  run systemctl is-enabled boltzcli
  [ "$output" = "enabled" ]
}

@test "Verify Boltz service is running" {
  # check if service is active
  run systemctl is-active boltzcli
  [ "$output" = "active" ]
}

@test "Verify boltzcli CLI responds" {
  # check if CLI responds to getinfo
  run sudo -u boltz /usr/local/bin/boltzcli --datadir /mnt/hdd/app-data/boltzcli getinfo
  [ "$status" -eq 0 ]
  # verify output contains expected fields
  echo "$output" | grep -q "node"
  [ "$?" -eq 0 ]
}

@test "Verify mnemonic backup file exists" {
  # check if mnemonic backup was created
  [ -s "/mnt/hdd/app-data/boltzcli/swap_mnemonic.backup" ]
  # check permissions (should be 600)
  run stat -c "%a" /mnt/hdd/app-data/boltzcli/swap_mnemonic.backup
  [ "$output" = "600" ]
}

@test "Verify alias is configured" {
  # check if boltzcli alias exists in _aliases
  run grep "alias boltzcli=" /home/admin/_aliases
  [ "$status" -eq 0 ]
  # check if boltzlog alias exists
  run grep "alias boltzlog=" /home/admin/_aliases
  [ "$status" -eq 0 ]
}

@test "Verify getpairs returns data" {
  # check if we can fetch swap pairs
  run sudo -u boltz /usr/local/bin/boltzcli --datadir /mnt/hdd/app-data/boltzcli getpairs --json
  [ "$status" -eq 0 ]
  # verify JSON contains expected structure
  echo "$output" | jq -e '.submarine' > /dev/null
  [ "$?" -eq 0 ]
}

@test "Uninstall Boltz Client" {
  # run the uninstall script
  run ../home.admin/config.scripts/bonus.boltzcli.sh off
  [ "$status" -eq 0 ]
  # verify service is removed
  run systemctl is-enabled boltzcli 2>&1
  [ "$status" -ne 0 ]
  # verify binaries are removed
  [ ! -f "/usr/local/bin/boltzd" ]
  [ ! -f "/usr/local/bin/boltzcli" ]
}

@test "Verify aliases removed after uninstall" {
  # check if boltzcli alias was removed
  run grep "alias boltzcli=" /home/admin/_aliases 2>&1
  [ "$status" -ne 0 ]
  # check if boltzlog alias was removed
  run grep "alias boltzlog=" /home/admin/_aliases 2>&1
  [ "$status" -ne 0 ]
}

@test "Cleanup boltzcli data" {
  # clean up data directory if still exists
  if [ -d "/mnt/hdd/app-data/boltzcli" ]; then
    sudo rm -rf /mnt/hdd/app-data/boltzcli
  fi
  [ ! -d "/mnt/hdd/app-data/boltzcli" ]
}
