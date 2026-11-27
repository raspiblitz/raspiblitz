#!/usr/bin/env bats

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR"
  export setupFile="$FIXTURE/raspiblitz.setup" logFile="$FIXTURE/log"
  export state=waitprovision scenario=setup scenarioSystemCopy=1 confirmedDriveInventory=fixture-id
  export FIXTURE_SCENARIO=setup
  mkdir -p "$FIXTURE/admin/config.scripts" "$FIXTURE/bin" "$FIXTURE/admin/setup.scripts"
  cp "$BATS_TEST_DIRNAME/../home.admin/setup.scripts/readSetup.sh" "$FIXTURE/admin/setup.scripts/"
  # Exercise the running bootstrap's wait, retry and selection code, stopping
  # before its first drive command. The cache and disk inspector are fixtures.
  sed -n '/^  echo "state(${state})"/,/^  # even when the user decided/{p; /^  # even when the user decided/q;}' \
    "$BATS_TEST_DIRNAME/../home.admin/_bootstrap.sh" |
    sed -e "s|/home/admin|$FIXTURE/admin|g" -e "s|/root|$FIXTURE|g" -e "s|/run/raspiblitz-setup/request/raspiblitz.setup|$FIXTURE/request|g" > "$FIXTURE/handoff"
  printf '\nprintf "selected=%%s\\n" "$setupCommand"\n' >> "$FIXTURE/handoff"
  printf '#!/bin/sh\necho "scenario=$FIXTURE_SCENARIO"\necho "setupDriveIdentity=${FIXTURE_INVENTORY:-fixture-id}"\n' > "$FIXTURE/admin/config.scripts/blitz.data.sh"
  cat > "$FIXTURE/admin/_cache.sh" <<'SH'
#!/bin/sh
case "$1:$2" in
  set:state) printf '%s\n' "$3" >> "$FIXTURE/states";;
  get:state)
    if [ ! -f "$FIXTURE/retry" ]; then exit 1; fi
    mv "$FIXTURE/retry" "$FIXTURE/request"
    echo state=waitprovision;;
esac
SH
  cat > "$FIXTURE/admin/setup.scripts/freezeSetup.py" <<'PY'
import pathlib, shutil, sys
request, accepted = map(pathlib.Path, sys.argv[1:])
if not request.is_file():
    sys.exit(1)
shutil.copyfile(request, accepted)
PY
  printf '#!/bin/sh\nexit 0\n' > "$FIXTURE/bin/sleep"
  chmod +x "$FIXTURE/admin/_cache.sh" "$FIXTURE/admin/config.scripts/blitz.data.sh" "$FIXTURE/bin/sleep"
  PATH="$FIXTURE/bin:$PATH"
}

@test "omitted web choice retries before storage and accepts a corrected choice" {
  printf 'formatHDD=1\ncleanHDD=0\n' > "$FIXTURE/request"
  printf 'passwordA=Fixture-A\nsystemCopy=0\ndeleteData=keepBlockchain\n' > "$FIXTURE/retry"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [ "$(cat "$FIXTURE/states")" = waitsetup ]
  [[ "$output" == *selected=clean* ]]
}

@test "old API handoff is ignored until the operator resubmits via a matching UI" {
  printf 'passwordA=Fixture-A\nsystemCopy=0\ndeleteData=all\n' > "$FIXTURE/legacy"
  printf 'passwordA=Fixture-A\nsystemCopy=0\ndeleteData=keepBlockchain\n' > "$FIXTURE/retry"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [ "$(cat "$FIXTURE/states")" = waitsetup ]
  [[ "$output" == *selected=clean* ]]
  [ -f "$FIXTURE/legacy" ]
}

@test "SSH can omit systemCopy when the installer did not offer it" {
  export scenarioSystemCopy=0
  printf 'passwordA=Fixture-A\ndeleteData=all\n' > "$FIXTURE/request"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [[ "$output" == *selected=setup* ]]
  [ ! -f "$FIXTURE/states" ]
}

@test "ordinary recovery and reboot after system copy keep their existing commands" {
  export scenario=recover FIXTURE_SCENARIO=recover
  echo passwordA=Fixture-A > "$FIXTURE/request"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [[ "$output" == *selected=recover* ]]
  export resumeFromCopiedSystem=1
  printf 'passwordA=Fixture-A\nsystemCopy=done\n' > "$setupFile"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [[ "$output" == *selected=skip* ]]
}


@test "replaced drive inventory stops before selecting a disk action" {
  export FIXTURE_INVENTORY=changed-disk
  printf 'passwordA=Fixture-A\nsystemCopy=0\ndeleteData=all\n' > "$FIXTURE/request"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 1 ]
  [ "$(cat "$FIXTURE/states")" = error ]
  [[ "$output" != *selected=setup* ]]
}


@test "rejecting a saved checkpoint accepts the next UI submission" {
  export resumeFromCopiedSystem=1
  printf 'systemCopy=done\n' > "$setupFile"
  cp "$setupFile" "$FIXTURE/.raspiblitz-setup-resume"
  printf 'passwordA=Fixture-A\nsystemCopy=0\ndeleteData=keepBlockchain\n' > "$FIXTURE/retry"
  run timeout 4 bash "$FIXTURE/handoff"
  [ "$status" = 0 ]
  [ "$(cat "$FIXTURE/states")" = waitsetup ]
  [ ! -e "$FIXTURE/.raspiblitz-setup-resume" ]
  [[ "$output" == *selected=clean* ]]
}
