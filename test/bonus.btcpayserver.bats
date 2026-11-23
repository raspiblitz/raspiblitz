#!/usr/bin/env bats

# Unit tests for the .NET bootstrap and PGP verification in bonus.btcpayserver.sh.
# Runs anywhere: only the script header (versions + functions, everything before
# "# command info") is sourced, and sudo, uname, sha512sum and the verify script
# are replaced by stubs, so nothing is downloaded, installed or deleted.
#
# bats ./bonus.btcpayserver.bats

SCRIPT="${BATS_TEST_DIRNAME}/../home.admin/config.scripts/bonus.btcpayserver.sh"

setup() {
  # shellcheck disable=SC1090
  source <(sed '/^# command info$/q' "${SCRIPT}")

  CALLS="${BATS_TEST_TMPDIR}/calls"
  : >"${CALLS}"
  FAKE_SDKS=""
  FAKE_CPU="aarch64"
  FAKE_SHA=""
  FAKE_GOOD_SIGNERS=""

  # log every privileged call, emulate only the ones the functions read from
  sudo() {
    [ "$1" = "-u" ] && shift 2
    echo "$*" >>"${CALLS}"
    case "$1" in
      /home/btcpay/dotnet/dotnet) printf '%s' "${FAKE_SDKS}" ;;
      /home/admin/config.scripts/blitz.git-verify.sh) [[ " ${FAKE_GOOD_SIGNERS} " == *" $2 "* ]] ;;
      *) return 0 ;;
    esac
  }
  uname() { echo "${FAKE_CPU}"; }
  sha512sum() { echo "${FAKE_SHA}  $1"; }
}

called() { grep -qF -- "$1" "${CALLS}"; }
# bats does not fail a test on a "!"-negated command, so negate explicitly
not_called() { if called "$1"; then echo "unexpected call: $1"; return 1; fi; }
# call sites use the functions without "|| exit 1", so a failure must end the caller
run_in_caller() { run eval "$1; echo CALLER_CONTINUED"; }

@test "PGPverify accepts the release signer without trying web-flow" {
  FAKE_GOOD_SIGNERS="nicolasdorier"
  run PGPverify
  [ "$status" -eq 0 ]
  called "blitz.git-verify.sh nicolasdorier https://keybase.io/nicolasdorier/pgp_keys.asc AB4CFA9895ACA0DBE27F6B346618763EF09186FE"
  not_called "web-flow"
}

@test "PGPverify falls back to GitHub web-flow" {
  FAKE_GOOD_SIGNERS="web-flow"
  run PGPverify
  [ "$status" -eq 0 ]
  called "blitz.git-verify.sh nicolasdorier"
  called "blitz.git-verify.sh web-flow https://github.com/web-flow.gpg B5690EEEBB952194"
}

@test "PGPverify stops the caller when neither signer verifies" {
  FAKE_GOOD_SIGNERS=""
  run_in_caller PGPverify
  [ "$status" -eq 1 ]
  [[ "$output" != *CALLER_CONTINUED* ]]
  called "blitz.git-verify.sh web-flow"
}

@test "DotNetInstall skips when the pinned SDK is already installed" {
  FAKE_SDKS=$'8.0.100 [/home/btcpay/dotnet/sdk]\n10.0.403 [/home/btcpay/dotnet/sdk]\n'
  run DotNetInstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  not_called "wget"
  not_called "rm -rf /home/btcpay/dotnet"
}

@test "DotNetInstall replaces an older SDK" {
  FAKE_SDKS=$'10.0.300 [/home/btcpay/dotnet/sdk]\n'
  FAKE_CPU="aarch64"
  FAKE_SHA="0966aa2b70f4677b8319be9df447a78a0dcd6164836425b55a68fd714f4023feb87b4cac21b9a996b79472ad54487cd0adcd2a9dfd570e2b2a1d26423a2baa9b"
  run DotNetInstall
  [ "$status" -eq 0 ]
  called "wget https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-linux-arm64.tar.gz"
  called "rm -rf /home/btcpay/dotnet"
}

