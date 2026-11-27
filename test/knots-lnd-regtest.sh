#!/usr/bin/env bash
# Run on a disposable Linux amd64 clone with curl, jq, gpg and tar.
# Uses an isolated regtest with no peers and removes all test wallet material.
set -euo pipefail
umask 077
work=$(mktemp -d)
cd "$work"
mkdir bitcoin lnd keys
export GNUPGHOME="$work/keys"
btcpid=''
lndpid=''
cleanup() {
  if [[ -n $lndpid ]]; then kill "$lndpid" 2>/dev/null || true; wait "$lndpid" || true; fi
  if [[ -n $btcpid ]]; then kill "$btcpid" 2>/dev/null || true; wait "$btcpid" || true; fi
  rm -rf -- "$work"
}
trap cleanup EXIT
get() { curl --retry 2 -fsSL "$1" -o "$2"; }
verified_by() {
  gpg --batch --status-fd=1 --verify "$1" "$2" >signer.status 2>/dev/null &&
    awk -v fp="$3" '$1=="[GNUPG:]" && $2=="VALIDSIG" && ($3==fp || $12==fp) {valid=1} END {exit !valid}' signer.status
}
check_file() {
  awk -v asset="$1" '$2==asset || $2=="*"asset {print; matches++} END {exit matches!=1}' "$2" | sha256sum -c -
}
knots=29.2.knots20251110
asset="bitcoin-${knots}-x86_64-linux-gnu.tar.gz"
base="https://bitcoinknots.org/files/29.x/$knots"
for file in "$asset" SHA256SUMS SHA256SUMS.asc; do get "$base/$file" "$file"; done
fingerprint=1A3E761F19D2CC7785C5502EA291A2C45D0C504A
get "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fingerprint" knots.key
gpg --batch --import knots.key 2>/dev/null
# The release includes independent builders. Require the expected builder in any position.
awk '/^-----BEGIN PGP SIGNATURE-----/ {part++; active=1} active {print > ("sig-"part".asc")} /^-----END PGP SIGNATURE-----/ {active=0}' SHA256SUMS.asc
verified=false
for signature in sig-*.asc; do
  if verified_by "$signature" SHA256SUMS "$fingerprint"; then verified=true; break; fi
done
"$verified" || { echo "Missing valid Knots builder signature" >&2; exit 1; }
check_file "$asset" SHA256SUMS
tar -xzf "$asset" "bitcoin-$knots/bin/bitcoind" "bitcoin-$knots/bin/bitcoin-cli"
bin="$work/bitcoin-$knots/bin"
release=v0.19.3-beta
name="lnd-linux-amd64-$release"
base="https://github.com/lightningnetwork/lnd/releases/download/$release"
for file in "$name.tar.gz" "manifest-$release.txt" "manifest-roasbeef-$release.sig"; do get "$base/$file" "$file"; done
get "https://raw.githubusercontent.com/lightningnetwork/lnd/$release/scripts/keys/roasbeef.asc" lnd.key
gpg --batch --import lnd.key 2>/dev/null
verified_by "manifest-roasbeef-$release.sig" "manifest-$release.txt" A5B61896952D9FDA83BC054CDC42612E89237182
check_file "$name.tar.gz" "manifest-$release.txt"
tar -xzf "$name.tar.gz" "$name/lnd" "$name/lncli"
"$bin/bitcoind" -version | head -1
"$name/lnd" --version
btc=("$bin/bitcoin-cli" -regtest "-datadir=$work/bitcoin" -rpcport=18143)
lncli=("$work/$name/lncli" "--lnddir=$work/lnd" -n regtest --rpcserver=127.0.0.1:18009)
"$bin/bitcoind" -regtest -listen=0 -connect=0 -dnsseed=0 "-datadir=$work/bitcoin" -rpcport=18143 -zmqpubrawblock=tcp://127.0.0.1:18332 -zmqpubrawtx=tcp://127.0.0.1:18333 >bitcoin.log 2>&1 &
btcpid=$!
"${btc[@]}" -rpcwait -rpcwaittimeout=60 getblockchaininfo >/dev/null
"${btc[@]}" createwallet miner >/dev/null
address=$("${btc[@]}" getnewaddress)
mine() { "${btc[@]}" generatetoaddress "$1" "$address" >/dev/null; }
mine 101
start_lnd() {
  local rpcuser rpcpass
  IFS=: read -r rpcuser rpcpass < bitcoin/regtest/.cookie || true
  "$name/lnd" "--lnddir=$work/lnd" --bitcoin.active --bitcoin.regtest --bitcoin.node=bitcoind --bitcoind.rpchost=127.0.0.1:18143 "--bitcoind.rpcuser=$rpcuser" "--bitcoind.rpcpass=$rpcpass" --bitcoind.zmqpubrawblock=tcp://127.0.0.1:18332 --bitcoind.zmqpubrawtx=tcp://127.0.0.1:18333 --rpclisten=127.0.0.1:18009 --restlisten=127.0.0.1:18080 --listen=127.0.0.1:18935 --noseedbackup >lnd.log 2>&1 &
  lndpid=$!
}
at_height() {
  for ((i=0; i<90; i++)); do
    if "${lncli[@]}" getinfo >info.json 2>/dev/null && jq -e --argjson h "$1" '.chains[0].network == "regtest" and .block_height == $h and .synced_to_chain' info.json >/dev/null; then return 0; fi
    if ! kill -0 "$lndpid"; then tail -5 lnd.log >&2; return 1; fi
    sleep 1
  done
  echo "LND did not reach height $1" >&2; return 1
}
start_lnd
at_height 101
identity=$(jq -er '.identity_pubkey | select(test("^(02|03)[a-f0-9]{64}$"))' info.json)
mine 2
at_height 103
"${lncli[@]}" stop >/dev/null
wait "$lndpid"; lndpid=
mine 1
start_lnd
at_height 104
[[ $(jq -r .identity_pubkey info.json) == "$identity" ]]
echo 'PASS Knots + LND: initial sync 101, live blocks to 103, same wallet catches up to 104 after restart.'
