# Shared setup for the TunnelSats bats suites. Sources the production script and points its TS_RB_*
# variables at a fixture tree below $BATS_TEST_TMPDIR; every test calls the real functions.
# The variables set here are read by the sourced script and the .bats files; bats' run sets output.
# shellcheck disable=SC2034,SC2154

ITS="${BATS_TEST_DIRNAME}/../../home.admin/config.scripts/internet.tunnelsats.sh"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
SCHEMA_CHECK="${BATS_TEST_DIRNAME}/schema_check.py"

LND_FLAGS="--tor.skip-proxy-for-clearnet-targets --externalhosts=de2.tunnelsats.com:24556"
CLN_FLAGS_ANNOUNCE="--bind-addr=0.0.0.0:9735 --announce-addr=1.2.3.4:24556 --always-use-proxy=false --announce-addr-discovered=false"
CLN_FLAGS_PLAIN="--bind-addr=0.0.0.0:9735 --always-use-proxy=false --announce-addr-discovered=false"

its_setup() {
    export LC_ALL=C
    FX="${BATS_TEST_TMPDIR}/fx"
    chmod -R u+rwX "$FX" 2>/dev/null || true
    rm -rf "$FX"
    mkdir -p "$FX/conf" "$FX/app-data/lnd" "$FX/app-data/.lightning" "$FX/bitcoin" "$FX/run" "$FX/bin" "$FX/admin"
    ln -s "$FX/app-data/.lightning" "$FX/bitcoin/.lightning"
    echo "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0" > "$FX/boot_id"
    # shellcheck source=/dev/null
    source "$ITS"
    TS_RB_ROOT="$FX/admin"
    TS_RB_CONF="$FX/conf/raspiblitz.conf"
    TS_RB_TOOL="$FX/bin/tunnelsats"
    TS_RB_RUN_DIR="$FX/run/tunnelsats"
    TS_RB_TOOL_TMP="$FX/run"
    TS_RB_LOCK_DIR="$FX/run/tunnelsats-rb"
    TS_RB_APPDATA="$FX/app-data"
    TS_RB_CLN_DIR="$FX/bitcoin/.lightning"
    TS_RB_BOOT_ID="$FX/boot_id"
    TS_RB_ROOT_UID="$(id -u)"
    TS_RB_SYSTEMCTL="$FX/bin/systemctl"
    TS_RB_VERIFY_TIMEOUT=30
    TS_RB_HANDSHAKE_WAIT=3
    TS_RB_HANDSHAKE_POLL=1
    unset INVOCATION_ID TUNNELSATS_LND_ARGS TUNNELSATS_CLN_ARGS
    printf '#!/bin/bash\ncat "%s/unit_state" 2>/dev/null || echo inactive\n' "$FX" > "$FX/bin/systemctl"
    chmod 0755 "$FX/bin/systemctl"
}

its_teardown() {
    chmod -R u+rwX "${BATS_TEST_TMPDIR}/fx" 2>/dev/null || true
}

# Runs a production function with nounset, as the executed script does.
call() {
    ( set -u; "$@" )
}

# Like call, but in the test shell, so the test can read the globals the function sets.
here() {
    local rc
    set -u
    "$@"
    rc=$?
    set +u
    return "$rc"
}

# Lists the fixture tree (files with mode and size, directories with mode, symlinks with target),
# without the stub tool's own call log.
tree_state() {
    (cd "$FX" && find . \( -path ./tool.calls -o -path ./tool.env \) -prune -o \
        \( -type f -printf 'f %p %m %s\n' \) -o \( -type d -printf 'd %p %m\n' \) -o \( -type l -printf 'l %p %l\n' \) | sort)
}

# Fails if the command succeeds (in bats, a leading ! never fails a test).
refute() {
    if "$@"; then
        echo "unexpected success: $*" >&2
        return 1
    fi
    return 0
}

# raspiblitz.conf from KEY=VALUE arguments
conf() {
    printf '%s\n' "$@" > "$TS_RB_CONF"
}

lnd_conf() {
    cp "${FIXTURES}/conf/$1" "$FX/app-data/lnd/lnd.conf"
}

cln_conf() {
    cp "${FIXTURES}/conf/$1" "$FX/app-data/.lightning/config"
}

# Stub tool: prints verify document(s) (one per call, the last one repeats) and exits with the
# document's exit_code. Options: -r RC (exit code), -s SECONDS (sleep first), -c CMD (run CMD first).
stub_tool() {
    local rc="" sleep_s="" pre="" d
    local -a docs=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r) rc="$2"; shift 2 ;;
            -s) sleep_s="$2"; shift 2 ;;
            -c) pre="$2"; shift 2 ;;
            *) docs+=("${FIXTURES}/verify/$1"); shift ;;
        esac
    done
    {
        echo '#!/bin/bash'
        echo "env > '$FX/tool.env'"
        echo "printf '%s\\n' \"\$*\" >> '$FX/tool.calls'"
        echo "n=\$(wc -l < '$FX/tool.calls')"
        echo "docs=(${docs[*]@Q})"
        echo 'i=$(( n - 1 )); (( i < ${#docs[@]} )) || i=$(( ${#docs[@]} - 1 ))'
        [[ -n "$pre" ]] && echo "$pre"
        [[ -n "$sleep_s" ]] && echo "sleep $sleep_s"
        echo 'cat "${docs[$i]}"'
        if [[ -n "$rc" ]]; then
            echo "exit $rc"
        else
            echo 'exit "$(jq -r ".exit_code" "${docs[$i]}" | head -n 1)"'
        fi
    } > "$TS_RB_TOOL"
    chmod 0755 "$TS_RB_TOOL"
    for d in "${docs[@]}"; do
        [[ -f "$d" ]] || { echo "missing fixture $d" >&2; return 1; }
    done
    TS_ACCEPTED_SHA256=("$(sha256sum "$TS_RB_TOOL" | cut -d' ' -f1)")
}

tool_calls() {
    if [[ -f "$FX/tool.calls" ]]; then wc -l < "$FX/tool.calls"; else echo 0; fi
}

# The env file content of unit base $1 (lnd, lightningd, tlnd, ...), or <absent>.
env_of() {
    local f="${TS_RB_RUN_DIR}/hybrid-$1.env"
    if [[ -e "$f" ]]; then cat "$f"; else echo "<absent>"; fi
}

record_field() {   # $1 unit base, $2 jq path
    jq -r "$2" "${TS_RB_RUN_DIR}/guard-$1.json"
}

# Asserts the guard's stderr summary line in $output names decision $1 and reason $2.
assert_decision() {
    if [[ "$output" != *"decision=$1 reason=$2"* ]]; then
        echo "expected decision=$1 reason=$2 in:" >&2
        echo "$output" >&2
        return 1
    fi
}

assert_schema() {   # $1 = document file
    python3 "$SCHEMA_CHECK" "${BATS_TEST_DIRNAME}/schema/guard-record.schema.json" "$1"
}
