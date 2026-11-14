#!/usr/bin/env bats

# Unit tests for createHsmSecret / checkHsmSecret in
# home.admin/config.scripts/cl.hsmtool.sh (wallet creation and seed restore
# for Core Lightning).
#
# The functions are loaded from the real script, the real cl.hsmsecret.py
# helper derives and writes the hsm_secret. Only 'sudo', 'python' and
# 'lightning-hsmtool checkhsm' are replaced by stubs, so nothing outside a
# temporary directory is touched. The stub hsmtool implements the checkhsm
# stdin interface of CLN >= v25.12 ("new") or < v25.12 ("old").
# The real Core Lightning binaries are tested in cl.hsmtool.real-cln.bats.
#
# Needs: python3 with mnemonic==0.19 (or PYTHON=/path/to/python)
# bats ./cl.hsmtool.hsmsecret.bats

REPO="${BATS_TEST_DIRNAME}/.."
SCRIPT="${REPO}/home.admin/config.scripts/cl.hsmtool.sh"
HELPER="${REPO}/home.admin/config.scripts/cl.hsmsecret.py"

# BIP39 test vectors (trezor/python-mnemonic vectors.json): the legacy
# hsm_secret is the first 32 bytes of the BIP39 seed
ABANDON_12="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
ABANDON_12_TREZOR="c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553"
ABANDON_12_NOPASS="5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1"
ZOO_24="zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
ZOO_24_TREZOR="dd48c104698c30cfe2b6142103248622fb7bb0ff692eebb00089b32d22484e16"

setup() {
  TESTDIR="$(mktemp -d)"
  CALLS="${TESTDIR}/calls"
  : >"${CALLS}"
  export CALLS
  export MOCK_HSMTOOL="new"
  export REAL_PYTHON="${PYTHON:-python3}"
  mkdir -p "${TESTDIR}/bin" "${TESTDIR}/lightning"

  # sudo: log the command line, drop '-u <user>' and run the rest
  cat >"${TESTDIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >>"${CALLS}"
if [ "$1" = "-u" ]; then shift 2; fi
exec "$@"
EOF

  # python: RaspiBlitz has /usr/bin/python -> python3
  cat >"${TESTDIR}/bin/python" <<'EOF'
#!/usr/bin/env bash
echo "python $*" >>"${CALLS}"
exec "${REAL_PYTHON}" "$@"
EOF

  # lightning-hsmtool checkhsm with the stdin interface of
  # CLN >= v25.12 (new: passphrase, mnemonic) or
  # CLN <  v25.12 (old: passphrase, language id, mnemonic)
  cat >"${TESTDIR}/bin/lightning-hsmtool" <<'EOF'
#!/usr/bin/env bash
echo "lightning-hsmtool $* (${MOCK_HSMTOOL})" >>"${CALLS}"
[ "$1" = "checkhsm" ] && [ $# -eq 2 ] || exit 99
case "${MOCK_HSMTOOL}" in
  fail) exit 1 ;;
  new) IFS= read -r pass; IFS= read -r words ;;
  old) IFS= read -r pass; IFS= read -r lang
       [ "${lang}" = "0" ] || { echo "Invalid language selection" >&2; exit 1; }
       IFS= read -r words ;;
esac
expected=$("${REAL_PYTHON}" -c 'import hashlib, sys
print(hashlib.pbkdf2_hmac("sha512", sys.argv[1].encode(), b"mnemonic" + sys.argv[2].encode(), 2048)[:32].hex())' "${words}" "${pass}")
actual=$(od -An -v -tx1 "$2" | tr -d ' \n')
if [ "${expected}" = "${actual}" ]; then echo OK; else echo "resulting hsm_secret did not match" >&2; exit 1; fi
EOF
  chmod +x "${TESTDIR}/bin/"*
  export PATH="${TESTDIR}/bin:${PATH}"

  # load the functions under test from the real script
  eval "$(sed -n '/^function checkHsmSecret()/,/^}/p; /^function createHsmSecret()/,/^}/p' "${SCRIPT}")"
  declare -F createHsmSecret checkHsmSecret >/dev/null
  hsmSecretPath="${TESTDIR}/lightning/hsm_secret"
  hsmSecretHelper="${HELPER}"
}

teardown() {
  chmod -R u+w "${TESTDIR}"
  rm -rf "${TESTDIR}"
}

hsm_hex() { od -An -v -tx1 "$1" | tr -d ' \n'; }
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
called() { grep -qF -- "$1" "${CALLS}"; }
# bats does not fail a test on a "!"-negated command, so negate explicitly
not_called() { if called "$1"; then echo "unexpected call: $1"; return 1; fi; }
no_wallet() {
  if [ -e "${hsmSecretPath}" ]; then echo "unexpected hsm_secret"; return 1; fi
  if [ -n "$(ls -A "${TESTDIR}/lightning")" ]; then
    ls -la "${TESTDIR}/lightning"; return 1
  fi
}

@test "createHsmSecret writes the known vector byte-for-byte (12 words, passphrase)" {
  run createHsmSecret "${ABANDON_12}" "TREZOR"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(hsm_hex "${hsmSecretPath}")" = "${ABANDON_12_TREZOR}" ]
  [ "$(wc -c <"${hsmSecretPath}" | tr -d ' ')" -eq 32 ]
  [ "$(file_mode "${hsmSecretPath}")" = "400" ]
  [[ "$output" == *"Created and checked the hsm_secret"* ]]
  # written as the bitcoin user and checked with the new interface first
  called "sudo -u bitcoin python ${HELPER} write ${hsmSecretPath}"
  called "lightning-hsmtool checkhsm ${hsmSecretPath} (new)"
  [ "$(grep -c '^lightning-hsmtool' "${CALLS}")" -eq 1 ]
  # no leftovers next to the hsm_secret
  [ "$(ls -A "${TESTDIR}/lightning")" = "hsm_secret" ]
}

