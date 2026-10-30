#!/usr/bin/env bats

# Pure unit generation checks, no installation, root privileges, or node paths.
@test "installer and integration tests pin the same stable release" {
  local installer_version integration_version
  installer_version=$(sed -n 's/^GITHUB_TAG="\([^"]*\)"$/\1/p' \
    "${BATS_TEST_DIRNAME}/../home.admin/config.scripts/bonus.joinmarket-ng.sh")
  integration_version=$(sed -n 's/^JM_VERSION="\([^"]*\)"$/\1/p' \
    "${BATS_TEST_DIRNAME}/bonus.joinmarket-ng.bats")

  [[ "$installer_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ "$installer_version" = "$integration_version" ]
}

@test "unattended maker restarts explain the wallet identity upgrade requirement" {
  local script="${BATS_TEST_DIRNAME}/../home.admin/config.scripts/bonus.joinmarket-ng.sh"
  local notice mode
  notice=$(awk '
    /^    case "\$\{MAKER_PASSWORD_MODE\}" in$/ { restart_modes=1 }
    restart_modes && /^    if \[ "\$\{MAKER_PASSWORD_MODE\}" != "temporary" \]; then$/ { capture=1 }
    capture { print }
    capture && /^    fi$/ { exit }
  ' "$script")
  [ -n "$notice" ]

  for mode in stored none; do
    run env MAKER_PASSWORD_MODE="$mode" bash -c "$notice"
    [ "$status" -eq 0 ]
    echo "$output" | grep -Fq 'register the intended wallet identity once in jm-ng'
  done

  run env MAKER_PASSWORD_MODE=temporary bash -c "$notice"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

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
