#!/usr/bin/env bats

# Run the existing-install paths against a temporary service tree.
setup() {
  export unitdir="$BATS_TEST_TMPDIR/system"
  export calls="$BATS_TEST_TMPDIR/calls"
  export effective="$BATS_TEST_TMPDIR/effective-env"
  local data="$BATS_TEST_TMPDIR/app-data" bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$unitdir" "$data/bitcoin" "$bin"
  touch "$unitdir/specter.service" "$calls" "$effective"
  printf 'network=bitcoin\nrunBehindTor=off\n' > "$data/raspiblitz.conf"
  echo blockfilterindex=1 > "$data/bitcoin/bitcoin.conf"
  sed -e "s|/etc/systemd/system|$unitdir|g" -e "s|/mnt/hdd/app-data|$data|g" \
    -e "s|/run/raspiblitz-specter-rpc-restart|$BATS_TEST_TMPDIR/restart-pending|g" \
    -e "s|/home/admin/config.scripts/blitz.conf.sh|true|g" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/bonus.specter.sh" > "$BATS_TEST_TMPDIR/installer"
  cat > "$bin/sudo" <<'SCRIPT'
#!/bin/sh
if [ "$1" = -u ]; then exit 0; fi
exec "$@"
SCRIPT
  cat > "$bin/systemctl" <<'SCRIPT'
#!/bin/sh
echo "$1" >> "$calls"
case "$1" in
  show) cat "$effective";;
  is-active) [ -z "$INACTIVE" ];;
  restart) [ -z "$FAIL_RESTART" ];;
  daemon-reload)
    [ -z "$FAIL_RELOAD" ] || exit 1
    sed -n 's/^Environment=//p' "$unitdir/specter.service.d/10-raspiblitz-rpc.conf" > "$effective";;
esac
SCRIPT
  chmod +x "$bin/sudo" "$bin/systemctl"
  export PATH="$bin:$PATH"
}

@test "reprovisioning an old service installs the RPC path and restarts only once if active" {
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -eq 0 ]
  grep -Fxq "RASPIBLITZ_SPECTER_RPC_LOGIN_BITCOIN_CONF_LOCATION=$BATS_TEST_TMPDIR/app-data/bitcoin" "$effective"
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -eq 0 ]
  [ "$(grep -cx restart "$calls")" -eq 1 ]
  [ "$(grep -cx daemon-reload "$calls")" -eq 1 ]
}

@test "the service keeps the administrator's existing Bitcoin config location" {
  echo 'OTHER=1 RASPIBLITZ_SPECTER_RPC_LOGIN_BITCOIN_CONF_LOCATION=/custom/bitcoin' > "$effective"
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -eq 0 ]
  [ ! -e "$unitdir/specter.service.d/10-raspiblitz-rpc.conf" ]
  ! grep -q restart "$calls"
}

@test "application update reloads the migration before its normal restart" {
  run bash "$BATS_TEST_TMPDIR/installer" update
  [ "$status" -eq 0 ]
  [ "$(cat "$calls")" = "$(printf '%s\n' show daemon-reload restart)" ]
}

@test "a failed migration aborts the update before restarting and can be retried" {
  export FAIL_RELOAD=1
  run bash "$BATS_TEST_TMPDIR/installer" update
  [ "$status" -ne 0 ]
  ! grep -q restart "$calls"
  unset FAIL_RELOAD
  run bash "$BATS_TEST_TMPDIR/installer" update
  [ "$status" -eq 0 ]
  [ "$(grep -cx restart "$calls")" -eq 1 ]
}

@test "reprovision retries a previously running daemon after its restart failed" {
  export FAIL_RESTART=1
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -ne 0 ]
  unset FAIL_RESTART
  export INACTIVE=1
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -eq 0 ]
  [ "$(grep -cx restart "$calls")" -eq 2 ]
  [ "$(grep -cx daemon-reload "$calls")" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/restart-pending" ]
}

@test "reprovision preserves an intentionally inactive daemon" {
  export INACTIVE=1
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -eq 0 ]
  ! grep -q '^restart$' "$calls"
  [ ! -e "$BATS_TEST_TMPDIR/restart-pending" ]
}