@test "createHsmSecret writes the known vector byte-for-byte (no passphrase)" {
  run createHsmSecret "${ABANDON_12}" ""
  [ "$status" -eq 0 ]
  [ "$(hsm_hex "${hsmSecretPath}")" = "${ABANDON_12_NOPASS}" ]
}

@test "createHsmSecret writes the known vector byte-for-byte (24 words)" {
  run createHsmSecret "${ZOO_24}" "TREZOR"
  [ "$status" -eq 0 ]
  [ "$(hsm_hex "${hsmSecretPath}")" = "${ZOO_24_TREZOR}" ]
}

@test "createHsmSecret normalizes whitespace between the seed words" {
  run createHsmSecret "  ${ABANDON_12// /	  } " "TREZOR"
  [ "$status" -eq 0 ]
  [ "$(hsm_hex "${hsmSecretPath}")" = "${ABANDON_12_TREZOR}" ]
}

@test "createHsmSecret accepts a CLN < v25.12 hsmtool (old checkhsm interface)" {
  export MOCK_HSMTOOL="old"
  run createHsmSecret "${ABANDON_12}" "TREZOR"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(hsm_hex "${hsmSecretPath}")" = "${ABANDON_12_TREZOR}" ]
  # the new interface was tried first and failed, the old one confirmed it
  [ "$(grep -c '^lightning-hsmtool checkhsm' "${CALLS}")" -eq 2 ]
}

@test "checkHsmSecret rejects a wrong passphrase with both interfaces" {
  run createHsmSecret "${ABANDON_12}" "TREZOR"
  [ "$status" -eq 0 ]
  for interface in new old; do
    export MOCK_HSMTOOL="${interface}"
    run checkHsmSecret "${ABANDON_12}" ""
    [ "$status" -eq 1 ]
    run checkHsmSecret "${ABANDON_12}" "TREZOR"
    [ "$status" -eq 0 ]
  done
}

@test "createHsmSecret: wrong word count creates no wallet" {
  run createHsmSecret "${ABANDON_12% about}" ""
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"11 words"* ]]
  [[ "$output" == *"ERROR: could not create the hsm_secret"* ]]
  no_wallet
  not_called "lightning-hsmtool"
}

@test "createHsmSecret: invalid mnemonic (bad checksum) creates no wallet" {
  run createHsmSecret "${ABANDON_12% about} abandon" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"wrong BIP39 checksum"* ]]
  no_wallet
  not_called "lightning-hsmtool"
}

@test "createHsmSecret: invalid mnemonic (unknown word) creates no wallet and does not log the words" {
  run createHsmSecret "${ABANDON_12% about} satoshi" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"word(s) number 12 not in the BIP39 english wordlist"* ]]
  [[ "$output" != *"satoshi"* ]]
  no_wallet
}

@test "createHsmSecret: failing derive tool creates no wallet" {
  hsmSecretHelper="${TESTDIR}/missing.py"
  run createHsmSecret "${ABANDON_12}" ""
  [ "$status" -eq 1 ]
  no_wallet
  not_called "lightning-hsmtool"
}

@test "createHsmSecret: never overwrites an existing hsm_secret" {
  printf 'existing wallet' >"${hsmSecretPath}"
  run createHsmSecret "${ABANDON_12}" ""
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
  [ "$(cat "${hsmSecretPath}")" = "existing wallet" ]
  [ "$(ls -A "${TESTDIR}/lightning")" = "hsm_secret" ]
  not_called "lightning-hsmtool"
}

@test "createHsmSecret: failed write leaves no partial hsm_secret (read-only directory)" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"
  chmod 500 "${TESTDIR}/lightning"
  run createHsmSecret "${ABANDON_12}" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not create"* ]]
  chmod 700 "${TESTDIR}/lightning"
  no_wallet
}

@test "createHsmSecret: hsmtool not confirming the wallet moves it aside" {
  export MOCK_HSMTOOL="fail"
  run createHsmSecret "${ABANDON_12}" "TREZOR"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checkhsm did not confirm the new hsm_secret"* ]]
  [ ! -e "${hsmSecretPath}" ]
  unverified=("${hsmSecretPath}".unverified.*)
  [ "${#unverified[@]}" -eq 1 ]
  [ "$(hsm_hex "${unverified[0]}")" = "${ABANDON_12_TREZOR}" ]
  [ "$(grep -c '^lightning-hsmtool checkhsm' "${CALLS}")" -eq 2 ]
}

@test "createHsmSecret passes seed words and passphrase on stdin only" {
  run createHsmSecret "${ABANDON_12}" "TREZOR"
  [ "$status" -eq 0 ]
  cat "${CALLS}"
  not_called "about"
  not_called "TREZOR"
}

@test "script: wallet creation uses createHsmSecret and exits on failure" {
  grep -qxF '  createHsmSecret "${seedwords}" "${seedpassword}" 1>&2 || exit 1' "${SCRIPT}"
  grep -qxF 'hsmSecretHelper="/home/admin/config.scripts/cl.hsmsecret.py"' "${SCRIPT}"
}

@test "script: lightning-hsmtool generatehsm is not used anymore" {
  run grep -n 'generatehsm' "${SCRIPT}"
  echo "$output"
  # only mentioned in comments
  if echo "$output" | grep -v '^[0-9]*:#'; then false; fi
}
