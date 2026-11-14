#!/usr/bin/env bats

# Tests for the Core Lightning release signature check in
# home.admin/config.scripts/cl.install.sh (verifySHA256SUMSSignature).
#
# The old check counted "Good signature" lines of 'gpg --verify'. gpg prints
# that for any key in the bitcoin user's keyring (other apps import their
# signers there) and for expired keys. The function must only accept a valid
# signature by the pinned key.
#
# Uses the real gpg with throwaway keys in a temporary GNUPGHOME ('sudo' is a
# stub), plus a replay of the real SHA256SUMS of the pinned CLVERSION with the
# pinned keys from cl.install.sh (network, skipped with CL_PGP_OFFLINE=1).
#
# bats ./cl.install.pgp.bats

INSTALL="${BATS_TEST_DIRNAME}/../home.admin/config.scripts/cl.install.sh"

setup_file() {
  # short path: gpg-agent socket paths are limited to ~100 characters
  GNUPGHOME="$(mktemp -d /tmp/clpgp.XXXXXX)"
  export GNUPGHOME
  chmod 700 "${GNUPGHOME}"
  gen() { # uid usage expiry [faked time]
    gpg --batch --passphrase '' ${4:+--faked-system-time "$4"} \
      --quick-gen-key "$1" ed25519 "$2" "$3" >/dev/null 2>&1
    gpg --with-colons --list-keys "$1" | awk -F: '$1 == "fpr" { print $10; exit }'
  }
  PINNED=$(gen "pinned <pinned@test>" sign never)
  OTHER=$(gen "other app signer <other@test>" sign never)
  EXPIRED=$(gen "expired <expired@test>" sign 1d 20200101T000000)
  # primary key only certifies, a subkey signs (like ngoline's release key)
  SUBPRIMARY=$(gen "subkey signer <sub@test>" cert never)
  gpg --batch --passphrase '' --quick-add-key "${SUBPRIMARY}" ed25519 sign never >/dev/null 2>&1
  SUBKEY=$(gpg --with-colons --list-keys "${SUBPRIMARY}" | awk -F: '$1 == "fpr" { n++ } $1 == "fpr" && n == 2 { print $10; exit }')
  export PINNED OTHER EXPIRED SUBPRIMARY SUBKEY
  [ -n "${PINNED}" ] && [ -n "${OTHER}" ] && [ -n "${EXPIRED}" ] && [ -n "${SUBKEY}" ]
}

teardown_file() {
  gpgconf --kill gpg-agent 2>/dev/null || true
  rm -rf "${GNUPGHOME}"
}

setup() {
  WORK="$(mktemp -d)"
  cd "${WORK}"
  mkdir bin
  # sudo stub: log the call, drop '-u <user>'
  CALLS="${WORK}/calls"
  export CALLS
  printf '#!/bin/sh\necho "sudo $*" >>"${CALLS}"\nif [ "$1" = "-u" ]; then shift 2; fi\nexec "$@"\n' >bin/sudo
  chmod +x bin/sudo
  PATH="${WORK}/bin:${PATH}"
  eval "$(sed -n '/^function verifySHA256SUMSSignature()/,/^}/p' "${INSTALL}")"
  declare -F verifySHA256SUMSSignature >/dev/null
  CLVERSION="vtest"
  echo "deadbeef  clightning-vtest.zip" >"SHA256SUMS-${CLVERSION}"
  : >"SHA256SUMS-${CLVERSION}.asc"
}

teardown() {
  cd /
  rm -rf "${WORK}"
}

# append a detached armored signature of SHA256SUMS by key $1
sign_by() {
  gpg --batch --yes --passphrase '' ${2:+--faked-system-time "$2"} --local-user "$1!" \
    --armor --detach-sign -o sig.asc "SHA256SUMS-${CLVERSION}" 2>/dev/null
  cat sig.asc >>"SHA256SUMS-${CLVERSION}.asc"
}

@test "accepts a valid signature by the pinned key" {
  sign_by "${PINNED}"
  run verifySHA256SUMSSignature "${PINNED}"
  echo "$output"
  [ "$status" -eq 0 ]
  # with the keyring of the bitcoin user (where cl.install.sh imports the keys)
  grep -qxF "sudo -u bitcoin gpg --status-fd 1 --verify SHA256SUMS-${CLVERSION}.asc SHA256SUMS-${CLVERSION}" "${CALLS}"
}

