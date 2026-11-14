#!/usr/bin/env bats

# Unit tests for the uv based dependency install in bonus.lnbits.sh.
# Runs anywhere: only the script header (versions + functions, everything before
# "# command info") is sourced and sudo is replaced by a stub, so nothing is
# downloaded, installed or deleted.
#
# bats ./bonus.lnbits.bats

SCRIPT="${BATS_TEST_DIRNAME}/../home.admin/config.scripts/bonus.lnbits.sh"

setup() {
  # shellcheck disable=SC1090
  source <(sed '/^# command info$/q' "${SCRIPT}")

  CALLS="${BATS_TEST_TMPDIR}/calls"
  : >"${CALLS}"
  REQUIREMENTS="${BATS_TEST_TMPDIR}/requirements.txt"
  UNIT="${BATS_TEST_TMPDIR}/lnbits.service"
  FAKE_UV_VERSION=""     # what an already installed uv reports
  FAKE_PIP_FAILS=""      # 1 = pip refuses the wheel (e.g. checksum mismatch)
  FAKE_SYNC_FAILS=""     # 1 = uv sync fails
  FAKE_LNBITS_BIN="1"    # 1 = the lnbits binary exists after uv sync
  FAKE_UNIT="1"          # 1 = the systemd service is set up

  # the functions change into directories that only exist on a RaspiBlitz
  cd() { echo "cd $*" >>"${CALLS}"; }

  # log every privileged call, emulate only the ones the functions read from
  sudo() {
    [ "$1" = "-u" ] && shift 2
    echo "$*" >>"${CALLS}"
    case "$1 $2" in
      "/home/lnbits/.uv/bin/uv --version") [ -n "${FAKE_UV_VERSION}" ] && echo "uv ${FAKE_UV_VERSION} (aarch64-unknown-linux-gnu)" ;;
      "/home/lnbits/.uv/bin/uv sync") [ -z "${FAKE_SYNC_FAILS}" ] ;;
      "/home/lnbits/.uv/bin/pip install") [ -z "${FAKE_PIP_FAILS}" ] ;;
      "tee /home/lnbits/.uv/requirements.txt") cat >"${REQUIREMENTS}" ;;
      "test -x") [ -n "${FAKE_LNBITS_BIN}" ] ;;
      "test -f") [ -n "${FAKE_UNIT}" ] ;;
      # run the real sed, but on the unit file of the test
      "sed -i") sed -i.bak "$3" "${UNIT}" ;;
      *) return 0 ;;
    esac
  }
}

called() { grep -qF -- "$1" "${CALLS}"; }
# bats does not fail a test on a "!"-negated command, so negate explicitly
not_called() { if called "$1"; then echo "unexpected call: $1"; return 1; fi; }

@test "the script pins LNbits v1.7.0 or newer (critical security fixes)" {
  [ "${VERSION}" = "${tag}" ]
  [ "$(printf '%s\n' "v1.7.0" "${tag}" | sort -V | head -n1)" = "v1.7.0" ]
}

@test "installUv skips when the pinned uv is already installed" {
  FAKE_UV_VERSION="${uvVersion}"
  run installUv
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  not_called "rm -rf"
  not_called "pip install"
}

@test "installUv installs the pinned uv into a venv of the lnbits user, checksums required" {
  run installUv
  [ "$status" -eq 0 ]
  called "python3 -m venv /home/lnbits/.uv"
  called "/home/lnbits/.uv/bin/pip install --disable-pip-version-check --require-hashes --only-binary :all: -r /home/lnbits/.uv/requirements.txt"
  # one requirement line: the pinned version and every pinned checksum
  [ "$(wc -l <"${REQUIREMENTS}")" -eq 1 ]
  grep -q "^uv==${uvVersion} --hash=sha256:" "${REQUIREMENTS}"
  [ "$(grep -o -- '--hash=sha256:[0-9a-f]\{64\}' "${REQUIREMENTS}" | wc -l)" -eq 3 ]
  for checksum in ${uvChecksums}; do
    grep -q -- "--hash=sha256:${checksum}" "${REQUIREMENTS}"
  done
  # no system-wide install
  not_called "pip3 install"
  not_called "break-system-packages"
}

