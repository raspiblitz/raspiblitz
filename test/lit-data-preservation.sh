#!/usr/bin/env bash
# On a disposable RaspiBlitz guest without a LiT user/service, exercise the
# real service removal path using synthetic custody files, never live assets.
set -euo pipefail
if [[ ${1:-} != --private ]]; then exec unshare --mount --propagation private /bin/bash "$0" --private "$@"; fi
shift
script=$(realpath "${1:?path to candidate bonus.lit.sh required}")
[[ $(id -u) == 0 && ! -e /etc/systemd/system/litd.service && ! -e /home/lit ]]
if id lit >/dev/null 2>&1; then echo 'Requires a fresh disposable guest'; exit 1; fi
mount -t tmpfs tmpfs /mnt
mkdir /mnt/hdd
mount -t tmpfs tmpfs /mnt/hdd
mkdir /mnt/hdd/app-data
echo 'runBehindTor=off' >/mnt/hdd/app-data/raspiblitz.conf
work=$(mktemp -d /.rb-lit-test.XXXXXXXX); chmod 700 "$work"
cleanup() {
  if id lit >/dev/null 2>&1; then userdel -r lit 2>/dev/null || true; fi
  rm -rf -- "$work"
}
trap cleanup EXIT
add_lit() { useradd --system --user-group --create-home --home-dir /home/lit lit; }
add_lit
source_dir=/home/lit/.tapd
data_dir=/mnt/hdd/app-data/.tapd
install -d -o lit -g lit -m 700 "$source_dir"
printf 'synthetic proof record\n' >"$source_dir/custody.fixture"
first=$(sha256sum <"$source_dir/custody.fixture")
# A stale config on the root disk is insufficient evidence of mounted storage.
mkdir "$work/false-data"
touch "$work/false-data/raspiblitz.conf"
mount --bind "$work/false-data" /mnt/hdd/app-data
if bash "$script" off >"$work/off-no-drive.log" 2>&1; then echo 'OS disk unexpectedly accepted'; exit 1; fi
umount /mnt/hdd/app-data
[[ $(sha256sum <"$source_dir/custody.fixture") == "$first" ]]
# Exercise conflict handling before giving the script a clean destination.
mkdir "$data_dir"
printf 'independent state\n' >"$data_dir/other.fixture"
if bash "$script" off >"$work/off-conflict.log" 2>&1; then echo 'Conflict unexpectedly accepted'; exit 1; fi
id lit >/dev/null
[[ $(sha256sum <"$source_dir/custody.fixture") == "$first" && -s "$data_dir/other.fixture" ]]
mv "$data_dir" "$work/conflicting-copy"
bash "$script" off >"$work/off.log" 2>&1
if id lit >/dev/null 2>&1; then echo 'Service user was not removed'; exit 1; fi
[[ $(sha256sum <"$data_dir/custody.fixture") == "$first" && ! -e /home/lit ]]
add_lit
# After re-creating the service account, a second removal must keep the same data.
bash "$script" off >"$work/off-again.log" 2>&1
[[ $(sha256sum <"$data_dir/custody.fixture") == "$first" && ! -e /home/lit ]]
echo 'PASS existing sources conflict safely; both removals preserve exact synthetic .tapd custody data.'
# Drive the regular local SSH info screen through a terminal and capture it.
TERM=xterm timeout 25 script -qefc "stty rows 32 cols 90; bash '$script' menu" "$work/dialog" < <(for _ in {1..15}; do sleep 1; printf '\r'; done) >/dev/null
for word in 'Password C' 'Password B'; do grep -aFq "$word" "$work/dialog"; done
echo 'PASS rendered terminal login instructions include LND Password C and Lightning Terminal Password B.'
