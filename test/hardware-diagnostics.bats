#!/usr/bin/env bats

setup() {
  export sandbox="$BATS_TEST_TMPDIR" calls="$BATS_TEST_TMPDIR/calls"
  admin="$BATS_TEST_DIRNAME/../home.admin"
  export PATH="$sandbox/bin:$PATH"
  mkdir -p "$sandbox/bin"
  touch "$calls"
  cat >"$sandbox/bin/lsblk" <<'MOCK'
#!/bin/bash
case " $* " in
  *" --raw "*) printf '%s\n' 'nvme0n1 disk nvme' 'sda disk usb' 'mmcblk0 disk mmc' 'vda disk virtio' 'sda1 part usb' ;;
  *) echo "NAME TYPE TRAN SIZE"; echo "nvme0n1 disk nvme 2T" ;;
esac
MOCK
  cat >"$sandbox/bin/lsusb" <<'MOCK'
#!/bin/bash
[ "$1" = -t ] && echo 'USB tree (5000M)'
MOCK
  cat >"$sandbox/bin/smartctl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$calls"
if [[ "$*" == *'-d sat'* ]]; then
  echo '{"smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":4}}]},"ata_smart_error_log":{"summary":{"count":2}}}'
  exit 64
fi
case "${HEALTH:-PASSED}" in
  SLOW) if [[ "$*" == *'/dev/nvme0n1' ]]; then exec sleep 30; fi; echo '{"smart_status":{"passed":true}}' ;;
  FAILED) echo '{"smart_status":{"passed":false}}'; exit 8 ;;
  USB) echo '{}'; exit 2 ;;
  MISSING) echo '{}'; exit 0 ;;
  STANDBY) echo '{"smartctl":{"messages":[{"string":"Device is in STANDBY mode, exit(2)"}]}}'; exit 2 ;;
  NVME) printf '{"smart_status":{"passed":true},"serial_number":"private-serial","nvme_smart_health_information_log":{"percentage_used":%d,"critical_warning":0,"media_errors":%d,"data_units_written":2000000}}\n' "$wear" "${errors:-0}" ;;
  *) echo '{"smart_status":{"passed":true}}' ;;
esac
MOCK
  chmod +x "$sandbox/bin/"*
}

@test "boot and support inventory can run without querying SMART or identifying disks by serial" {
  run "$admin/config.scripts/blitz.hardware.sh" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvme0n1"* && "$output" == *"5000M"* ]]
  [ ! -s "$calls" ]
}

@test "manual summary reads health from supported whole disks with the standby guard" {
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart
  [ "$status" -eq 0 ]
  [ "$(cat "$calls")" = "$(printf '%s\n' '-a -j /dev/nvme0n1' '-a -j -n standby,2 /dev/sda')" ]
}

@test "failed SMART remains visible and the other disks are still checked" {
  export HEALTH=FAILED
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart
  [ "$status" -ne 0 ]
  [[ "$output" == *FAILED* ]]
  [ "$(wc -l < "$calls")" -eq 2 ]
}

@test "an unresponsive disk times out and the next disk is still read" {
  export HEALTH=SLOW
  run "$admin/config.scripts/blitz.hardware.sh" check smart
  [ "$status" -eq 1 ]
  [[ "$output" == *"within 20 seconds"* && "$output" == *"SMART health: PASSED"* ]]
}

@test "SYSTEM and REPAIR both reach the manual check and SYSTEM can view debug locally" {
  # Exercise the menu dispatch without a real terminal or root privileges.
  mkdir -p "$sandbox/admin/config.scripts" "$sandbox/data"
  touch "$sandbox/admin/raspiblitz.info" "$sandbox/data/raspiblitz.conf"
  printf '%s\n' '#!/bin/bash' 'echo "CHAIN=mainnet"' 'echo "network=bitcoin"' >"$sandbox/admin/config.scripts/network.aliases.sh"
  printf '%s\n' '#!/bin/bash' 'echo "txindex=0"' >"$sandbox/admin/config.scripts/network.txindex.sh"
  cp "$admin/config.scripts/blitz.hardware.sh" "$sandbox/admin/config.scripts/"
  cp "$admin/config.scripts/blitz.drive-health.py" "$sandbox/admin/config.scripts/"
  chmod +x "$sandbox/admin/config.scripts/"*
  printf '%s\n' 'debug() { printf "local-debug:%s\n" "$#" >> "$calls"; }' >"$sandbox/admin/_commands.sh"
  printf '%s\n' '#!/bin/bash' 'exec "$@"' >"$sandbox/bin/sudo"
  printf '%s\n' '#!/bin/bash' 'if [[ "$*" == *"Select a disk"* ]]; then echo sda >&2; exit 0; fi' '[[ " $* " == *" $pick "* ]] || exit 1' 'echo "$pick" >&2' >"$sandbox/bin/dialog"
  cp "$sandbox/bin/dialog" "$sandbox/bin/whiptail"
  chmod +x "$sandbox/bin/"*
  export TERM=dumb
  for menu in 99systemMenu.sh 98repairMenu.sh; do
    sed -e "s|/home/admin|$sandbox/admin|g" -e "s|/mnt/hdd/app-data|$sandbox/data|g" -e 's|>/dev/tty|>/dev/null|g' "$admin/$menu" >"$sandbox/$menu"
    export pick=HARDWARE
    run bash "$sandbox/$menu" <<< ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"SMART health: PASSED"* ]]
    [ "$(tail -1 "$calls")" = '-a -j -n standby,2 /dev/sda' ]
  done
  export pick=DEBUG
  run bash "$sandbox/99systemMenu.sh" <<< ""
  [ "$status" -eq 0 ]
  grep -Fx 'local-debug:0' "$calls"
  export pick=SOFTWARE
  run bash "$sandbox/98repairMenu.sh" <<< ""
  [ "$status" -eq 0 ]
  [ "$(grep -Fc 'local-debug:0' "$calls")" -eq 2 ]
}

