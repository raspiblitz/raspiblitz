#!/usr/bin/env bats

setup() {
  root="$BATS_TEST_TMPDIR"
  mkdir -p "$root/helpers" "$root/bin" "$root/disk_data/app-data"
  conf="$root/disk_data/app-data/raspiblitz.conf"
  printf '%s\n' '# Existing node settings' > "$conf"
  setupFile="$root/setup"
  : > "$setupFile"
  export PATH="$root/bin:$PATH"
  cat > "$root/bin/findmnt" <<EOF
#!/bin/sh
case "\$*" in
  *"output FSROOT"*) echo / ;;
  *"output SOURCE"*) echo /dev/fixture ;;
  *) echo "$root/disk_data" ;;
esac
EOF
  printf '#!/bin/sh\necho "%s"\n' "$(stat -c '%Hd:%Ld' "$conf")" > "$root/bin/lsblk"
  printf '#!/bin/sh\necho "$2" >&2\n' > "$root/helpers/blitz.error.sh"
  printf '#!/bin/sh\nexec "$@"\n' > "$root/bin/sudo"
  printf '#!/bin/sh\nexit 0\n' > "$root/cache"
  src="$BATS_TEST_DIRNAME/../home.admin"
  sed "s|/home/admin/_cache.sh|$root/cache|g" "$src/config.scripts/blitz.conf.sh" > "$root/helpers/blitz.conf.sh"
  chmod +x "$root/bin/"* "$root/helpers/"* "$root/cache"
  # Exercise the release precheck and config writer without starting migration.
  sed -n '/^# check if config file exists/,/^# check if config files contain lightning/p' \
    "$src/_provision.update.sh" | sed "s|/home/admin/config.scripts|$root/helpers|g; s|/mnt/disk_data|$root/disk_data|g" > "$root/precheck"
}

precheck() {
  configFile="$conf" logFile="$root/log" bash -c 'source "$1"; source "$2"' -- "$setupFile" "$root/precheck"
}

@test "mounted DATA retains the saved hostname and other settings" {
  printf "hostname='existing'\nlnd=on\n" >> "$conf"
  echo "hostname=other" > "$setupFile"
  cp "$conf" "$root/original"
  run precheck
  [ "$status" -eq 0 ]
  cmp "$conf" "$root/original"
}

@test "a missing or empty saved hostname is actually persisted" {
  echo 'hostname=' >> "$conf"
  echo 'hostname=existing-node' > "$setupFile"
  run precheck
  [ "$status" -eq 0 ]
  grep -Fx "hostname='existing-node'" "$conf"
  : > "$setupFile"
  echo 'cl=on' > "$conf"
  run precheck
  [ "$status" -eq 0 ]
  grep -Fx "hostname='raspiblitz'" "$conf"
  grep -Fx 'cl=on' "$conf"
}

@test "a missing config or a stale copy on SYSTEM blocks upgrade writes" {
  rm "$conf"
  run precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *missing-config* ]]
  echo 'lnd=on' > "$conf"
  printf '#!/bin/sh\necho /\n' > "$root/bin/findmnt"
  run precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *data-not-mounted* ]]
  [ "$(cat "$conf")" = 'lnd=on' ]
  printf '#!/bin/sh\necho /var\n' > "$root/bin/findmnt"
  run precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *data-not-mounted* ]]
}

@test "a failed write stops migration and identifies the hostname failure" {
  printf '#!/bin/sh\nexit 1\n' > "$root/helpers/blitz.conf.sh"
  run precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *missing-hostname* ]]
}

@test "a config link escaping the DATA directory is refused" {
  echo 'lnd=on' > "$root/outside"
  ln -sf "$root/outside" "$conf"
  run precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *data-not-mounted* ]]
  [ "$(cat "$root/outside")" = 'lnd=on' ]
}

@test "a different device mounted at the correct path is refused" {
  printf '#!/bin/sh\necho 99:1234\n' > "$root/bin/lsblk"
  run precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *wrong-data-device* ]]
  [ "$(cat "$conf")" = '# Existing node settings' ]
}
