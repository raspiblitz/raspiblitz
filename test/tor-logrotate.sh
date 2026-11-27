#!/usr/bin/env bash
# Debian integration check for the logrotate policy shipped with RaspiBlitz.
# Run as root with logrotate and the Debian Tor package installed.
set -euo pipefail
policy=$(cd "$(dirname "$0")/../home.admin/assets" && pwd)/raspiblitz-tor.logrotate
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
chmod 0755 "$work"
install -d -o debian-tor -g debian-tor -m 0700 "$work/logs"
mkdir "$work/bin"
export RELOAD_TRACE="$work/service-calls"
export TEST_SERVICE_STATE=active
cat >"$work/bin/systemctl" <<'STUB'
#!/bin/sh
case "$*" in
  'is-active --quiet tor@default.service') test "$TEST_SERVICE_STATE" = active ;;
  'reload tor@default.service') echo reload >> "$RELOAD_TRACE" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$work/bin/systemctl"
export PATH="$work/bin:$PATH"
sed "s|/mnt/hdd/app-data/tor/|$work/logs/|" "$policy" >"$work/policy"
# build_sdcard.sh sets copytruncate globally. The Tor rule must override it.
printf 'copytruncate\ninclude %s\n' "$work/policy" >"$work/logrotate.conf"
rotate() { logrotate --state "$work/state" "$work/logrotate.conf"; }

rotate  # no log files yet
touch "$work/logs/notice.log" "$work/logs/info.log"
rotate
test ! -e "$RELOAD_TRACE"
for round in 1 2 3; do
  for name in info notice; do
    printf 'round %s\n' "$round" >"$work/logs/$name.log"
    truncate -s 104857601 "$work/logs/$name.log"
  done
  rotate
  for name in info notice; do
    test -f "$work/logs/$name.log.1"
    test ! -s "$work/logs/$name.log"
    test "$(stat -c '%a:%U:%G' "$work/logs/$name.log")" = 640:debian-tor:debian-tor
  done
done
test "$(wc -l <"$RELOAD_TRACE")" -eq 3
gzip -t "$work/logs/info.log.2.gz" "$work/logs/notice.log.2.gz"
test ! -e "$work/logs/info.log.3.gz"
test ! -e "$work/logs/notice.log.3.gz"
TEST_SERVICE_STATE=inactive
truncate -s 104857601 "$work/logs/info.log"
rotate
test "$(wc -l <"$RELOAD_TRACE")" -eq 3
echo 'Tor log rotation passed: missing, empty, size, ownership, retention and reload.'
