#!/usr/bin/env bats

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR"
  mkdir -p "$FIXTURE/hdd/app-data" "$FIXTURE/inspect" "$FIXTURE/bin" "$FIXTURE/nm"
  sed -e "s|/mnt/hdd|$FIXTURE/hdd|g" -e "s|/var/cache/raspiblitz/hdd-inspect|$FIXTURE/inspect|g" \
    -e "s|/etc/NetworkManager/system-connections|$FIXTURE/nm|g" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/internet.wifi.sh" > "$FIXTURE/wifi.sh"
  printf '#!/bin/sh\nexec "$@"\n' > "$FIXTURE/bin/sudo"
  cat > "$FIXTURE/bin/nmcli" <<'SH'
#!/bin/sh
case "$*" in *'device status') printf '%s\n' "${TEST_DEVICE_STATE:-wifi:disconnected}";; esac
SH
  printf '#!/bin/sh\nexit 0\n' > "$FIXTURE/bin/ip"
  cp "$FIXTURE/bin/ip" "$FIXTURE/bin/sleep"
  cp "$FIXTURE/bin/ip" "$FIXTURE/bin/systemctl"
  chmod +x "$FIXTURE"/bin/*
  PATH="$FIXTURE/bin:$PATH"
}

@test "legacy-only backup gives actionable guidance without disclosing or deleting credentials" {
  echo 'psk="FixtureOnly123"' > "$FIXTURE/hdd/app-data/wpa_supplicant.conf"
  run bash "$FIXTURE/wifi.sh" backup-restore
  [ "$status" = 0 ]
  [[ "$output" == *wifiRestoreNeedsSetup=1* && "$output" == *'sudo nmtui'* ]]
  [[ "$output" == *wifiRestore=0* && "$output" != *FixtureOnly123* ]]
  grep -Fq FixtureOnly123 "$FIXTURE/hdd/app-data/wpa_supplicant.conf"
}

@test "early inspection marker works before DATA is mounted" {
  rmdir "$FIXTURE/hdd/app-data"
  touch "$FIXTURE/inspect/legacy-wifi"
  run bash "$FIXTURE/wifi.sh" backup-restore
  [ "$status" = 0 ]
  [[ "$output" == *wifiRestoreNeedsSetup=1* ]]
}

@test "modern keyfile restored privately with association status reported separately" {
  mkdir "$FIXTURE/hdd/app-data/wifi"
  echo '[connection]' > "$FIXTURE/hdd/app-data/wifi/fixture.nmconnection"
  touch "$FIXTURE/inspect/legacy-wifi"
  run bash "$FIXTURE/wifi.sh" backup-restore
  [ "$status" = 0 ]
  [[ "$output" == *wifiRestore=1* && "$output" == *wifiActive=0* && "$output" != *wifiRestoreNeedsSetup* ]]
  [ "$(stat -c %a "$FIXTURE/nm/fixture.nmconnection")" = 600 ]
  export TEST_DEVICE_STATE=wifi:connected
  run bash "$FIXTURE/wifi.sh" backup-restore
  [[ "$output" == *wifiActive=1* ]]
}
