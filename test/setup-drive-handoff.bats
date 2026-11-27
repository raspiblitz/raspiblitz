#!/usr/bin/env bats

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR"
  export setupFile="$FIXTURE/raspiblitz.setup" logFile="$FIXTURE/log"
  export state=waitprovision scenario=setup scenarioSystemCopy=1
  mkdir -p "$FIXTURE/admin/config.scripts" "$FIXTURE/bin"
  # Exercise the running bootstrap's wait, retry and selection code, stopping
  # before its first drive command. The cache and disk inspector are fixtures.
  sed -n '/^  echo "state(${state})"/,/^  # even when the user decided/{p; /^  # even when the user decided/q;}' \
    "$BATS_TEST_DIRNAME/../home.admin/_bootstrap.sh" |
    sed "s|/home/admin|$FIXTURE/admin|g" > "$FIXTURE/handoff"
  printf '\nprintf "selected=%%s\\n" "$setupCommand"\n' >> "$FIXTURE/handoff"
  printf '#!/bin/sh\nexit 0\n' > "$FIXTURE/admin/config.scripts/blitz.data.sh"
  cat > "$FIXTURE/admin/_cache.sh" <<'SH'
#!/bin/sh
case "$1:$2" in
  set:state) printf '%s\n' "$3" >> "$FIXTURE/states";;
  get:state)
    if [ ! -f "$FIXTURE/retry" ]; then exit 1; fi
    mv "$FIXTURE/retry" "$setupFile"
    echo state=waitprovision;;
esac
SH
  printf '#!/bin/sh\nexit 0\n' > "$FIXTURE/bin/sleep"
  chmod +x "$FIXTURE/admin/_cache.sh" "$FIXTURE/admin/config.scripts/blitz.data.sh" "$FIXTURE/bin/sleep"
  PATH="$FIXTURE/bin:$PATH"
}

@test "omitted web choice retries before storage and accepts a corrected choice" {
  printf 'formatHDD=1\ncleanHDD=0\n' > "$setupFile"
  printf 'systemCopy=0\ndeleteData=keepBlockchain\n' > "$FIXTURE/retry"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [ "$(cat "$FIXTURE/states")" = waitsetup ]
  [[ "$output" == *selected=clean* ]]
}

@test "old API handoff is ignored until the operator resubmits via a matching UI" {
  printf 'systemCopy=0\ndeleteData=all\n' > "$FIXTURE/legacy"
  printf 'systemCopy=0\ndeleteData=keepBlockchain\n' > "$FIXTURE/retry"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [ "$(cat "$FIXTURE/states")" = waitsetup ]
  [[ "$output" == *selected=clean* ]]
  [ -f "$FIXTURE/legacy" ]
}

@test "SSH can omit systemCopy when the installer did not offer it" {
  export scenarioSystemCopy=0
  echo deleteData=all > "$setupFile"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [[ "$output" == *selected=setup* ]]
  [ ! -f "$FIXTURE/states" ]
}

@test "ordinary recovery and reboot after system copy keep their existing commands" {
  export scenario=recover
  : > "$setupFile"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [[ "$output" == *selected=recover* ]]
  echo systemCopy=done > "$setupFile"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [[ "$output" == *selected=skip* ]]
}
