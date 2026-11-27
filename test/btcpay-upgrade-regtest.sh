#!/usr/bin/env bash
# Disposable, local-only regtest on an otherwise idle Linux clone with Docker,
# Bitcoin Core (wallet support), curl and jq. Test data is removed on exit.
set -euo pipefail
umask 077
work=$(mktemp -d)
prefix="rb-btcpay-$$"
pg="$prefix-pg"; app="$prefix-app"; nbx="$prefix-nbx"
btc=()
cleanup() {
  docker rm -vf "$app" "$nbx" "$pg" >/dev/null 2>&1 || true
  if ((${#btc[@]})); then "${btc[@]}" stop >/dev/null 2>&1 || true; fi
  if [[ -n ${pid:-} ]]; then wait "$pid" || true; fi
  rm -rf -- "$work"
}
trap cleanup EXIT
cd "$work"; mkdir bitcoin btcpay nbx
password=$(openssl rand -hex 20)
admin="qa@example.invalid"
btc=(bitcoin-cli -regtest "-datadir=$work/bitcoin" -rpcport=18343)
bitcoind -regtest -server -listen=1 -bind=127.0.0.1:18344 -port=18344 -dnsseed=0 -connect=0 -rpcbind=127.0.0.1 -rpcport=18343 -rpcuser=regtest "-rpcpassword=$password" "-datadir=$work/bitcoin" -txindex=1 >btc.log 2>&1 &
pid=$!
btc+=(-rpcuser=regtest "-rpcpassword=$password")
"${btc[@]}" -rpcwait -rpcwaittimeout=60 getblockcount >/dev/null
"${btc[@]}" createwallet miner >/dev/null
address=$("${btc[@]}" getnewaddress)
"${btc[@]}" generatetoaddress 101 "$address" >/dev/null
docker run --name "$pg" -d -p 127.0.0.1:18432:5432 -e "POSTGRES_PASSWORD=$password" postgres:16@sha256:ce81150802644ddfac1db4da9e63be6f2a3818aa6ee98a7a28838aeea65dc37a >/dev/null
for ((i=0;i<60;i++)); do docker exec "$pg" pg_isready -U postgres >/dev/null && break; sleep 1; done
for database in nbxmerchant btcpaymerchant; do docker exec "$pg" createdb -U postgres "$database"; done
db="Host=127.0.0.1;Port=18432;Username=postgres;Password=$password;Database="
docker run --name "$nbx" -d --network host -v "$work/nbx:/datadir" nicolasdorier/nbxplorer:2.6.10@sha256:7d2ab1f6ce38e301cba98a4f85bfbfcf2912d5034bd88af056f9d60e5511f911 \
  --network=regtest --bind=127.0.0.1:18435 --chains=btc "--postgres=${db}nbxmerchant" \
  --btcrpcurl=http://127.0.0.1:18343 --btcrpcuser=regtest "--btcrpcpassword=$password" \
  --btcnodeendpoint=127.0.0.1:18344 >/dev/null
cookie="$work/nbx/RegTest/.cookie"
for ((i=0;i<90;i++)); do [[ -s $cookie ]] && break; sleep 1; done
[[ -s $cookie ]] || { echo 'NBXplorer regtest did not initialize'; exit 1; }
base=http://127.0.0.1:18436
start_app() {
  docker run --name "$app" -d --network host -v "$work/btcpay:/datadir" -v "$cookie:/qa.cookie:ro" \
    -e BTCPAY_DATADIR=/datadir -e BTCPAY_NETWORK=regtest -e BTCPAY_CHAINS=btc \
    -e BTCPAY_BIND=127.0.0.1:18436 -e "BTCPAY_POSTGRES=${db}btcpaymerchant" \
    -e BTCPAY_BTCEXPLORERURL=http://127.0.0.1:18435/ -e BTCPAY_BTCEXPLORERCOOKIEFILE=/qa.cookie \
    "btcpayserver/btcpayserver:$1@sha256:$2" >/dev/null
  for ((i=0;i<150;i++)); do
    if curl -fsS "$base/api/v1/health" >health.json 2>/dev/null && jq -e '.synchronized' health.json >/dev/null; then return; fi
    if [[ $(docker inspect -f '{{.State.Running}}' "$app") != true ]]; then break; fi
    sleep 1
  done
  echo "BTCPay $1 did not report a synchronized explorer" >&2; exit 1
}
post() {
  curl -sS --fail-with-body --user "$admin:$password" -H 'Content-Type: application/json' --data "$2" "$base/api/v1/$1"
}
start_app 2.3.9 7c4b79fd578d919da1bc3bb52fd4695c156fe309ab8c0b6602c36026f1780d27
curl -fsS -H 'Content-Type: application/json' --data "$(jq -nc --arg p "$password" --arg e "$admin" '{email:$e,password:$p,sendInvitationEmail:false}')" "$base/api/v1/users" >user.json
post stores '{"name":"RaspiBlitz upgrade merchant"}' >store.json
store=$(jq -er .id store.json)
post "stores/$store/payment-methods/BTC-CHAIN/wallet/generate" '{"savePrivateKeys":false,"label":"QA regtest"}' >wallet.json
post "stores/$store/invoices" '{"amount":"0.0002","currency":"BTC","metadata":{"orderId":"before-upgrade"}}' >invoice.json
invoice=$(jq -er .id invoice.json)
checkout=$(jq -er .checkoutLink invoice.json)
curl -fsS "$checkout" -o checkout.html
grep -q "$invoice" checkout.html
echo 'PASS 2.3.9: merchant store, on-chain invoice and public checkout created.'
docker stop "$app" >/dev/null
docker rm "$app" >/dev/null
start_app 2.4.2 66a7e88964d44302a0312bf601c9ef0e4c3af71696e2e4edac6daa2742854e79
get() { curl -fsS --user "$admin:$password" "$base/api/v1/$1"; }
get "stores/$store" | jq -e '.name == "RaspiBlitz upgrade merchant"' >/dev/null
get "stores/$store/invoices/$invoice" | jq -e --arg id "$invoice" '.id == $id and .metadata.orderId == "before-upgrade"' >/dev/null
curl -fsS "$checkout" -o checkout-after.html
grep -q "$invoice" checkout-after.html
post "stores/$store/invoices" '{"amount":"0.0003","currency":"BTC","metadata":{"orderId":"after-upgrade"}}' >new-invoice.json
jq -e --arg first "$invoice" '.id != $first and .metadata.orderId == "after-upgrade"' new-invoice.json >/dev/null
echo 'PASS 2.4.2: same store, old invoice and checkout preserved; new invoice created.'
