#!/usr/bin/env bats

# Unit tests for the hsm_secret format handling of Core Lightning >= v25.12
# in the RaspiBlitz scripts:
#  - cl.hsmtool.sh: getHsmSecretType, clHsmStartError and clStartJournal
#    (unlock loop, cl.monitor.sh)
#  - cl.install-service.sh: hsmPassphraseOption
#  - the callers in cl.backup.sh, _provision.setup.sh, cl.monitor.sh and
#    cl.install.sh
# The functions are loaded from the real scripts; 'sudo', 'python',
# 'systemctl' and 'journalctl' are stubs, so nothing outside a temporary
# directory is touched.
# The real Core Lightning binaries and messages are tested in
# cl.hsmtool.real-cln.bats.
#
# Needs: python3 with mnemonic==0.19 (or PYTHON=/path/to/python), bash >= 4
# bats ./cl.hsmtool.formats.bats

REPO="${BATS_TEST_DIRNAME}/.."
SCRIPTS="${REPO}/home.admin/config.scripts"
SCRIPT="${SCRIPTS}/cl.hsmtool.sh"
HELPER="${SCRIPTS}/cl.hsmsecret.py"

ABANDON_12="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
ZOO_24="zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"

# start errors of lightningd with an encrypted hsm_secret, as printed by the
# real binaries (reproduced live in cl.hsmtool.real-cln.bats)
OLD_UNREADABLE="lightningd: --encrypted-hsm: Could not read pass from stdin."
OLD_MISSING="lightningd: hsm_secret is encrypted, you need to pass the --encrypted-hsm startup option."
OLD_WRONG="lightningd: Wrong password for encrypted hsm_secret."
NEW_UNREADABLE="lightningd: --hsm-passphrase: Invalid hsm_secret format"
NEW_UNREADABLE_DEPRECATED="lightningd: --encrypted-hsm: Invalid hsm_secret format"
NEW_MISSING="lightningd: HSM initialization failed: Failed to load hsm_secret: Passphrase required but not provided"
NEW_WRONG="lightningd: HSM initialization failed: Failed to load hsm_secret: Wrong passphrase"
NEW_REMOVED="lightningd: --encrypted-hsm: --encrypted-hsm was removed, use --hsm-passphrase instead"

load_functions() { # file function...
  local file="$1" f
  shift
  for f in "$@"; do
    eval "$(sed -n "/^function ${f}()/,/^}/p" "${file}")"
    declare -F "${f}" >/dev/null || { echo "missing function ${f}"; return 1; }
  done
}

setup() {
  TESTDIR="$(mktemp -d)"
  CALLS="${TESTDIR}/calls"
  : >"${CALLS}"
  export CALLS
  export REAL_PYTHON="${PYTHON:-python3}"
  mkdir -p "${TESTDIR}/bin" "${TESTDIR}/lightning"
  cat >"${TESTDIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >>"${CALLS}"
if [ "$1" = "-u" ]; then shift 2; fi
exec "$@"
EOF
  cat >"${TESTDIR}/bin/python" <<'EOF'
#!/usr/bin/env bash
echo "python $*" >>"${CALLS}"
exec "${REAL_PYTHON}" "$@"
EOF
  # systemd: InvocationID from $INVOCATION, journal from $JOURNAL
  cat >"${TESTDIR}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"${CALLS}"
[ "$*" = "show -p InvocationID --value lightningd" ] && echo "${INVOCATION}"
EOF
  cat >"${TESTDIR}/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
echo "journalctl $*" >>"${CALLS}"
printf '%s\n' "${JOURNAL}"
EOF
  chmod +x "${TESTDIR}/bin/"*
  export PATH="${TESTDIR}/bin:${PATH}"
  load_functions "${SCRIPT}" getHsmSecretType clHsmStartError clStartJournal
  hsmSecretPath="${TESTDIR}/lightning/hsm_secret"
  hsmSecretHelper="${HELPER}"
}

teardown() {
  rm -rf "${TESTDIR}"
}

put_hsm() { printf "$1" >"${hsmSecretPath}"; }
zeros32() { printf '\\x00%.0s' $(seq 32); }
called() { grep -qF -- "$1" "${CALLS}"; }

@test "getHsmSecretType detects the format as the bitcoin user" {
  put_hsm "$(printf '\\x01%.0s' $(seq 32))"
  run getHsmSecretType
  [ "$status" -eq 0 ]
  [ "$output" = "plain" ]
  called "sudo -u bitcoin python ${HELPER} type ${hsmSecretPath}"
  put_hsm "$(printf '\\x01%.0s' $(seq 73))"
  [ "$(getHsmSecretType)" = "encrypted" ]
  put_hsm "$(zeros32)${ABANDON_12}"
  [ "$(getHsmSecretType)" = "mnemonic" ]
  put_hsm "\\x01$(zeros32)${ABANDON_12}"
  [ "$(getHsmSecretType)" = "mnemonic-passphrase" ]
  rm "${hsmSecretPath}"
  run getHsmSecretType
  [ "$status" -ne 0 ]
  [[ "$output" != *"plain"* ]]
}