@test "installUv replaces another uv version" {
  FAKE_UV_VERSION="0.1.0"
  run installUv
  [ "$status" -eq 0 ]
  called "rm -rf /home/lnbits/.uv"
  called "python3 -m venv /home/lnbits/.uv"
  called "pip install"
}

@test "installUv fails and removes the venv when pip refuses the wheel" {
  FAKE_PIP_FAILS=1
  run installUv
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: could not install uv"* ]]
  # the last call cleans up, so the next run starts from scratch
  [ "$(tail -n1 "${CALLS}")" = "rm -rf /home/lnbits/.uv" ]
}

@test "installDependencies syncs exactly the locked versions without dev tools" {
  FAKE_UV_VERSION="${uvVersion}"
  run installDependencies
  [ "$status" -eq 0 ]
  called "cd /home/lnbits/lnbits"
  called "/home/lnbits/.uv/bin/uv sync --frozen --no-dev --extra migration"
  called "test -x /home/lnbits/lnbits/.venv/bin/lnbits"
  # the virtual environment of the old poetry based install is removed
  called "rm -rf /home/lnbits/.cache/pypoetry"
}

@test "installDependencies does not sync when uv cannot be installed" {
  FAKE_PIP_FAILS=1
  run installDependencies
  [ "$status" -eq 1 ]
  not_called "uv sync"
  not_called "pypoetry"
}

@test "installDependencies fails when uv sync fails" {
  FAKE_UV_VERSION="${uvVersion}"
  FAKE_SYNC_FAILS=1
  run installDependencies
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: uv sync failed"* ]]
  not_called "pypoetry"
}

@test "installDependencies fails when the lnbits binary is missing after the sync" {
  FAKE_UV_VERSION="${uvVersion}"
  FAKE_LNBITS_BIN=""
  run installDependencies
  [ "$status" -eq 1 ]
  [[ "$output" == *"is missing after uv sync"* ]]
  not_called "pypoetry"
}

@test "setServiceExecStart moves a poetry based service to the uv venv" {
  cat >"${UNIT}" <<EOF
[Service]
WorkingDirectory=/home/lnbits/lnbits
ExecStartPre=/home/admin/config.scripts/bonus.lnbits.sh prestart
ExecStart=/bin/sh -c 'cd /home/lnbits/lnbits && poetry run lnbits --port 5000 --host 0.0.0.0'
User=lnbits
EOF
  run setServiceExecStart
  [ "$status" -eq 0 ]
  grep -qx "ExecStart=/home/lnbits/lnbits/.venv/bin/lnbits --port 5000 --host 0.0.0.0" "${UNIT}"
  # the other lines are untouched
  grep -qx "ExecStartPre=/home/admin/config.scripts/bonus.lnbits.sh prestart" "${UNIT}"
  [ "$(wc -l <"${UNIT}")" -eq 5 ]
  called "sed -i s|^ExecStart=.*|ExecStart=/home/lnbits/lnbits/.venv/bin/lnbits --port 5000 --host 0.0.0.0| /etc/systemd/system/lnbits.service"
  called "systemctl daemon-reload"
}

@test "setServiceExecStart does nothing when the service is not set up" {
  FAKE_UNIT=""
  run setServiceExecStart
  [ "$status" -eq 0 ]
  not_called "sed -i"
  not_called "daemon-reload"
}

@test "pinned uv checksums match the Linux wheels on PyPI" {
  if ! metadata=$(curl -fsSL --max-time 20 "https://pypi.org/pypi/uv/${uvVersion}/json"); then
    skip "PyPI not reachable"
  fi
  for wheel in manylinux_2_17_aarch64 manylinux_2_28_aarch64 manylinux_2_17_x86_64; do
    # the digest that belongs to the file name of the wheel
    checksum=$(echo "${metadata}" | tr '{' '\n' | grep "\"filename\": *\"uv-${uvVersion}-py3-none-${wheel}[^\"]*\.whl\"" |
      grep -o '"sha256": *"[0-9a-f]\{64\}"' | grep -o '[0-9a-f]\{64\}' | head -n1)
    echo "${wheel}: ${checksum}"
    [ -n "${checksum}" ]
    echo "${uvChecksums}" | grep -qx "${checksum}"
  done
}
