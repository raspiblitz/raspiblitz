#!/usr/bin/env bats

setup() {
  source <(sed '/^# command info$/q' "$BATS_TEST_DIRNAME/../home.admin/config.scripts/bonus.lnbits.sh")
  previousCommit=$tagCommit
  previousActive=1
  beforeCheckout=1
  gitHead=$previousCommit
  fakeChanges=""
  runtime=1.7.1
  unitCommand="{ path=$lnbitsBin ; argv[]=$lnbitsBin --port 5000 ; }"
  transfer=0
  fakeResponse=$'{"server_time":1,"up_time":2}\n200'
  active=0
  systemctl() {
    if [ "$1" = show ]; then echo "$unitCommand"; else return "$active"; fi
  }
  curl() { printf '%s' "$fakeResponse"; return "$transfer"; }
  sudo() {
    case "$*" in
      *'rev-parse HEAD') printf '%s\n' "$gitHead" ;;
      *'status --porcelain') printf '%s' "$fakeChanges" ;;
      *'importlib.metadata'*) printf '%s\n' "$runtime" ;;
      *) return 1 ;;
    esac
  }
}

@test "only an active verified runtime before checkout may be explicitly resumed" {
  run previousLnbitsIsSafe; [ "$status" = 0 ]
  for condition in inactive mutated unrelated dirty runtime unit old v170; do
    run bash_check_previous "$condition"
    [ "$status" != 0 ]
  done
}

bash_check_previous() {
  case "$1" in
    inactive) previousActive=0 ;;
    mutated) beforeCheckout=0 ;;
    unrelated) gitHead=abcdef ;;
    dirty) fakeChanges=' M tracked-file' ;;
    runtime) runtime=1.2.1 ;;
    unit) unitCommand='{ path=/usr/bin/poetry ; }' ;;
    old) previousCommit=unverified ;;
    v170) previousCommit=aaeff9a62a9310d9d14c22cc188bbd21c347577d; gitHead=$previousCommit; runtime=1.7.0 ;;
  esac
  previousLnbitsIsSafe
}

@test "health requires the local LNbits response, HTTP 200 and a complete transfer" {
  run lnbitsHealthy; [ "$status" = 0 ]
  for condition in inactive short missing redirect error html; do
    run bash_check_health "$condition"
    [ "$status" != 0 ]
  done
}

bash_check_health() {
  case "$1" in
    inactive) active=3 ;;
    short) transfer=18 ;; # a transport failure may still emit a complete JSON object
    missing) fakeResponse=$'{}\n200' ;;
    redirect) fakeResponse=$'{"server_time":1,"up_time":2}\n302' ;;
    error) fakeResponse=$'{"server_time":1,"up_time":2}\n500' ;;
    html) fakeResponse=$'<html>waiting</html>\n200' ;;
  esac
  lnbitsHealthy
}
