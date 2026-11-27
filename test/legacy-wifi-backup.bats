#!/usr/bin/env bats

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR"
  mkdir -p "$FIXTURE/hdd/app-data" "$FIXTURE/inspect" "$FIXTURE/bin" "$FIXTURE/nm"
  sed "s|/etc/NetworkManager/system-connections|$FIXTURE/nm|g" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/internet.wifi.restore.py" > "$FIXTURE/restore.py"
  sed -e "s|/home/admin/config.scripts/internet.wifi.restore.py|$FIXTURE/restore.py|g" \
    -e "s|/mnt/hdd|$FIXTURE/hdd|g" -e "s|/var/cache/raspiblitz/hdd-inspect|$FIXTURE/inspect|g" \
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


@test "a partially published set is replayed only from the matching original backup" {
  python3 - "$FIXTURE" <<'PY'
import importlib.util
import os
import sys
from pathlib import Path
from unittest.mock import patch

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("restore", root / "restore.py")
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)
source = root / "profiles"
source.mkdir()
for name in ("a", "b"):
    (source / name).write_text(name)
target = root / "nm"
replace = os.replace
def interrupt(source, destination):
    if Path(destination).name == "b":
        raise OSError("synthetic interrupted write")
    return replace(source, destination)
try:
    with patch.object(restore.os, "replace", side_effect=interrupt):
        restore.restore_profiles(source, target)
except OSError:
    pass
assert (target / "a").read_text() == "a"
assert not (target / "b").exists()
assert (target / ".raspiblitz-restore-pending").is_file()
(source / "b").write_text("another backup")
try:
    restore.restore_profiles(source, target)
except ValueError:
    pass
assert not (target / "b").exists()
(source / "b").write_text("b")
restore.restore_profiles(source, target)
assert (target / "a").read_text() == "a" and (target / "b").read_text() == "b"
assert not (target / ".raspiblitz-restore-pending").exists()
PY
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


@test "invalid profile link aborts before installing any entry" {
  mkdir "$FIXTURE/hdd/app-data/wifi"
  echo '[connection]' > "$FIXTURE/hdd/app-data/wifi/a.nmconnection"
  echo 'outside fixture' > "$FIXTURE/outside"
  ln -s "$FIXTURE/outside" "$FIXTURE/hdd/app-data/wifi/z.nmconnection"
  run bash "$FIXTURE/wifi.sh" backup-restore
  [ "$status" -ne 0 ]
  [ -z "$(ls -A "$FIXTURE/nm")" ]
  grep -Fxq 'outside fixture' "$FIXTURE/outside"
}
