#!/usr/bin/env bats

setup() {
  [ "$(id -u)" -ne 0 ] || skip "run with the unprivileged PATCH account"
  helper="$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.patch-lndlibs.py"
  work=$(mktemp -d /var/tmp/raspiblitz-lndlibs-test-XXXXXXXX)
  cd "$work"
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
  [ "$status" -eq 0 ] && [[ "$output" = *replaced ]]
  [ "$(stat -c %a "$retired")" = 700 ]
  [ -d "$retired/lndlibs/__pycache__" ] && [ ! -e live/lndlibs/__pycache__ ]
  (cd live && python3 -c 'from lndlibs.example import value; assert value == "new"')
  run /usr/bin/python3 -I "$helper" "$work/staged" "$work/live"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "removing the library in the selected branch retires an unremovable cache with it" {
  make_cache
  rm -r staged/lndlibs
  publish
  [ "$status" -eq 0 ] && [[ "$output" = *replaced ]]
  [ ! -e live/lndlibs ] && [ -f "$retired/lndlibs/example.py" ]
}

@test "ordinary updates use normal rsync while symlinked script or library directories fail closed" {
  publish
  [ "$status" -eq 0 ] && [ -z "$output" ]
  mv live normal
  ln -s normal live
  publish
  [ "$status" -ne 0 ] && [ -f normal/lndlibs/example.py ]
  rm live
  mkdir live
  ln -s ../normal/lndlibs live/lndlibs
  publish
  [ "$status" -ne 0 ] && [ -f normal/lndlibs/example.py ]
}
