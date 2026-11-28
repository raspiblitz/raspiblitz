#!/usr/bin/env bats

setup() {
  [ "$(id -u)" -ne 0 ] || skip "run with the unprivileged PATCH account"
  work=$(mktemp -d /var/tmp/raspiblitz-lndlibs-test-XXXXXXXX)
  cd "$work"
  # The running updater carries its own handoff, even for an older checkout.
  helper="$work/embedded-helper.py"
  sed -n "/<<'PYTHON_CACHE_HANDOFF'/,/^PYTHON_CACHE_HANDOFF$/p" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.github.sh" | sed '1d;$d' >"$helper"
  [ -s "$helper" ]
  mkdir -p staged/lndlibs live/lndlibs
  touch live/lndlibs/"${work##*/}"
  printf 'value="old"\n' >live/lndlibs/example.py
  printf 'value="new"\n' >staged/lndlibs/example.py
  touch -r live/lndlibs/example.py staged/lndlibs/example.py
}

teardown() {
  [ -n "${work:-}" ] || return 0
  if [[ ${retired:-} = /var/tmp/raspiblitz-retired-lndlibs-* && -e "$retired/lndlibs/${work##*/}" ]]; then
    chmod -R u+rwX "$retired"
    rm -r -- "$retired"
  fi
  chmod -R u+rwX "$work"
  rm -r -- "$work"
}

make_cache() {
  (cd live && python3 -c 'from lndlibs.example import value; assert value == "old"')
  chmod 0555 live/lndlibs/__pycache__
}

publish() {
  run /usr/bin/python3 -I "$helper" "$work/staged" "$work/live"
  retired=$(sed -n 's/^Retired previous lndlibs under //p' <<<"$output")
}

@test "an unremovable warm cache is exchanged for fresh same-size same-mtime source" {
  make_cache
  mkdir staged/lndlibs/__pycache__
  cp live/lndlibs/__pycache__/*.pyc staged/lndlibs/__pycache__/
  publish
  [ "$status" -eq 0 ]
  [[ "$output" = *replaced ]]
  [ "$(stat -c %a "$retired")" = 700 ]
  [ -d "$retired/lndlibs/__pycache__" ]
  [ ! -e live/lndlibs/__pycache__ ]
  (cd live && python3 -c 'from lndlibs.example import value; assert value == "new"')
  run /usr/bin/python3 -I "$helper" "$work/staged" "$work/live"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "removing the library in the selected branch retires an unremovable cache with it" {
  make_cache
  rm -r staged/lndlibs
  publish
  [ "$status" -eq 0 ]
  [[ "$output" = *replaced ]]
  [ ! -e live/lndlibs ]
  [ -f "$retired/lndlibs/example.py" ]
}

@test "ordinary updates use normal rsync while symlinked script or library directories fail closed" {
  publish
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  mv live normal
  ln -s normal live
  publish
  [ "$status" -ne 0 ]
  [ -f normal/lndlibs/example.py ]
  rm live
  mkdir live
  ln -s ../normal/lndlibs live/lndlibs
  publish
  [ "$status" -ne 0 ]
  [ -f normal/lndlibs/example.py ]
}

@test "a symlinked incoming library is rejected before the no-cache fast path" {
  mv staged/lndlibs source
  ln -s ../source staged/lndlibs
  publish
  [ "$status" -ne 0 ]
  [ "$(cat live/lndlibs/example.py)" = 'value="old"' ]
}

@test "two PATCH operations cannot publish concurrently" {
  mkdir admin
  sed -e "s|/home/admin|$work/admin|g" -e 's|/mnt/hdd/app-data/raspiblitz.conf|/dev/null|g' \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.github.sh" > updater
  exec 8<admin
  flock -n 8
  run bash updater -run
  [ "$status" -eq 1 ]
  [[ "$output" = *"Another script update is running"* ]]
  exec 8<&-
}
