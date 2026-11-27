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
echo "SMART health: ${HEALTH:-PASSED}"
[ "${HEALTH:-PASSED}" = PASSED ]
MOCK
  chmod +x "$sandbox/bin/"*
}

@test "boot and support inventory can run without querying SMART or identifying disks by serial" {
  run bash "$admin/config.scripts/blitz.hardware.sh" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvme0n1"* && "$output" == *"5000M"* ]]
  [ ! -s "$calls" ]
}

@test "manual summary reads health from supported whole disks with the standby guard" {
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart
  [ "$status" -eq 0 ]
  [ "$(cat "$calls")" = "$(printf '%s\n' '-n standby,0 -H /dev/nvme0n1' '-n standby,0 -H /dev/sda')" ]
}

@test "failed SMART remains visible and the other disks are still checked" {
  export HEALTH=FAILED
  run bash "$admin/config.scripts/blitz.hardware.sh" check smart
  [ "$status" -ne 0 ]
  [[ "$output" == *FAILED* ]]
  [ "$(wc -l < "$calls")" -eq 2 ]
}

@test "SYSTEM and REPAIR both reach the manual check and SYSTEM can view debug locally" {
  # Exercise the menu dispatch without a real terminal or root privileges.
  mkdir -p "$sandbox/admin/config.scripts" "$sandbox/data"
  touch "$sandbox/admin/raspiblitz.info" "$sandbox/data/raspiblitz.conf"
  printf '%s\n' '#!/bin/bash' 'echo "CHAIN=mainnet"' 'echo "network=bitcoin"' >"$sandbox/admin/config.scripts/network.aliases.sh"
  printf '%s\n' '#!/bin/bash' 'echo "txindex=0"' >"$sandbox/admin/config.scripts/network.txindex.sh"
  cp "$admin/config.scripts/blitz.hardware.sh" "$sandbox/admin/config.scripts/"
  chmod +x "$sandbox/admin/config.scripts/"*
  printf '%s\n' 'debug() { printf "local-debug:%s\n" "$#" >> "$calls"; }' >"$sandbox/admin/_commands.sh"
  printf '%s\n' '#!/bin/bash' 'exec "$@"' >"$sandbox/bin/sudo"
  printf '%s\n' '#!/bin/bash' '[[ " $* " == *" $pick "* ]] || exit 1' 'echo "$pick" >&2' >"$sandbox/bin/dialog"
  cp "$sandbox/bin/dialog" "$sandbox/bin/whiptail"
  chmod +x "$sandbox/bin/"*
  export TERM=dumb
  for menu in 99systemMenu.sh 98repairMenu.sh; do
    sed -e "s|/home/admin|$sandbox/admin|g" -e "s|/mnt/hdd/app-data|$sandbox/data|g" -e 's|>/dev/tty|>/dev/null|g' "$admin/$menu" >"$sandbox/$menu"
    export pick=HARDWARE
    run bash "$sandbox/$menu" <<< ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"SMART health: PASSED"* ]]
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
  grep -F 'wal=***&wal=***' "$sandbox/sent"
  [ -z "$(ls -A "$TMPDIR")" ]
}
