#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  export PATH="$PWD/bin:$PATH"
  mkdir -p bin admin/config.scripts bitcoin/.lightning/bitcoin
  sed -e "s|/home/admin|$PWD/admin|g" -e "s|/home/bitcoin|$PWD/bitcoin|g" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/cl-plugin.backup.sh" >backup.sh
  cat >admin/config.scripts/network.aliases.sh <<'SH'
#!/bin/sh
echo 'CLNETWORK=bitcoin netprefix= lightningcli_alias=mock-lightning-cli'
SH
  cat >bin/sudo <<'SH'
#!/bin/sh
case "$1" in
  df|du|stat|ls|test) exec "$@" ;;
  *) echo "unexpected privileged command: $*" >>unexpected; exit 1 ;;
esac
SH
  cat >bin/df <<'SH'
#!/bin/bash
echo "${!#}" >>df-target
if [[ ${!#} = /tmp ]]; then AVAILABLE=${TEMP_AVAILABLE:-$AVAILABLE}; fi
if [[ -f installed ]]; then AVAILABLE=3072; fi
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'fixture 1048576 1000 %s 50%% /\n' "$AVAILABLE"
SH
  cat >bin/stat <<'SH'
#!/bin/bash
if [[ $2 = %d ]]; then
  if [[ ${!#} = /tmp ]]; then echo "${TEMP_DEVICE:-2}"; else echo 1; fi
elif [[ ${DENY_STAT:-0} = 1 ]]; then
  exit 1
else
  exec /usr/bin/stat "$@"
fi
SH
  cat >bin/du <<'SH'
#!/bin/bash
case "${!#}" in *.backup) echo "$BACKUP_MIB";; *) echo 1;; esac
SH
  printf '#!/bin/sh\necho "$*" >>journal\n' >bin/logger
  printf '#!/bin/sh\necho "$*" >>rpc\n' >bin/mock-lightning-cli
  chmod +x bin/* admin/config.scripts/network.aliases.sh
  truncate -s 1M bitcoin/.lightning/bitcoin/lightningd.sqlite3
  echo 'recovery fixture' >bitcoin/lightningd.sqlite3.backup
  export BACKUP_MIB=28 AVAILABLE=3072
}

@test "a nearly full destination fails before the relative backup-size check" {
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"Low CLN backup space"* ]]
  grep -Fxq "$PWD/bitcoin/lightningd.sqlite3.backup" df-target
  grep -qF "3072 KiB available, need at least 205824 KiB" journal
  [ "$(cat bitcoin/lightningd.sqlite3.backup)" = 'recovery fixture' ]
  [ ! -e rpc ]
}

@test "low-space initialization leaves the old backup and running service alone" {
  run bash backup.sh on mainnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"Low CLN backup space"* ]]
  grep -Fxq "$PWD/bitcoin" df-target
  [ "$(cat bitcoin/lightningd.sqlite3.backup)" = 'recovery fixture' ]
  [ ! -e unexpected ]
}

@test "an unavailable free-space reading prevents compaction" {
  export AVAILABLE=unknown BACKUP_MIB=202
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot determine available CLN backup space"* ]]
  [ ! -e rpc ]
}

@test "normal compact threshold is preserved with sufficient headroom" {
  export AVAILABLE=205824
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 0 ]
  [ ! -e rpc ]
  export BACKUP_MIB=202
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 0 ]
  [ "$(cat rpc)" = backup-compact ]
}

@test "compaction refuses a full temporary device and simultaneous copies on a shared device" {
  export BACKUP_MIB=202 AVAILABLE=205824 TEMP_AVAILABLE=3072
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"Low CLN backup space on /tmp"* ]]
  export TEMP_DEVICE=1
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"need at least 206848 KiB"* ]]
  [ "$(cat bitcoin/lightningd.sqlite3.backup)" = 'recovery fixture' ]
  [ ! -e rpc ]
}

@test "an unreadable database size never falls back to the empty-database threshold" {
  export AVAILABLE=205000 DENY_STAT=1
  run bash backup.sh on mainnet
  [ "$status" -eq 1 ]
  [ ! -e df-target ]
  [ ! -e unexpected ]
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 1 ]
  [ ! -e df-target ]
}

@test "an archived disabled backup is skipped and an active missing backup is reported" {
  mv bitcoin/lightningd.sqlite3.backup bitcoin/lightningd.sqlite3.backup.archived
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 0 ]
  [[ "$output" == *"No active CLN file backup"* ]]
  touch bitcoin/.lightning/bitcoin/backup.lock
  run bash backup.sh backup-compact mainnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"recovery file is missing"* ]]
  [ "$(cat bitcoin/lightningd.sqlite3.backup.archived)" = 'recovery fixture' ]
}

@test "an installation that consumes the available space is stopped before backup rotation" {
  export AVAILABLE=300000
  sed '/^function install() {/,/^}/c\function install() { touch installed; }' backup.sh >install-fixture.sh
  run bash install-fixture.sh on mainnet
  [ "$status" -eq 1 ]
  [ -e installed ]
  [[ "$output" == *"Low CLN backup space"* ]]
  [ "$(cat bitcoin/lightningd.sqlite3.backup)" = 'recovery fixture' ]
  [ ! -e unexpected ]
}
