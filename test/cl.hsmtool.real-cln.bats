#!/usr/bin/env bats

# Tests of the Core Lightning wallet creation in cl.hsmtool.sh against the
# real 'lightning-hsmtool' binaries in the official Docker images:
#  - CLN v25.09.3: the last release with the old generatehsm/checkhsm interface
#  - CLN ${CLVERSION} pinned in cl.install.sh: the new (>= v25.12) interface
# and an end-to-end run of cl.hsmtool.sh seed-force / seed / new-force inside
# the pinned CLN image (Debian) with python3, sudo and mnemonic==0.19.
#
# Needs docker and network access (image pulls, apt, pip).
# Without docker the tests are skipped unless CL_HSMTOOL_REQUIRE_DOCKER=1 (CI).
# Needs python3 with mnemonic==0.19 on the host (or PYTHON=/path/to/python).
#
# bats ./cl.hsmtool.real-cln.bats

REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT="${REPO}/home.admin/config.scripts/cl.hsmtool.sh"
HELPER="${REPO}/home.admin/config.scripts/cl.hsmsecret.py"
OLD_IMAGE="elementsproject/lightningd:v25.09.3"

# BIP39 test vectors (trezor/python-mnemonic vectors.json): the legacy
# hsm_secret is the first 32 bytes of the BIP39 seed
ABANDON_12="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
ABANDON_12_TREZOR="c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553"
ABANDON_12_NOPASS="5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1"
ZOO_24="zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
ZOO_24_TREZOR="dd48c104698c30cfe2b6142103248622fb7bb0ff692eebb00089b32d22484e16"

clversion() {
  sed -n 's/^CLVERSION="\(v[0-9.]*\)"$/\1/p' "${REPO}/home.admin/config.scripts/cl.install.sh"
}

setup_file() {
  if ! docker info >/dev/null 2>&1; then
    if [ "${CL_HSMTOOL_REQUIRE_DOCKER}" = "1" ]; then
      echo "docker is required (CL_HSMTOOL_REQUIRE_DOCKER=1)" >&3
      return 1
    fi
    return 0
  fi
  local version
  version="$(clversion)"
  [ -n "${version}" ]
  export NEW_IMAGE="elementsproject/lightningd:${version}"
  export E2E_IMAGE="raspiblitz-cl-hsmtool-test:${version}"
  docker pull -q "${OLD_IMAGE}" >/dev/null
  docker pull -q "${NEW_IMAGE}" >/dev/null
  # the pinned CLN image (Debian bookworm) with what cl.hsmtool.sh needs
  docker build -q -t "${E2E_IMAGE}" --build-arg "CLN_IMAGE=${NEW_IMAGE}" - >/dev/null <<'EOF'
ARG CLN_IMAGE
FROM ${CLN_IMAGE}
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends python3 python3-pip sudo >/dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf /usr/bin/python3 /usr/bin/python \
 && pip install -q --break-system-packages mnemonic==0.19 \
 && useradd -m bitcoin && useradd -m admin
ENTRYPOINT []
EOF
}

setup() {
  docker info >/dev/null 2>&1 || skip "docker is not available"
  WORK="$(mktemp -d)"
  export WORK
  export REAL_PYTHON="${PYTHON:-python3}"
  mkdir -p "${WORK}/bin" "${WORK}/lightning"
  cat >"${WORK}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-u" ]; then shift 2; fi
exec "$@"
EOF
  cat >"${WORK}/bin/python" <<'EOF'
#!/usr/bin/env bash
exec "${REAL_PYTHON}" "$@"
EOF
  # the real lightning-hsmtool of ${HSMTOOL_IMAGE}, as the current user
  cat >"${WORK}/bin/lightning-hsmtool" <<'EOF'
#!/usr/bin/env bash
exec docker run --rm -i --user "$(id -u):$(id -g)" -v "${WORK}:${WORK}" \
  --entrypoint lightning-hsmtool "${HSMTOOL_IMAGE}" "$@"
EOF
  chmod +x "${WORK}/bin/"*
  export PATH="${WORK}/bin:${PATH}"
  eval "$(sed -n '/^function checkHsmSecret()/,/^}/p; /^function createHsmSecret()/,/^}/p' "${SCRIPT}")"
  declare -F createHsmSecret checkHsmSecret >/dev/null
  hsmSecretPath="${WORK}/lightning/hsm_secret"
  hsmSecretHelper="${HELPER}"
}

teardown() {
  [ -n "${WORK}" ] || return 0
  chmod -R u+w "${WORK}"
  rm -rf "${WORK}"
}