@test "DotNetInstall fresh install on aarch64 downloads, verifies and extracts arm64" {
  FAKE_CPU="aarch64"
  FAKE_SHA="0966aa2b70f4677b8319be9df447a78a0dcd6164836425b55a68fd714f4023feb87b4cac21b9a996b79472ad54487cd0adcd2a9dfd570e2b2a1d26423a2baa9b"
  run DotNetInstall
  [ "$status" -eq 0 ]
  called "wget https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-linux-arm64.tar.gz -O /home/btcpay/dotnet-sdk-10.0.403-linux-arm64.tar.gz"
  called "tar -xvf /home/btcpay/dotnet-sdk-10.0.403-linux-arm64.tar.gz -C /home/btcpay/dotnet"
}

@test "DotNetInstall fresh install on x86_64 downloads, verifies and extracts x64" {
  FAKE_CPU="x86_64"
  FAKE_SHA="b7b3d8461cf98b07d2552ce9199702fa3ad010ac2671a5f8cd5136f7534e50f6855ba7bbb02b11494563f1d04156276a31cda1103b900e5eecd0d9473dc7b9c5"
  run DotNetInstall
  [ "$status" -eq 0 ]
  called "wget https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-linux-x64.tar.gz -O /home/btcpay/dotnet-sdk-10.0.403-linux-x64.tar.gz"
  called "tar -xvf /home/btcpay/dotnet-sdk-10.0.403-linux-x64.tar.gz -C /home/btcpay/dotnet"
}

@test "DotNetInstall stops the caller on a wrong checksum" {
  FAKE_CPU="x86_64"
  # the arm64 hash is valid hex but wrong for the x64 archive
  FAKE_SHA="0966aa2b70f4677b8319be9df447a78a0dcd6164836425b55a68fd714f4023feb87b4cac21b9a996b79472ad54487cd0adcd2a9dfd570e2b2a1d26423a2baa9b"
  run_in_caller DotNetInstall
  [ "$status" -eq 1 ]
  [[ "$output" == *"result='dotnet wrong checksum'"* ]]
  [[ "$output" != *CALLER_CONTINUED* ]]
  not_called "rm -rf /home/btcpay/dotnet"
  not_called "tar "
}

@test "DotNetInstall stops the caller on an unsupported CPU, before downloading" {
  FAKE_CPU="armv7l"
  run_in_caller DotNetInstall
  [ "$status" -eq 1 ]
  [[ "$output" == *"result='dotnet cpu not supported'"* ]]
  [[ "$output" != *CALLER_CONTINUED* ]]
  not_called "wget"
}

@test "pinned .NET checksums match Microsoft's release metadata" {
  command -v curl >/dev/null && command -v jq >/dev/null || skip "needs curl and jq"
  metadata=$(curl -sfL --max-time 60 https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json) || skip "release metadata not reachable"
  version=$(sed -n 's/^ *dotNetVersion="\(.*\)"$/\1/p' "${SCRIPT}")
  for pair in arm64:0966aa2b70f4677b8319be9df447a78a0dcd6164836425b55a68fd714f4023feb87b4cac21b9a996b79472ad54487cd0adcd2a9dfd570e2b2a1d26423a2baa9b \
              x64:b7b3d8461cf98b07d2552ce9199702fa3ad010ac2671a5f8cd5136f7534e50f6855ba7bbb02b11494563f1d04156276a31cda1103b900e5eecd0d9473dc7b9c5; do
    arch=${pair%%:*} hash=${pair#*:}
    grep -q "dotNetChecksum=\"${hash}\"" "${SCRIPT}"
    expected=$(jq -r --arg v "${version}" --arg n "dotnet-sdk-linux-${arch}.tar.gz" \
      '[.releases[].sdks[]? | select(.version==$v) | .files[] | select(.name==$n) | .hash][0]' <<<"${metadata}")
    [ "${expected}" = "${hash}" ]
  done
}