@test "rejects a signature by another key in the keyring (accepted by the old 'Good signature' count)" {
  sign_by "${OTHER}"
  # what the old check counted
  gpg --verify "SHA256SUMS-${CLVERSION}.asc" "SHA256SUMS-${CLVERSION}" 2>&1 | grep -q "Good signature"
  run verifySHA256SUMSSignature "${PINNED}"
  echo "$output"
  [ "$status" -ne 0 ]
}

@test "accepts the pinned signature next to other signatures in any order" {
  sign_by "${OTHER}"
  sign_by "${PINNED}"
  sign_by "${OTHER}"
  run verifySHA256SUMSSignature "${PINNED}"
  [ "$status" -eq 0 ]
}

@test "rejects a signature by the pinned key when it is expired" {
  sign_by "${EXPIRED}" 20200101T120000
  gpg --verify "SHA256SUMS-${CLVERSION}.asc" "SHA256SUMS-${CLVERSION}" 2>&1 | grep -q "Good signature"
  run verifySHA256SUMSSignature "${EXPIRED}"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"EXPKEYSIG"* ]]
}

@test "a good signature by another key does not validate an expired one by the pinned key" {
  sign_by "${OTHER}"
  sign_by "${EXPIRED}" 20200101T120000
  run verifySHA256SUMSSignature "${EXPIRED}"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GOODSIG"* ]]
  [[ "$output" == *"EXPKEYSIG"* ]]
}

@test "rejects a tampered SHA256SUMS" {
  sign_by "${PINNED}"
  echo "cafebabe  clightning-vtest.zip" >"SHA256SUMS-${CLVERSION}"
  run verifySHA256SUMSSignature "${PINNED}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BADSIG"* ]]
}

@test "rejects a missing or empty signature file" {
  run verifySHA256SUMSSignature "${PINNED}"
  [ "$status" -ne 0 ]
  rm "SHA256SUMS-${CLVERSION}.asc"
  run verifySHA256SUMSSignature "${PINNED}"
  [ "$status" -ne 0 ]
}

@test "a signing subkey matches by its own or its primary fingerprint, not by another key" {
  sign_by "${SUBKEY}"
  run verifySHA256SUMSSignature "${SUBKEY}"
  [ "$status" -eq 0 ]
  run verifySHA256SUMSSignature "${SUBPRIMARY}"
  [ "$status" -eq 0 ]
  run verifySHA256SUMSSignature "${PINNED}"
  [ "$status" -ne 0 ]
}

@test "rejects an empty fingerprint" {
  sign_by "${PINNED}"
  run verifySHA256SUMSSignature ""
  [ "$status" -ne 0 ]
}

@test "the real SHA256SUMS of the pinned CLVERSION is signed by both pinned keys" {
  [ "${CL_PGP_OFFLINE}" != "1" ] || skip "CL_PGP_OFFLINE=1"
  eval "$(grep -E '^(CLVERSION|PGPsigner|PGPpubkeyLink|PGPpubkeyFingerprint|PGPfallbackSigner|PGPfallbackPubkeyLink|PGPfallbackPubkeyFingerprint)=' "${INSTALL}")"
  base="https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}"
  curl -fsSL -o "SHA256SUMS-${CLVERSION}" "${base}/SHA256SUMS-${CLVERSION}"
  curl -fsSL -o "SHA256SUMS-${CLVERSION}.asc" "${base}/SHA256SUMS-${CLVERSION}.asc"
  # a separate keyring with only the pinned keys
  export GNUPGHOME="${WORK}/gnupg"
  mkdir -m 700 "${GNUPGHOME}"
  curl -fsSL "${PGPpubkeyLink}" | gpg --import 2>/dev/null
  curl -fsSL "${PGPfallbackPubkeyLink}" | gpg --import 2>/dev/null
  run verifySHA256SUMSSignature "${PGPpubkeyFingerprint}"
  echo "$output"
  [ "$status" -eq 0 ]
  run verifySHA256SUMSSignature "${PGPfallbackPubkeyFingerprint}"
  [ "$status" -eq 0 ]
  run verifySHA256SUMSSignature "${PINNED}"
  [ "$status" -ne 0 ]
  gpgconf --kill gpg-agent 2>/dev/null || true
}

@test "script: both signature checks pass the pinned fingerprint" {
  grep -qF '! verifySHA256SUMSSignature "${PGPpubkeyFingerprint}"; then' "${INSTALL}"
  grep -qF 'if ! verifySHA256SUMSSignature "${PGPfallbackPubkeyFingerprint}"; then' "${INSTALL}"
  run grep -n 'grep -c "Good signature"' "${INSTALL}"
  [ "$status" -ne 0 ]
}