@test "clHsmStartError classifies the messages of CLN < v25.12 and >= v25.12" {
  [ "$(clHsmStartError "${OLD_UNREADABLE}")" = "password-unreadable" ]
  [ "$(clHsmStartError "${NEW_UNREADABLE}")" = "password-unreadable" ]
  [ "$(clHsmStartError "${NEW_UNREADABLE_DEPRECATED}")" = "password-unreadable" ]
  [ "$(clHsmStartError "${OLD_MISSING}")" = "password-missing" ]
  [ "$(clHsmStartError "${NEW_MISSING}")" = "password-missing" ]
  [ "$(clHsmStartError "${OLD_WRONG}")" = "password-wrong" ]
  [ "$(clHsmStartError "${NEW_WRONG}")" = "password-wrong" ]
  # refused when deprecated APIs are off (and after the deprecation ends):
  # the service has to be reinstalled with --hsm-passphrase
  [ "$(clHsmStartError "${NEW_REMOVED}")" = "password-missing" ]
  # journal lines around the message
  [ "$(clHsmStartError $'Nov 14 lightningd[1]: started\n'"${NEW_WRONG}"$'\nsystemd[1]: failed')" = "password-wrong" ]
}

@test "clHsmStartError ignores other start errors" {
  for text in "" "lightningd: Could not connect to bitcoind" \
    "Backup is out of date, we cannot continue safely. Emergency shutdown." \
    "use --database-upgrade=true to override" \
    "lightningd: Using BIP32 derivation for all operations (legacy HSM secret)"; do
    [ -z "$(clHsmStartError "${text}")" ]
  done
}

@test "clStartJournal reads the whole latest run of the service" {
  export INVOCATION="0123abcd" JOURNAL="${NEW_MISSING}"
  run clStartJournal lightningd
  [ "$status" -eq 0 ]
  [ "$output" = "${NEW_MISSING}" ]
  called "systemctl show -p InvocationID --value lightningd"
  called "sudo journalctl --no-pager -n 200 _SYSTEMD_INVOCATION_ID=0123abcd"
  # never started: the last lines of the unit
  : >"${CALLS}"
  export INVOCATION=""
  run clStartJournal lightningd
  [ "$output" = "${NEW_MISSING}" ]
  called "sudo journalctl --no-pager -n 60 -u lightningd"
}

@test "clStartJournal + clHsmStartError: the v26 error is found above its backtrace" {
  # CLN >= v25.12 prints a backtrace after 'Passphrase required but not
  # provided' (status_failed): the old 'journalctl -n5' window missed it
  backtrace=$(for i in $(seq 26); do echo "lightningd[1]: 0x5555555$i ???"; done)
  export INVOCATION="0123abcd"
  export JOURNAL="systemd[1]: Started lightningd.service
lightning_hsmd: Failed to load hsm_secret: Passphrase required but not provided (version v26.06.10)
${NEW_MISSING}
${backtrace}
systemd[1]: lightningd.service: Main process exited, code=exited, status=1/FAILURE
systemd[1]: lightningd.service: Failed with result 'exit-code'."
  [ -z "$(clHsmStartError "$(echo "${JOURNAL}" | tail -n 5)")" ]
  [ "$(clHsmStartError "$(clStartJournal lightningd)")" = "password-missing" ]
}

@test "hsmPassphraseOption: --hsm-passphrase from CLN v25.12 on, by 'lightningd --version'" {
  load_functions "${SCRIPTS}/cl.install-service.sh" hsmPassphraseOption
  lightningdBin="${TESTDIR}/bin/lightningd"
  for case in "v26.06.10:--hsm-passphrase" "v25.12:--hsm-passphrase" "v25.12.1:--hsm-passphrase" \
    "v26.12rc1:--hsm-passphrase" "v100.1:--hsm-passphrase" "v25.09.3:--encrypted-hsm" \
    "v25.09:--encrypted-hsm" "v24.11.2-modded:--encrypted-hsm" "25.05:--encrypted-hsm" \
    "garbage:--hsm-passphrase" ":--hsm-passphrase"; do
    printf '#!/bin/sh\necho "lightningd $*" >>"${CALLS}"\n[ "$1" = "--version" ] && echo "%s"\n' "${case%%:*}" >"${lightningdBin}"
    chmod +x "${lightningdBin}"
    echo "${case}: $(hsmPassphraseOption)"
    [ "$(hsmPassphraseOption)" = "${case#*:}" ]
  done
  # only --version, never a full start (--help reads the config and starts the plugins)
  run grep -v "^lightningd --version$" "${CALLS}"
  [ "$status" -ne 0 ]
  rm "${lightningdBin}"
  [ "$(hsmPassphraseOption)" = "--hsm-passphrase" ]
}

