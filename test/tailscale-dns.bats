#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_TMPDIR:$PATH" calls="$BATS_TEST_TMPDIR/calls" state=Running
  printf '#!/bin/sh\nexec "$@"\n' >"$BATS_TEST_TMPDIR/sudo"
  cat >"$BATS_TEST_TMPDIR/tailscale" <<'SH'
#!/bin/sh
echo "$*" >>"$calls"
case "$1" in
  status) printf '{"BackendState":"%s","User":{}}\n' "$state" ;;
  set) exit "${set_rc:-0}" ;;
  *) exit 2 ;;
esac
SH
  cat >"$BATS_TEST_TMPDIR/whiptail" <<'SH'
#!/bin/sh
case "$*" in
  *--menu*) [ "$choice" != BACK ] || exit 1; echo "$choice" >&2 ;;
  *) echo "$*" >>"$calls" ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/sudo" "$BATS_TEST_TMPDIR/tailscale" "$BATS_TEST_TMPDIR/whiptail"
  menu="$BATS_TEST_DIRNAME/../home.admin/config.scripts/internet.tailscale.sh"
}

@test "the running VPN keeps other preferences while switching DNS in either direction" {
  for pair in LOCAL:false TAILNET:true; do
    : >"$calls"
    export choice=${pair%:*}
    run sh "$menu" menu
    [ "$status" -eq 0 ]
    [ "$(grep '^set ' "$calls")" = "set --accept-dns=${pair#*:}" ]
  done
  ! grep -Eq '^(up|down|logout|login)' "$calls"
}

@test "back, keep and a stopped backend preserve preferences" {
  for choice in BACK KEEP; do
    export choice
    run sh "$menu" menu
    [ "$status" -eq 0 ]
  done
  export state=Stopped choice=LOCAL
  run sh "$menu" menu
  [ "$status" -eq 0 ]
  ! grep -q '^set ' "$calls"
}

@test "a failed DNS change reports an error" {
  export choice=LOCAL set_rc=1
  run sh "$menu" menu
  [ "$status" -eq 1 ]
  grep -q 'Could not change' "$calls"
}
