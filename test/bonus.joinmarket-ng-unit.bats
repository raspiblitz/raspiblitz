#!/usr/bin/env bats

# Pure unit generation checks, no installation, root privileges, or node paths.
@test "maker declares its staging source independently of the optional credentials" {
  local script="${BATS_TEST_DIRNAME}/../home.admin/config.scripts/bonus.joinmarket-ng.sh"
  local generator
  generator=$(awk '/^systemd_unit_contents\(\)/ { capture=1 } capture { print } capture && /^}$/ { exit }' "$script")
  [ -n "$generator" ]
  run bash -c "$generator"'
USER_JM=testmaker
APPID=joinmarket-ng
SERVICE_HELPER=/usr/local/sbin/raspiblitz-joinmarket-ng-service
bitcoind_service=bitcoind
systemd_unit_contents
'
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fx 'EnvironmentFile=-/home/testmaker/.joinmarket-ng/.maker.env'
  echo "$output" | grep -Fx 'Environment="JOINMARKET_STAGED_CREDENTIALS_FILE=/home/testmaker/.joinmarket-ng/.maker.env"'
  echo "$output" | grep -Fx "ExecStart=/bin/bash -c 'exec jm-maker start'"
  echo "$output" | grep -Fx "ExecStopPost=/bin/bash -c 'rm -f /home/testmaker/.joinmarket-ng/.maker.env'"
  echo "$output" | grep -Fx 'Restart=on-failure'
}