@test "script: the service uses hsmPassphraseOption and the same lightningd binary" {
  service="${SCRIPTS}/cl.install-service.sh"
  grep -qxF '  encryptedHSMoption="$(hsmPassphraseOption)"' "${service}"
  grep -qF "ExecStart=/bin/sh -c '\${passwordInput}\${lightningdBin} --conf=" "${service}"
  grep -qxF 'lightningdBin="/usr/local/bin/lightningd"' "${service}"
}

@test "script: no hsm_secret check parses lightning-hsmtool messages any more" {
  run grep -rn "grep.*hsm_secret is not encrypted" "${REPO}/home.admin"
  echo "$output"
  [ "$status" -ne 0 ]
  for caller in "${SCRIPTS}/cl.backup.sh" "${REPO}/home.admin/_provision.setup.sh"; do
    grep -qF 'source <(/home/admin/config.scripts/cl.hsmtool.sh hsm-type ' "${caller}"
    grep -qF '[ "${hsmSecretType}" = "plain" ] || [ "${hsmSecretType}" = "mnemonic" ]' "${caller}"
  done
}

@test "script: the unlock loop and cl.monitor.sh read the whole latest run" {
  grep -qxF '    clError=$(clStartJournal ${netprefix}lightningd)' "${SCRIPT}"
  run grep -n 'journalctl -n5\|journalctl -n 5' "${SCRIPT}" "${SCRIPTS}/cl.monitor.sh"
  echo "$output"
  [ "$status" -ne 0 ]
  grep -qF 'source <(/home/admin/config.scripts/cl.hsmtool.sh start-error $1 2>/dev/null | grep "^clStartError=")' "${SCRIPTS}/cl.monitor.sh"
  grep -qF '[ -n "${clStartError}" ]' "${SCRIPTS}/cl.monitor.sh"
  run grep -n "Could not read pass from stdin\|Wrong password for encrypted" "${SCRIPTS}/cl.monitor.sh"
  [ "$status" -ne 0 ]
}

@test "script: start-error prints only the assignment for cl.monitor.sh" {
  run awk '/^elif \[ "\$1" = "start-error" \]; then$/ {f=1; next} f && /^elif / {exit} f' "${SCRIPT}"
  echo "$output"
  [ "$(echo "$output" | grep -c 'echo')" -eq 1 ]
  [[ "$output" == *"echo \"clStartError='\$(clHsmStartError \"\$(clStartJournal \${netprefix}lightningd)\")'\""* ]]
}

@test "script: no seed words are recovered from a lightningd wallet" {
  # a lightningd >= v25.12 wallet (mnemonic format) is derived from the full
  # BIP39 seed: its words restored with 'seed-force' (legacy format) would be
  # a different wallet, so they are not shown as the wallet seed
  run grep -n "recoverStoredSeedwords\|cl.hsmsecret.py.* mnemonic\|\" mnemonic \"" "${SCRIPT}"
  [ "$status" -ne 0 ]
}

@test "script: the unlock loop uses clHsmStartError for all password errors" {
  for category in password-unreadable password-missing password-wrong; do
    grep -qF "elif [ \"\$(clHsmStartError \"\${clError}\")\" = \"${category}\" ];then" "${SCRIPT}"
  done
  run grep -nE "Could not read pass from stdin|you need to pass the --encrypted-hsm|Wrong password for encrypted" "${SCRIPT}"
  # only inside clHsmStartError
  [ "$(echo "$output" | wc -l)" -eq 3 ]
  [[ "$output" != *"grep -c"* ]]
}

@test "script: encrypt checks the format before the seed words are shredded" {
  run awk '/^elif \[ "\$1" = "encrypt" \]; then$/ {f=1}
    f && /hsmSecretType=\$\(getHsmSecretType\)/ {print "check"}
    f && /^    shred / {print "shred"; exit}' "${SCRIPT}"
  [ "$output" = $'check\nshred' ]
}

@test "script: no '2>1' redirections and no directory listing on the sourced stdout" {
  run grep -n '2>1' "${SCRIPT}"
  [ "$status" -ne 0 ]
  grep -qxF '  if ! sudo ls /home/bitcoin/.lightning/bitcoin 1>/dev/null 2>&1; then' "${SCRIPT}"
}

@test "script: cl.install.sh does not start lightningd without the created wallet" {
  run awk '/cl.hsmtool.sh new-force mainnet 2>&1 1>\/dev\/null \|\|$/ {f=1}
    f && /! sudo ls \$hsmSecretPath/ {print "check"}
    f && /^        exit 1$/ {print "exit"; exit}' "${SCRIPTS}/cl.install.sh"
  [ "$output" = $'check\nexit' ]
}