hsm_hex() { od -An -v -tx1 "$1" | tr -d ' \n'; }
# lightning-hsmtool of an image: hsmtool <image> <args...>
hsmtool() { HSMTOOL_IMAGE="$1" lightning-hsmtool "${@:2}"; }
# 'generatehsm' of CLN < v25.12: language id, mnemonic, passphrase
old_generatehsm() {
  printf '0\n%s\n%s\n' "$1" "$2" | hsmtool "${OLD_IMAGE}" generatehsm "$3" >/dev/null
}
# 'generatehsm' of CLN >= v25.12: mnemonic, passphrase
new_generatehsm() {
  printf '%s\n%s\n' "$1" "$2" | hsmtool "${NEW_IMAGE}" generatehsm "$3" >/dev/null
}
wallet_of() {
  hsmtool "$1" getnodeid "$2"
  hsmtool "$1" dumponchaindescriptors "$2"
  hsmtool "$1" dumponchaindescriptors "$2" testnet
}

@test "CLN v25.09.3: createHsmSecret is byte-identical to lightning-hsmtool generatehsm" {
  export HSMTOOL_IMAGE="${OLD_IMAGE}"
  while read -r words pass expected; do
    words="${words//_/ }"; pass="${pass#-}"
    # a new directory each time: Docker Desktop bind mounts can serve a
    # cached old file at a reused path
    mkdir "${WORK}/${expected}"
    hsmSecretPath="${WORK}/${expected}/hsm_secret"
    # checked with the old checkhsm interface (fallback)
    run createHsmSecret "${words}" "${pass}"
    echo "$output"
    [ "$status" -eq 0 ]
    old_generatehsm "${words}" "${pass}" "${WORK}/${expected}/reference"
    cmp "${hsmSecretPath}" "${WORK}/${expected}/reference"
    [ "$(hsm_hex "${hsmSecretPath}")" = "${expected}" ]
  done <<EOF
${ABANDON_12// /_} TREZOR ${ABANDON_12_TREZOR}
${ABANDON_12// /_} - ${ABANDON_12_NOPASS}
${ZOO_24// /_} TREZOR ${ZOO_24_TREZOR}
EOF
}

@test "CLN pinned: createHsmSecret is confirmed by checkhsm and restores the same node and on-chain wallet as CLN v25.09.3" {
  export HSMTOOL_IMAGE="${NEW_IMAGE}"
  run createHsmSecret "${ABANDON_12}" "TREZOR"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(hsm_hex "${hsmSecretPath}")" = "${ABANDON_12_TREZOR}" ]
  old_generatehsm "${ABANDON_12}" "TREZOR" "${WORK}/reference"
  new_wallet="$(wallet_of "${NEW_IMAGE}" "${hsmSecretPath}")"
  old_wallet="$(wallet_of "${OLD_IMAGE}" "${WORK}/reference")"
  echo "${new_wallet}"
  [ "${new_wallet}" = "${old_wallet}" ]
  [ "$(echo "${new_wallet}" | wc -l)" -eq 7 ]
}

@test "CLN pinned: its generatehsm (mnemonic format) would restore a different on-chain wallet" {
  # why createHsmSecret does not use generatehsm of CLN >= v25.12
  new_generatehsm "${ABANDON_12}" "" "${WORK}/mnemonic_format"
  old_generatehsm "${ABANDON_12}" "" "${WORK}/reference"
  [ "$(hsm_hex "${WORK}/reference")" = "${ABANDON_12_NOPASS}" ]
  [ "$(wc -c <"${WORK}/mnemonic_format" | tr -d ' ')" -ne 32 ]
  mnemonic_descriptors="$(hsmtool "${NEW_IMAGE}" dumponchaindescriptors "${WORK}/mnemonic_format")"
  legacy_descriptors="$(hsmtool "${NEW_IMAGE}" dumponchaindescriptors "${WORK}/reference")"
  [ "${mnemonic_descriptors}" != "${legacy_descriptors}" ]
  # and 'lightning-hsmtool encrypt' (cl.hsmtool.sh encrypt) rejects it
  run bash -c "printf 'pw\npw\n' | HSMTOOL_IMAGE='${NEW_IMAGE}' lightning-hsmtool encrypt '${WORK}/mnemonic_format'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"only works on legacy plain binary format"* ]]
}

@test "CLN pinned: encrypt and decrypt (cl.hsmtool.sh encrypt/decrypt) work on the created hsm_secret" {
  export HSMTOOL_IMAGE="${NEW_IMAGE}"
  run createHsmSecret "${ABANDON_12}" "TREZOR"
  [ "$status" -eq 0 ]
  chmod 600 "${hsmSecretPath}"
  printf 'pw\npw\n' | lightning-hsmtool encrypt "${hsmSecretPath}"
  [ "$(wc -c <"${hsmSecretPath}" | tr -d ' ')" -eq 73 ]
  echo "pw" | lightning-hsmtool decrypt "${hsmSecretPath}"
  [ "$(hsm_hex "${hsmSecretPath}")" = "${ABANDON_12_TREZOR}" ]
}

@test "both interfaces: checkhsm rejects a wrong passphrase and wrong seed words" {
  for image in "${OLD_IMAGE}" "${NEW_IMAGE}"; do
    export HSMTOOL_IMAGE="${image}"
    mkdir "${WORK}/${image##*:}"
    hsmSecretPath="${WORK}/${image##*:}/hsm_secret"
    run createHsmSecret "${ABANDON_12}" "TREZOR"
    [ "$status" -eq 0 ]
    run checkHsmSecret "${ABANDON_12}" ""
    [ "$status" -eq 1 ]
    run checkHsmSecret "${ZOO_24}" "TREZOR"
    [ "$status" -eq 1 ]
    run checkHsmSecret "${ABANDON_12}" "TREZOR"
    [ "$status" -eq 0 ]
  done
}

@test "CLN pinned: the old generatehsm payload is rejected and creates no file (the original break)" {
  run bash -c "printf '0\n%s\n\n' '${ABANDON_12}' | HSMTOOL_IMAGE='${NEW_IMAGE}' lightning-hsmtool generatehsm '${WORK}/old_payload'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not read mnemonic"* ]]
  [ ! -e "${WORK}/old_payload" ]
}

@test "end-to-end: cl.hsmtool.sh seed-force, seed and new-force with the pinned CLN" {
  cat >"${WORK}/e2e.sh" <<'EOF'
#!/bin/bash
set -u
fail() { echo "FAIL: $*"; exit 1; }
hex() { od -An -v -tx1 "$1" | tr -d ' \n'; }
mkdir -p /home/admin/config.scripts /mnt/hdd/app-data
cp -a /repo/home.admin/config.scripts/. /home/admin/config.scripts/
# stubs for the services touched after the wallet creation
for stub in cl-plugin.backup.sh cl.install-service.sh; do
  printf '#!/bin/sh\necho "%s $*" >>/tmp/calls\n' "${stub}" >/home/admin/config.scripts/${stub}
done
chmod +x /home/admin/config.scripts/*
printf 'network=bitcoin\nchain=main\nlightning=cl\n' >/mnt/hdd/app-data/raspiblitz.conf
touch /home/admin/raspiblitz.info
hsm=/home/bitcoin/.lightning/bitcoin/hsm_secret
cd /home/admin

echo "## seed-force (restore with passphrase)"
bash config.scripts/cl.hsmtool.sh seed-force mainnet "${ABANDON_12}" "TREZOR" || fail "seed-force"
[ "$(hex "${hsm}")" = "${ABANDON_12_TREZOR}" ] || fail "seed-force bytes"
[ "$(stat -c '%U %a %s' "${hsm}")" = "bitcoin 400 32" ] || fail "owner/mode: $(stat -c '%U %a %s' "${hsm}")"
grep -q "seedwords='abandon, abandon," /home/bitcoin/.lightning/bitcoin/seedwords.info || fail "seedwords.info"
grep -q "cl-plugin.backup.sh on mainnet" /tmp/calls || fail "backup plugin not re-initialized"
ls /home/bitcoin/.lightning/bitcoin/ | grep -q '^\.' && fail "leftover temporary file"

echo "## seed-force again (moves the old wallet to a backup)"
bash config.scripts/cl.hsmtool.sh seed-force mainnet "${ZOO_24}" "TREZOR" || fail "seed-force 2"
[ "$(hex "${hsm}")" = "${ZOO_24_TREZOR}" ] || fail "seed-force 2 bytes"
[ "$(hex ${hsm}.backup.*)" = "${ABANDON_12_TREZOR}" ] || fail "backup of the old wallet"

echo "## seed with invalid words (no wallet, no backup plugin re-init)"
rm -f "${hsm}" /tmp/calls
if bash config.scripts/cl.hsmtool.sh seed mainnet "${ABANDON_12% about} abandon" ""; then
  fail "invalid seed words accepted"
fi
[ ! -e "${hsm}" ] || fail "wallet created from invalid seed words"
[ ! -e /tmp/calls ] || fail "continued after the failure: $(cat /tmp/calls)"

echo "## new-force (new wallet from generated seed words)"
out="$(bash config.scripts/cl.hsmtool.sh new-force mainnet 2>/dev/null)" || fail "new-force"
seedwords="$(echo "${out}" | sed -n "s/^seedwords='\(.*\)'$/\1/p" | head -n 1 | sed 's/, / /g')"
[ "$(echo "${seedwords}" | wc -w)" -eq 24 ] || fail "new-force seed words: ${out}"
[ "$(stat -c '%U %a %s' "${hsm}")" = "bitcoin 400 32" ] || fail "new-force owner/mode"
printf '\n%s\n' "${seedwords}" | sudo -u bitcoin lightning-hsmtool checkhsm "${hsm}" | grep -qx OK \
  || fail "new-force wallet does not match its seed words"
echo "E2E OK"
EOF
  run docker run --rm -v "${REPO}:/repo:ro" -v "${WORK}/e2e.sh:/e2e.sh:ro" \
    -e ABANDON_12="${ABANDON_12}" -e ABANDON_12_TREZOR="${ABANDON_12_TREZOR}" \
    -e ZOO_24="${ZOO_24}" -e ZOO_24_TREZOR="${ZOO_24_TREZOR}" \
    "${E2E_IMAGE}" bash /e2e.sh
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"E2E OK"* ]]
}