@test "NVMe thresholds, device health and host writes are reported without exposing identifiers" {
  export HEALTH=NVME wear=75
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart nvme0n1
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.02 TB"* && "$output" != *"private-serial"* ]]
  for wear in 76 90 91; do
    run bash "$admin/config.scripts/blitz.hardware.sh" check smart nvme0n1
    [ "$status" -eq 1 ]
    if [ "$wear" = 91 ]; then [[ "$output" == *"critical wear"* ]]; else [[ "$output" == *"wear warning"* ]]; fi
  done
  export wear=5 errors=2
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart nvme0n1
  [ "$status" -eq 1 ]
  [[ "$output" == *"media/data integrity errors: 2"* ]]
}

@test "USB bridges retry SAT for an unsupported command and flag ATA errors" {
  export HEALTH=USB
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart sda
  [ "$status" -eq 1 ]
  [[ "$output" == *"Reallocated_Sector_Ct: 4 (review)"* && "$output" == *"ATA logged errors: 2"* ]]
  [ "$(wc -l < "$calls")" -eq 2 ]
}

@test "standby is skipped, unsupported health is explicit, and a partition cannot be selected" {
  export HEALTH=STANDBY
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart sda
  [ "$status" -eq 0 ]
  [[ "$output" == *"check skipped"* ]]
  [ "$(wc -l < "$calls")" -eq 1 ]
  export HEALTH=MISSING
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart nvme0n1
  [ "$status" -eq 1 ]
  [[ "$output" == *"unavailable"* ]]
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart sda1
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$calls")" -eq 2 ]
}

prepare_debug() {
  export TMPDIR="$sandbox/private tmp" redactor="$admin/config.scripts/blitz.debug.sh"
  mkdir -p "$TMPDIR" "$sandbox/admin/config.scripts"
  sed "s|/home/admin|$sandbox/admin|g" "$admin/_commands.sh" >"$sandbox/commands.sh"
  cat >"$sandbox/admin/config.scripts/blitz.debug.sh" <<'MOCK'
#!/bin/bash
if [ "$1" = redact ]; then
  [ "$(stat -c %a "$2")" = 600 ] && [ "$(stat -c %a "$(dirname "$2")")" = 700 ] || exit 1
  exec bash "$redactor" "$@"
fi
echo 'collector diagnostic for fixture' >&2
[ "${fault:-}" != empty ] || exit 0
echo 'API query: wal=TEST_FIRST&wal=TEST_SECOND at 192.0.2.2 and 198.51.100.5'
echo 'IPv6 [2001:db8::20] and fe80::1%eth0 and 2001:db8:0:0:0:0:0:20'
echo 'headers: "api-key": "TEST_QUOTED", X-Api-Key: TEST_HEADER or api_key="TEST_ATTRIBUTE"'
[ "${fault:-}" != collect ]
MOCK
  cat >"$sandbox/bin/nc" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"$calls"
cat >"$sandbox/sent"
MOCK
  chmod +x "$sandbox/admin/config.scripts/blitz.debug.sh" "$sandbox/bin/nc"
  export TERM=dumb
  source "$sandbox/commands.sh"
}

@test "debug displays only the redacted report and cleans its private directory" {
  prepare_debug
  run debug
  [ "$status" -eq 0 ]
  [[ "$output" == *'wal=***&wal=*** at *.*.*.* and *.*.*.*'* ]]
  [[ "$output" != *TEST_FIRST* && "$output" != *'collector diagnostic'* ]]
  [[ "$output" != *TEST_QUOTED* && "$output" != *TEST_HEADER* && "$output" != *TEST_ATTRIBUTE* ]]
  [[ "$output" != *'2001:db8'* && "$output" != *'fe80::1'* && "$output" != *'%eth0'* ]]
  [ ! -e "$sandbox/sent" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "debug stops before printing or sharing on collect, empty report and sed failures" {
  prepare_debug
  for fault in collect empty redact; do
    export fault
    if [ "$fault" = redact ]; then
      printf '%s\n' '#!/bin/bash' 'exit 2' >"$sandbox/bin/sed"
      chmod +x "$sandbox/bin/sed"
    fi
    for mode in local share; do
      if [ "$mode" = local ]; then run debug; else run debug --link; fi
      [ "$status" -ne 0 ]
      [[ "$output" != *TEST_FIRST* && "$output" != *'collector diagnostic'* ]]
      [ ! -e "$sandbox/sent" ]
      [ -z "$(ls -A "$TMPDIR")" ]
    done
  done
}

@test "explicit link flags pass a redacted report to the selected transport" {
  prepare_debug
  run debug -l
  [ "$status" -eq 0 ]
  grep -Fx -- '-X 5 -x localhost:9050 termbin.com 9999' "$calls"
  run debug --link --no-tor
  [ "$status" -eq 0 ]
  grep -Fx 'termbin.com 9999' "$calls"
  ! grep -q TEST_ "$sandbox/sent"
  ! grep -Eq '2001:db8|fe80::1|%eth0' "$sandbox/sent"
  grep -F 'wal=***&wal=***' "$sandbox/sent"
  [ -z "$(ls -A "$TMPDIR")" ]
}
