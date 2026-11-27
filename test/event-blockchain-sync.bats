#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  sed -e 's|/home/admin/|./|g' -e 's|/mnt/hdd/app-data/|./|g' \
    "$BATS_TEST_DIRNAME/../home.admin/setup.scripts/eventBlockchainSync.sh" > show.sh
  touch _version.info raspiblitz.info raspiblitz.conf
  cat > _cache.sh <<'SH'
#!/bin/bash
shift
for key in "$@"; do printf '%s=%q\n' "$key" "${!key}"; done
SH
  printf '#!/bin/bash\nprintf "%%s\\n" "$@"\n' > dialog
  chmod +x _cache.sh dialog
  export PATH="$PWD:$PATH" lightning=lnd vm=1
  export btc_default_ready=1 btc_default_sync_percentage=99.99 btc_default_peers=2
  export btc_default_blocks_behind=1 ln_default_ready=1 ln_default_sync_chain=1
  export ln_default_sync_progress=100.00 ln_default_peers=0
}

@test "a complete chain scan can coexist with a pending graph and no peers" {
  export ln_default_sync_graph=0 ln_default_recovery_mode=1 ln_default_recovery_done=0
  run bash show.sh ssh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Blocks behind headers: 1"* ]]
  [[ "$output" == *"LND chain scan : synced (100.00 %)"* ]]
  [[ "$output" == *"LND graph      : pending, 0 peers"* ]]
  [[ "$output" == *"Wallet recovery: in progress"* ]]
}

@test "a missing graph sample stays unknown, an unready RPC hides old progress" {
  unset ln_default_sync_graph
  run bash show.sh lcd
  [[ "$output" == *"LND graph      : unknown"* ]]
  export ln_default_ready=0 ln_default_sync_graph=1
  run bash show.sh lcd
  [[ "$output" == *"waiting for RPC"* ]]
  [[ "$output" != *"100.00 %"* ]]
}

@test "Bitcoin-only and CLN screens keep their own display" {
  export lightning=cl
  run bash show.sh ssh
  [[ "$output" == *"Lightning Progress"* ]]
  [[ "$output" != *"LND graph"* ]]
  export lightning=
  run bash show.sh ssh
  [[ "$output" != *"Lightning Progress"* && "$output" != *"LND graph"* ]]
}
