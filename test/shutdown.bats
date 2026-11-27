#!/usr/bin/env bats

setup() {
  sandbox="$BATS_TEST_TMPDIR"
  export calls="$sandbox/calls"
  export PATH="$sandbox/bin:$PATH"
  mkdir "$sandbox/bin"
  # Exercise the whole service shutdown sequence with isolated state and commands.
  sed -e "s@/home/admin/_cache.sh@$sandbox/cache@g" \
      -e 's/"$EUID"/"0"/' \
      "$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.shutdown.sh" >"$sandbox/shutdown.sh"
  printf '%s\n' '#!/bin/sh' 'if [ "$1" = get ]; then echo network=; else echo "cache $*" >> "$calls"; fi' >"$sandbox/cache"
  for name in sudo sleep sync; do
    printf '%s\n' '#!/bin/sh' 'echo "${0##*/} $*" >>"$calls"' >"$sandbox/bin/$name"
  done
  printf '%s\n' '#!/bin/sh' 'echo "systemctl $*" >>"$calls"' '[ "$1" != is-active ]' >"$sandbox/bin/systemctl"
  printf '%s\n' '#!/bin/sh' 'echo "shutdown $*" >>"$calls"' 'exit "${shutdown_result:-0}"' >"$sandbox/bin/shutdown"
  chmod +x "$sandbox/cache" "$sandbox/bin/"*
}

@test "reboot from a service without a session bus syncs and submits one orderly request" {
  unset DBUS_SESSION_BUS_ADDRESS
  run bash "$sandbox/shutdown.sh" reboot
  [ "$status" -eq 0 ]
  [ "$(tail -2 "$calls")" = "$(printf 'sync \nshutdown -r now')" ]
  ! grep -q -- '--force' "$calls"
}

@test "a stale login bus does not affect the poweroff request" {
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
  run bash "$sandbox/shutdown.sh"
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$calls")" = 'shutdown -P now' ]
  ! grep -q -- '--force' "$calls"
}

@test "a failed orderly request reaches the caller without forcing a reset" {
  unset DBUS_SESSION_BUS_ADDRESS
  export shutdown_result=7
  run bash "$sandbox/shutdown.sh" reboot
  [ "$status" -eq 7 ]
  [[ "$output" == *"services may already be stopped"* ]]
  grep -Fx 'cache set state error' "$calls"
  grep -F 'cache set message Shutdown request failed' "$calls"
  [ "$(grep -c '^shutdown ' "$calls")" -eq 1 ]
  ! grep -q -- '--force' "$calls"
}
