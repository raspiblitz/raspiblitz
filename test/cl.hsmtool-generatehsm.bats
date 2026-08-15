#!/usr/bin/env bats

# Tests for the 'lightning-hsmtool generatehsm' stdin interface used by
# home.admin/config.scripts/cl.hsmtool.sh
#
# Background:
# CLN < v25.12 'generatehsm' first asked for a wordlist number ("0" = english),
# then the mnemonic, then the passphrase twice (confirmation).
# CLN >= v25.12 reads the BIP39 mnemonic from the FIRST stdin line and the
# passphrase (once) from the second line. Sending the old payload makes
# hsmtool read "0" as the mnemonic, fail BIP39 validation and abort
# (fail-closed: no hsm_secret is created and no weak wallet is possible).

SCRIPT="${BATS_TEST_DIRNAME}/../home.admin/config.scripts/cl.hsmtool.sh"
# 12-word BIP39 test vector (valid checksum)
MNEMONIC="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

setup() {
  TESTDIR="$(mktemp -d)"

  # mock 'lightning-hsmtool' implementing the CLN >= v25.12 generatehsm
  # interface: first stdin line = mnemonic, second stdin line = passphrase
  cat > "$TESTDIR/lightning-hsmtool" <<'EOF'
#!/usr/bin/env bash
if [ "$1" != "generatehsm" ] || [ -z "$2" ]; then
  echo "usage: lightning-hsmtool generatehsm <path>" >&2
  exit 1
fi
hsm="$2"
if [ -e "$hsm" ]; then
  echo "hsm_secret file at $hsm already exists" >&2
  exit 1
fi
# first stdin line must be a valid BIP39 mnemonic (>=12 lowercase words)
read -r mnemonic
count=$(echo "$mnemonic" | wc -w)
if [ "$count" -lt 12 ] || ! echo "$mnemonic" | grep -qE '^[a-z ]+$'; then
  echo "Could not read mnemonic: invalid format" >&2
  exit 1
fi
# second stdin line is the passphrase (may be empty)
read -r passphrase || passphrase=""
{
  echo "mock-hsm-secret"
  echo "mnemonic=$mnemonic"
  echo "passphrase=$passphrase"
} > "$hsm"
echo "New hsm_secret file created at $hsm"
EOF
  chmod +x "$TESTDIR/lightning-hsmtool"

  # mock 'sudo': drop '-u <user>' and exec the rest
  cat > "$TESTDIR/sudo" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-u" ]; then shift 2; fi
exec "$@"
EOF
  chmod +x "$TESTDIR/sudo"

  export PATH="$TESTDIR:$PATH"

  # load the function under test from the real script
  eval "$(sed -n '/^function generateHsmInput/,/^}/p' "$SCRIPT")"
}

teardown() {
  rm -rf "$TESTDIR"
}

# replicate the exact pipeline used in cl.hsmtool.sh
pipe_to_hsmtool() {
  generateHsmInput "$1" "$2" | sudo -u bitcoin \
    lightning-hsmtool "generatehsm" "$3" 1>&2
}

@test "problem: old input format (language id first) is rejected by CLN >= v25.12" {
  hsm="$TESTDIR/hsm_secret_old"
  # this is exactly what cl.hsmtool.sh piped before the fix:
  # language id "0", mnemonic, empty passphrase
  run bash -c "(echo '0'; echo '$MNEMONIC'; echo) | lightning-hsmtool generatehsm '$hsm'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not read mnemonic"* ]]
  # fail-closed: no wallet file was created
  [ ! -e "$hsm" ]
}

@test "fix: generateHsmInput without seedpassword creates the wallet" {
  hsm="$TESTDIR/hsm_secret_nopass"
  run pipe_to_hsmtool "$MNEMONIC" "" "$hsm"
  [ "$status" -eq 0 ]
  [ -f "$hsm" ]
  grep -q "mnemonic=$MNEMONIC" "$hsm"
  grep -q "^passphrase=$" "$hsm"
}

@test "fix: generateHsmInput with seedpassword passes it as the second line" {
  hsm="$TESTDIR/hsm_secret_pass"
  run pipe_to_hsmtool "$MNEMONIC" "secretpass" "$hsm"
  [ "$status" -eq 0 ]
  [ -f "$hsm" ]
  grep -q "mnemonic=$MNEMONIC" "$hsm"
  grep -q "^passphrase=secretpass$" "$hsm"
}

@test "fix: first line of generateHsmInput output is the mnemonic" {
  run generateHsmInput "$MNEMONIC" "whatever"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$MNEMONIC" ]
  [ "${lines[1]}" = "whatever" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "script: generatehsm call uses generateHsmInput" {
  grep -q 'generateHsmInput "${seedwords}" "${seedpassword}"' "$SCRIPT"
}

@test "script: no legacy language id is piped to hsmtool anymore" {
  run grep -n 'echo "0"' "$SCRIPT"
  [ "$status" -ne 0 ]
}
