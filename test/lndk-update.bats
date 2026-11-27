#!/usr/bin/env bats

setup() {
  admin="$BATS_TEST_DIRNAME/../home.admin"
  export calls="$BATS_TEST_TMPDIR/calls" TERM=dumb
  mkdir -p "$BATS_TEST_TMPDIR/admin/config.scripts" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/units"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  touch "$calls" "$BATS_TEST_TMPDIR/admin/raspiblitz.info"
  printf '%s\n' '#!/bin/sh' 'echo state=ready' >"$BATS_TEST_TMPDIR/admin/_cache.sh"
  printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$calls"' >"$BATS_TEST_TMPDIR/admin/config.scripts/blitz.conf.sh"
  printf '%s\n' '#!/bin/sh' 'if [ "$1" = -u ]; then shift 2; fi' 'exec "$@"' >"$BATS_TEST_TMPDIR/bin/sudo"
  printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$calls"' >"$BATS_TEST_TMPDIR/bin/systemctl"
  printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$calls"' >"$BATS_TEST_TMPDIR/bin/whiptail"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$BATS_TEST_TMPDIR/bin/lndk"
  cp "$BATS_TEST_TMPDIR/bin/lndk" "$BATS_TEST_TMPDIR/bin/lndk-cli"
  chmod +x "$BATS_TEST_TMPDIR"/bin/* "$BATS_TEST_TMPDIR/admin/_cache.sh" "$BATS_TEST_TMPDIR/admin/config.scripts/blitz.conf.sh"
  sed -e "s|/etc/systemd/system|$BATS_TEST_TMPDIR/units|g" -e "s|/home/admin|$BATS_TEST_TMPDIR/admin|g" \
    -e "s|/usr/local/bin|$BATS_TEST_TMPDIR/bin|g" "$admin/config.scripts/bonus.lndk.sh" > "$BATS_TEST_TMPDIR/installer"
  unit="$BATS_TEST_TMPDIR/units/lndk.service"
}

@test "an existing legacy unit requires the explicit keep-data upgrade" {
  echo '[Unit]' > "$unit"
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -ne 0 ]
  [[ "$output" == *"choose Keep Data"* ]]
  [ ! -s "$calls" ]
  [ "$(cat "$unit")" = '[Unit]' ]
}

@test "a current unit with both binaries can be enabled again without a rebuild" {
  echo '# RaspiBlitz LNDK v0.3.0' > "$unit"
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -eq 0 ]
  grep -Fx 'enable lndk' "$calls"
  grep -Fx 'start lndk' "$calls"
  grep -Fx 'set lndk on' "$calls"
  rm "$BATS_TEST_TMPDIR/bin/lndk-cli"
  : > "$calls"
  run bash "$BATS_TEST_TMPDIR/installer" on
  [ "$status" -ne 0 ]
  [ ! -s "$calls" ]
}

@test "service-menu action reports a failed install and confirms a successful install" {
  # Run the LNDK dispatch with controlled installer results.
  sed -n '/^# LNDK$/,/^# JoinMarket process choice/p' "$admin/00settingsMenuServices.sh" |
    sed "s|/home/admin|$BATS_TEST_TMPDIR/admin|g" > "$BATS_TEST_TMPDIR/menu"
  printf '%s\n' '#!/bin/sh' 'exit "$outcome"' > "$BATS_TEST_TMPDIR/admin/config.scripts/bonus.lndk.sh"
  chmod +x "$BATS_TEST_TMPDIR/admin/config.scripts/bonus.lndk.sh"
  export lndk=off CHOICES=lb outcome=1
  run bash "$BATS_TEST_TMPDIR/menu"
  grep -F 'Could not turn LNDK on' "$calls"
  run grep -Fq 'LNDK was installed' "$calls"
  [ "$status" -eq 1 ]
  : > "$calls"
  export outcome=0
  run bash "$BATS_TEST_TMPDIR/menu"
  grep -F 'LNDK was installed' "$calls"
}

@test "provision restores only an enabled LNDK with LND and records installer failure" {
  sed -n '/^# LNDK$/,/^# helipad$/p' "$admin/_provision_.sh" |
    sed "s|/home/admin|$BATS_TEST_TMPDIR/admin|g" > "$BATS_TEST_TMPDIR/provision"
  printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$calls"' 'exit 1' > "$BATS_TEST_TMPDIR/admin/config.scripts/bonus.lndk.sh"
  chmod +x "$BATS_TEST_TMPDIR/admin/config.scripts/bonus.lndk.sh"
  export lndk=off lnd=on logFile="$BATS_TEST_TMPDIR/log"
  run bash "$BATS_TEST_TMPDIR/provision"
  [ ! -s "$calls" ]
  export lndk=on lnd=off lightning=cl
  run bash "$BATS_TEST_TMPDIR/provision"
  [ ! -s "$calls" ]
  export lightning=lnd
  run bash "$BATS_TEST_TMPDIR/provision"
  grep -Fx on "$calls"
  grep -F 'LNDK setup failed' "$logFile"
}
