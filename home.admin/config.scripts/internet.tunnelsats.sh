#!/bin/bash
#
# internet.tunnelsats.sh: TunnelSats (WireGuard VPN for Lightning clearnet traffic) on RaspiBlitz.
#
# Lightning stays Tor-only at rest: the LND and CLN configs on the data drive never hold clearnet
# settings. The start guard runs as ExecStartPre=+ in the Lightning unit and writes the clearnet
# flags for that start only to /run/tunnelsats/hybrid-<unit>.env (tmpfs), and only when the pinned
# tunnelsats tool reports its kill switch armed for exactly this unit. In every other case the
# value is empty and Lightning starts Tor-only. The guard keeps a start from running (non-zero exit,
# systemd retries) only when clearnet settings sit at rest and cannot be repaired toward Tor-only,
# when Tor is off while TunnelSats is on, or when it cannot write its own env file.
#
# Every path comes from a TS_RB_* variable. When the script is executed, main resets them to the
# production values first: the LND unit loads raspiblitz.conf into its environment, so nothing in
# that environment may redirect the guard. Tests source this file and point the variables at
# fixture trees.

# ---------------------------------------------------------------------------------------------
# Pins and production constants
# ---------------------------------------------------------------------------------------------

TS_PIN_VERSION="3.2"
# web-flow signed squash merge on Tunnelsats/tunnelsats main (PR 237, on top of PR 233, PR 230 and PR 227)
TS_PIN_COMMIT="24b184620a715825148cf50d0e537870943d1a94"
TS_PIN_SHA256="b1c0998c70dcaab6928120250d249f775d24c5f736abc24e611591126f67d048"
TS_PIN_SIGNER="web-flow"
TS_PIN_KEY_URL="https://github.com/web-flow.gpg"
# issuer of the signature of the pinned commit
TS_PIN_KEY_FPR="B5690EEEBB952194"
TS_PIN_CONTRACT=1
# sha256 of every tunnelsats.sh the guard runs: the current pin plus pins shipped in earlier
# RaspiBlitz releases (a node keeps working until REPAIR installs the newer pinned tool). The
# previous pin, db70fd8 (0cb360ae...), shipped in no release and is not accepted: its uninstall
# removes the dataplane under a Lightning unit that is still starting (fixed in tunnelsats PR 227).
TS_ACCEPTED_SHA256=("${TS_PIN_SHA256}")
TS_REPO_URL="https://github.com/Tunnelsats/tunnelsats.git"

# Size cap of a verify document read by the guard
ITS_DOC_MAX=262144
# Size cap of any other tool document
ITS_OUT_MAX=1048576
# Characters a flag value may contain: no quote, backslash, dollar, hash or glob character
ITS_VALUE_RE='^[A-Za-z0-9.:=/ -]*$'
ITS_SAFE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# What the tick unit runs (written into a unit file, so the production path)
ITS_PROD_MODULE="/home/admin/config.scripts/blitz.subscriptions.tunnelsats.py"

# Paths and commands. Values set before sourcing win (tests); main resets them when executed.
its_init_paths() {
    TS_RB_ROOT="${TS_RB_ROOT:-/home/admin}"
    TS_RB_CONF="${TS_RB_CONF:-/mnt/hdd/app-data/raspiblitz.conf}"
    TS_RB_TOOL="${TS_RB_TOOL:-/usr/local/sbin/tunnelsats}"
    TS_RB_RUN_DIR="${TS_RB_RUN_DIR:-/run/tunnelsats}"
    # The pinned tool's uninstall --managed (and a failed install's rollback) removes the run
    # directory: private copies of the tool and the locks live next to it, never inside it
    TS_RB_TOOL_TMP="${TS_RB_TOOL_TMP:-/run}"
    TS_RB_LOCK_DIR="${TS_RB_LOCK_DIR:-/run/tunnelsats-rb}"
    TS_RB_APPDATA="${TS_RB_APPDATA:-/mnt/hdd/app-data}"
    TS_RB_CUSTOM="${TS_RB_CUSTOM:-/mnt/hdd/app-data/custom-installs.sh}"
    TS_RB_SYSTEMCTL="${TS_RB_SYSTEMCTL:-systemctl}"
    TS_RB_VERIFY_TIMEOUT="${TS_RB_VERIFY_TIMEOUT:-30}"
    TS_RB_CLN_DIR="${TS_RB_CLN_DIR:-/home/bitcoin/.lightning}"
    TS_RB_BOOT_ID="${TS_RB_BOOT_ID:-/proc/sys/kernel/random/boot_id}"
    TS_RB_ROOT_UID="${TS_RB_ROOT_UID:-0}"
    TS_RB_HANDSHAKE_WAIT="${TS_RB_HANDSHAKE_WAIT:-20}"
    TS_RB_HANDSHAKE_POLL="${TS_RB_HANDSHAKE_POLL:-2}"
    TS_RB_UNIT_DIR="${TS_RB_UNIT_DIR:-/etc/systemd/system}"
    TS_RB_LOGGER="${TS_RB_LOGGER:-logger}"
    # seconds for all network steps of one online fetch together (git and the signature check)
    TS_RB_FETCH_BUDGET="${TS_RB_FETCH_BUDGET:-240}"
}
its_init_paths

ITS_TMPDIRS=()
NOW_MS=0

its_usage() {
    cat <<'EOF'
TunnelSats on RaspiBlitz (root only, except status)
  internet.tunnelsats.sh guard <lnd|cl> <mainnet|testnet|signet> [--dry-run] [--json]
  internet.tunnelsats.sh audit <lnd|cl> [--repair] [--json]
  internet.tunnelsats.sh fetch [--offline] [--json]
  internet.tunnelsats.sh install --impl <lnd|cl> [--json]
  internet.tunnelsats.sh adopt --impl <lnd|cl> [--json]
  internet.tunnelsats.sh uninstall [--json]
  internet.tunnelsats.sh verify [--no-probe] [--json]
  internet.tunnelsats.sh detect [--json]
  internet.tunnelsats.sh block-insert [--check] [--json] | block-remove [--json] | block-status [--json]
  internet.tunnelsats.sh restore [--json]
  internet.tunnelsats.sh tick-timer <on|off|status>
  internet.tunnelsats.sh status [--json]
EOF
}

# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

its_log() {
    printf '%s\n' "$*" >&2
}

its_now() {
    NOW_MS=$(( ${EPOCHREALTIME//[!0-9]/} / 1000 ))
}

its_is_root() {
    [[ "$EUID" -eq "$TS_RB_ROOT_UID" ]]
}

its_cleanup() {
    local d
    for d in "${ITS_TMPDIRS[@]}"; do
        rm -rf -- "$d"
    done
    ITS_TMPDIRS=()
}

# Prints the value of key $1 in raspiblitz.conf (KEY=v, KEY='v' or KEY="v"; the last assignment
# wins). The file is parsed, never sourced. Fails if the key is not set or the file cannot be read.
its_conf_get() {
    local key="$1" line val="" found=1 re
    re="^[[:space:]]*${key}=(.*)$"
    [[ -r "$TS_RB_CONF" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ $re ]]; then
            val="${BASH_REMATCH[1]}"
            found=0
        fi
    done < "$TS_RB_CONF"
    [[ "$found" -eq 0 ]] || return 1
    case "$val" in
        \'*) val="${val#\'}"; val="${val%%\'*}" ;;
        \"*) val="${val#\"}"; val="${val%%\"*}" ;;
        *) val="${val%%[[:space:]]*}" ;;
    esac
    printf '%s' "$val"
}

# Succeeds if raspiblitz.conf defines variable $1 in any form systemd or a shell would read.
its_conf_defines() {
    [[ -r "$TS_RB_CONF" ]] || return 1
    grep -Eq -- "^[[:space:]]*(export[[:space:]]+)?${1}[[:space:]]*=" "$TS_RB_CONF"
}

# Succeeds if directory $1 is a real directory owned by root and not writable by group or others.
its_dir_safe() {
    local st
    [[ -L "$1" ]] && return 1
    [[ -d "$1" ]] || return 1
    st=$(stat -c '%u %a' -- "$1" 2>/dev/null) || return 1
    [[ "${st%% *}" == "$TS_RB_ROOT_UID" ]] || return 1
    (( (8#${st##* } & 8#022) == 0 ))
}

# Makes sure the run directory exists (root 0755) and is safe to write to.
its_run_dir_ok() {
    if [[ ! -e "$TS_RB_RUN_DIR" ]] && [[ ! -L "$TS_RB_RUN_DIR" ]]; then
        mkdir -m 0755 -- "$TS_RB_RUN_DIR" 2>/dev/null || true
    fi
    its_dir_safe "$TS_RB_RUN_DIR"
}

# Makes sure the lock directory exists (root 0700) and is safe to write to.
its_lock_dir_ok() {
    if [[ ! -e "$TS_RB_LOCK_DIR" ]] && [[ ! -L "$TS_RB_LOCK_DIR" ]]; then
        mkdir -m 0700 -- "$TS_RB_LOCK_DIR" 2>/dev/null || true
    fi
    its_dir_safe "$TS_RB_LOCK_DIR"
}

# Base directory for the private temp directories of tool runs, verify and fetch: TS_RB_TOOL_TMP
# when it is safe, else TMPDIR. Never the run directory: uninstall --managed removes it while the
# tool runs, and with it the document of the run.
its_tool_tmp_base() {
    if its_dir_safe "$TS_RB_TOOL_TMP"; then
        printf '%s' "$TS_RB_TOOL_TMP"
    else
        printf '%s' "${TMPDIR:-/tmp}"
    fi
}

# Writes content $2 to file $1 atomically with mode $3 (temp file in the same directory, rename).
its_atomic_write() {
    local target="$1" content="$2" mode="$3" tmp
    tmp=$(mktemp "${target%/*}/.${target##*/}.XXXXXX" 2>/dev/null) || return 1
    if ! printf '%s' "$content" > "$tmp" 2>/dev/null || ! chmod "$mode" -- "$tmp" 2>/dev/null || \
        ! mv -fT -- "$tmp" "$target" 2>/dev/null; then
        rm -f -- "$tmp"
        return 1
    fi
    return 0
}

its_valid_host() {
    local re='^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+tunnelsats\.com$'
    [[ ${#1} -le 253 ]] && [[ "$1" =~ $re ]]
}

its_valid_port() {
    [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && (( $1 <= 65535 ))
}

# Succeeds for a dotted IPv4 address outside the private, shared, loopback, link-local,
# documentation, benchmark, multicast and reserved ranges.
its_valid_public_ipv4() {
    local o='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])' a b c
    [[ "$1" =~ ^${o}\.${o}\.${o}\.${o}$ ]] || return 1
    a="${BASH_REMATCH[1]}"
    b="${BASH_REMATCH[2]}"
    c="${BASH_REMATCH[3]}"
    if (( a == 0 || a == 10 || a == 127 || a >= 224 )) || \
        (( a == 100 && b >= 64 && b <= 127 )) || \
        (( a == 169 && b == 254 )) || \
        (( a == 172 && b >= 16 && b <= 31 )) || \
        (( a == 192 && b == 0 && (c == 0 || c == 2) )) || \
        (( a == 192 && b == 168 )) || \
        (( a == 198 && (b == 18 || b == 19) )) || \
        (( a == 198 && b == 51 && c == 100 )) || \
        (( a == 203 && b == 0 && c == 113 )); then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------
# At-rest audit of the Lightning configs (Tor-only at rest)
# ---------------------------------------------------------------------------------------------

# Splits config line $1 into P_KEY (blanks trimmed, lowercased) and P_VAL (blanks trimmed, empty
# for a bare flag). Fails for blank lines, comments (# or ;) and [section] lines.
its_cfg_parse() {
    local line="${1%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
        "" | "#"* | ";"* | "["*) return 1 ;;
    esac
    if [[ "$line" == *=* ]]; then
        P_KEY="${line%%=*}"
        P_VAL="${line#*=}"
    else
        P_KEY="$line"
        P_VAL=""
    fi
    P_KEY="${P_KEY%"${P_KEY##*[![:space:]]}"}"
    P_KEY="${P_KEY,,}"
    P_VAL="${P_VAL#"${P_VAL%%[![:space:]]*}"}"
    P_VAL="${P_VAL%"${P_VAL##*[![:space:]]}"}"
    return 0
}

# LND clearnet settings at rest (keys compared with or without the tor. prefix): bare, true or 1
# tor.skip-proxy-for-clearnet-targets, any externalhosts, any externalip. Uses P_KEY and P_VAL.
its_lnd_hit() {
    case "${P_KEY#tor.}" in
        skip-proxy-for-clearnet-targets)
            case "${P_VAL,,}" in
                "" | true | 1) return 0 ;;
            esac
            ;;
        externalhosts | externalip) return 0 ;;
    esac
    return 1
}

# Succeeds if CLN addr value $1 stays off the clearnet: loopback, Tor (onion, autotor:,
# statictor:) or a local socket path. Same predicate as tunnelsats.sh (ts_m_cln_addr_private).
its_cln_addr_private() {
    local v="${1,,}" host
    case "$v" in
        autotor:* | statictor:* | /*) return 0 ;;
    esac
    if [[ "$v" =~ \.onion(:[0-9]+)?$ ]]; then
        return 0
    fi
    host="$v"
    if [[ "$host" =~ ^(.*):[0-9]{1,5}$ ]]; then
        host="${BASH_REMATCH[1]}"
    fi
    case "$host" in
        localhost | 127.* | "[::1]" | ::1) return 0 ;;
    esac
    return 1
}

# CLN clearnet settings at rest (same predicate as tunnelsats.sh ts_m_nc_setting_hit): bind-addr on
# 9735 for all interfaces, a clearnet addr, an announce-addr that is not an onion address,
# always-use-proxy false or 0. Sets P_ACTION (delete or replace). Uses P_KEY and P_VAL.
its_cln_hit() {
    P_ACTION=""
    case "$P_KEY" in
        bind-addr)
            case "$P_VAL" in
                0.0.0.0:9735 | :9735 | "[::]:9735") P_ACTION=delete ;;
            esac
            ;;
        addr)
            if [[ -n "$P_VAL" ]] && ! its_cln_addr_private "$P_VAL"; then
                P_ACTION=delete
            fi
            ;;
        announce-addr)
            if [[ -n "$P_VAL" ]] && [[ ! "${P_VAL,,}" =~ \.onion(:[0-9]+)?$ ]]; then
                P_ACTION=delete
            fi
            ;;
        always-use-proxy)
            case "${P_VAL,,}" in
                false | 0) P_ACTION=replace ;;
            esac
            ;;
    esac
    [[ -n "$P_ACTION" ]]
}

# Reads config $1 into AS_LINES and sets AS_ENDS_NL (1 if the file ends with a newline). Fails if
# it cannot be read or holds NUL bytes (a rewrite could not keep them).
its_read_lines() {
    local f="$1" n_all n_nonul
    AS_LINES=()
    AS_ENDS_NL=1
    [[ -f "$f" ]] && [[ -r "$f" ]] || return 1
    n_all=$(wc -c < "$f" 2>/dev/null) || return 1
    n_nonul=$(tr -d '\000' < "$f" 2>/dev/null | wc -c) || return 1
    [[ "$n_all" == "$n_nonul" ]] || return 1
    mapfile -t AS_LINES < "$f" || return 1
    if [[ "$n_all" -gt 0 ]] && [[ -n "$(tail -c 1 -- "$f" 2>/dev/null)" ]]; then
        AS_ENDS_NL=0
    fi
    return 0
}

# Scans an included CLN config (path $1 as written, relative to directory $2) and the files it
# includes. Sets AS_INC_FAIL (the first of include_unreadable and include_hybrid), adds every
# clearnet line found to AS_HITS (<file>:<line>:<setting>) and sets the presence flags.
its_cln_scan_includes() {
    local -a queue=() seen=()
    local entry path dir depth resolved line s inc num
    queue=("0|$2|$1")
    while [[ ${#queue[@]} -gt 0 ]]; do
        entry="${queue[0]}"
        queue=("${queue[@]:1}")
        depth="${entry%%|*}"
        entry="${entry#*|}"
        dir="${entry%%|*}"
        path="${entry#*|}"
        [[ "$path" == /* ]] || path="${dir}/${path}"
        resolved=$(readlink -f -- "$path" 2>/dev/null) || resolved=""
        if [[ -z "$resolved" ]] || [[ ! -f "$resolved" ]] || [[ ! -r "$resolved" ]] || [[ "$depth" -gt 4 ]]; then
            [[ -n "$AS_INC_FAIL" ]] || AS_INC_FAIL="include_unreadable"
            continue
        fi
        for s in "${seen[@]}"; do
            [[ "$s" == "$resolved" ]] && continue 2
        done
        seen+=("$resolved")
        num=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            num=$((num + 1))
            line="${line%$'\r'}"
            line="${line#"${line%%[![:space:]]*}"}"
            if [[ "$line" =~ ^include([[:space:]]+|=)(.+)$ ]]; then
                inc="${BASH_REMATCH[2]}"
                inc="${inc%"${inc##*[![:space:]]}"}"
                queue+=("$((depth + 1))|${resolved%/*}|${inc}")
                continue
            fi
            its_cfg_parse "$line" || continue
            if its_cln_hit; then
                AS_HITS+=("${resolved}:${num}:${line}")
                [[ -n "$AS_INC_FAIL" ]] || AS_INC_FAIL="include_hybrid"
                continue
            fi
            its_cln_presence
        done < "$resolved"
    done
    return 0
}

# Records the CLN settings that eligibility and the always-use-proxy rule look at.
its_cln_presence() {
    case "$P_KEY" in
        always-use-proxy) AS_HAVE_AUP=1 ;;
        proxy) [[ -n "$P_VAL" ]] && AS_HAVE_PROXY=1 ;;
        bind-addr) [[ "$P_VAL" == "127.0.0.1:9736" ]] && AS_HAVE_TORBIND=1 ;;
    esac
    return 0
}

# Scans config $2 of implementation $1 (lnd|cl). Sets AS_ACTION (per line: delete, replace or
# empty), AS_KEYS (clearnet keys found), AS_HITS (every clearnet line as <file>:<line>:<setting>,
# includes too), AS_APPEND_AUP (CLN: always-use-proxy=true is missing), AS_FAIL (why the config
# cannot be made Tor-only by the guard) and the eligibility result AS_ELIGIBLE/AS_NE_REASON.
# Read-only.
its_audit_scan() {
    local impl="$1" file="$2" i k line inc tor_active="" listen_lines=0 listen_ok=0 nat=0 iso=0 port
    local -a includes=()
    AS_ACTION=() AS_KEYS=() AS_HITS=() AS_APPEND_AUP=0 AS_FAIL="" AS_ELIGIBLE=1 AS_NE_REASON="" AS_INC_FAIL=""
    AS_HAVE_AUP=0 AS_HAVE_PROXY=0 AS_HAVE_TORBIND=0
    if ! its_read_lines "$file"; then
        AS_FAIL="config_unreadable"
        return 0
    fi
    for i in "${!AS_LINES[@]}"; do
        AS_ACTION[i]=""
        line="${AS_LINES[i]%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ "$impl" == cl ]] && [[ "$line" =~ ^include([[:space:]]+|=)(.+)$ ]]; then
            inc="${BASH_REMATCH[2]}"
            includes+=("${inc%"${inc##*[![:space:]]}"}")
            continue
        fi
        its_cfg_parse "$line" || continue
        if [[ "$impl" == lnd ]]; then
            if its_lnd_hit; then
                AS_ACTION[i]=delete
                AS_KEYS+=("$P_KEY")
                AS_HITS+=("${file}:$((i + 1)):${line}")
                continue
            fi
            k="${P_KEY#tor.}"
            case "$k" in
                active) tor_active="${P_VAL,,}" ;;
                nat) case "${P_VAL,,}" in "" | true | 1) nat=1 ;; esac ;;
                streamisolation) case "${P_VAL,,}" in "" | true | 1) iso=1 ;; esac ;;
                listen)
                    listen_lines=$((listen_lines + 1))
                    case "$P_VAL" in
                        0.0.0.0:9735 | :9735 | "[::]:9735") listen_ok=1 ;;
                    esac
                    ;;
            esac
        else
            if its_cln_hit; then
                AS_ACTION[i]="$P_ACTION"
                AS_KEYS+=("$P_KEY")
                AS_HITS+=("${file}:$((i + 1)):${line}")
                [[ "$P_ACTION" == replace ]] && AS_HAVE_AUP=1
                continue
            fi
            its_cln_presence
        fi
    done
    if [[ "$impl" == lnd ]]; then
        case "$tor_active" in
            true | 1) ;;
            *) AS_FAIL="tor_inactive" ;;
        esac
        port=$(its_conf_get lndPort) || port=""
        if [[ "$nat" -eq 1 ]]; then
            AS_ELIGIBLE=0; AS_NE_REASON="nat"
        elif [[ "$iso" -eq 1 ]]; then
            AS_ELIGIBLE=0; AS_NE_REASON="streamisolation"
        elif [[ "$listen_lines" -gt 0 ]] && [[ "$listen_ok" -eq 0 ]]; then
            AS_ELIGIBLE=0; AS_NE_REASON="listen"
        elif [[ -n "$port" ]] && [[ "$port" != "9735" ]]; then
            AS_ELIGIBLE=0; AS_NE_REASON="lndport"
        fi
        return 0
    fi
    for inc in "${includes[@]}"; do
        its_cln_scan_includes "$inc" "${file%/*}"
    done
    [[ -z "$AS_INC_FAIL" ]] || AS_FAIL="$AS_INC_FAIL"
    if [[ "$AS_HAVE_AUP" -eq 0 ]]; then
        AS_APPEND_AUP=1
        AS_KEYS+=("always-use-proxy")
    fi
    if [[ "$AS_HAVE_PROXY" -eq 0 ]]; then
        AS_ELIGIBLE=0; AS_NE_REASON="proxy"
    elif [[ "$AS_HAVE_TORBIND" -eq 0 ]]; then
        AS_ELIGIBLE=0; AS_NE_REASON="torbind"
    fi
    return 0
}

# Writes the repaired text of AS_LINES (AS_ACTION applied) to file $1 (open temp file).
its_audit_render() {
    local out="$1" i last=$(( ${#AS_LINES[@]} - 1 )) line cr nl ends=1
    {
        for i in "${!AS_LINES[@]}"; do
            line="${AS_LINES[i]}"
            nl=$'\n'
            if [[ "$i" -eq "$last" ]] && [[ "$AS_ENDS_NL" -eq 0 ]]; then
                nl=""
            fi
            case "${AS_ACTION[i]}" in
                delete) continue ;;
                replace)
                    cr=""
                    [[ "$line" == *$'\r' ]] && cr=$'\r'
                    printf '%s%s%s' "always-use-proxy=true" "$cr" "$nl"
                    ;;
                *) printf '%s%s' "$line" "$nl" ;;
            esac
            [[ -n "$nl" ]] && ends=1 || ends=0
        done
        if [[ "$AS_APPEND_AUP" -eq 1 ]]; then
            [[ "$ends" -eq 1 ]] || printf '\n'
            printf '%s\n' "always-use-proxy=true"
        fi
    } > "$out"
}

# Repairs config A_CONF (scanned into AS_*) toward Tor-only: one backup slot, temp file with the
# original owner, group and mode next to the target, fsync, rename onto the resolved path.
# $1 = unit base name for the backup file. Sets A_BACKUP; fails with A_WHY.
its_audit_repair() {
    local base="$1" sdir bdir bfile btmp dir tmp st u g m
    sdir="${TS_RB_APPDATA}/tunnelsats"
    bdir="${sdir}/backup"
    bfile="${bdir}/${base}.${A_CONF##*/}.pre-repair"
    if { [[ -d "$sdir" ]] || mkdir -m 0700 -- "$sdir" 2>/dev/null; } && \
        { [[ -d "$bdir" ]] || mkdir -m 0700 -- "$bdir" 2>/dev/null; } && \
        btmp=$(mktemp "${bdir}/.pre-repair.XXXXXX" 2>/dev/null); then
        if ! cp -- "$A_CONF" "$btmp" 2>/dev/null || ! chmod 0600 -- "$btmp" 2>/dev/null || \
            ! sync -- "$btmp" 2>/dev/null || ! mv -fT -- "$btmp" "$bfile" 2>/dev/null; then
            rm -f -- "$btmp"
            A_WHY="backup_failed"
            return 1
        fi
    else
        A_WHY="backup_failed"
        return 1
    fi
    A_BACKUP="$bfile"
    dir="${A_CONF%/*}"
    st=$(stat -c '%u %g %a' -- "$A_CONF" 2>/dev/null) || { A_WHY="replace_failed"; return 1; }
    read -r u g m <<< "$st"
    if ! tmp=$(mktemp "${dir}/.${A_CONF##*/}.tunnelsats.XXXXXX" 2>/dev/null); then
        A_WHY="replace_failed"
        return 1
    fi
    if ! its_audit_render "$tmp" 2>/dev/null || ! chown -- "${u}:${g}" "$tmp" 2>/dev/null || \
        ! chmod -- "$m" "$tmp" 2>/dev/null || ! sync -- "$tmp" 2>/dev/null || \
        ! mv -fT -- "$tmp" "$A_CONF" 2>/dev/null; then
        rm -f -- "$tmp"
        A_WHY="replace_failed"
        return 1
    fi
    sync -- "$dir" 2>/dev/null || true
    return 0
}

# At-rest audit of config $2 (implementation $1, lnd|cl) toward Tor-only. $3 = check (read-only),
# repair (fix clearnet settings, one backup) or plan (read-only; drift a repair would fix counts as
# passable, used by --dry-run). $4 = unit base name (backup file name). Sets A_STATUS (clean, drift,
# repaired or unrepairable), A_WHY, A_KEYS, A_LINES (the clearnet lines still at rest, as
# <file>:<line>:<setting>), A_REPAIRED, A_BACKUP, A_ELIGIBLE, A_NE_REASON, A_CONF.
its_audit() {
    local impl="$1" file="$2" mode="$3" base="$4" resolved
    A_STATUS="" A_WHY="" A_KEYS=() A_LINES=() A_REPAIRED=() A_BACKUP="" A_ELIGIBLE=1 A_NE_REASON="" A_CONF=""
    resolved=$(readlink -f -- "$file" 2>/dev/null) || resolved=""
    if [[ -z "$resolved" ]] || [[ ! -e "$resolved" ]]; then
        A_STATUS="unrepairable"; A_WHY="config_missing"
        return 0
    fi
    A_CONF="$resolved"
    its_audit_scan "$impl" "$resolved"
    A_KEYS=("${AS_KEYS[@]}")
    A_LINES=("${AS_HITS[@]}")
    A_ELIGIBLE="$AS_ELIGIBLE"
    A_NE_REASON="$AS_NE_REASON"
    if [[ -n "$AS_FAIL" ]]; then
        A_STATUS="unrepairable"; A_WHY="$AS_FAIL"
        return 0
    fi
    if [[ ${#AS_KEYS[@]} -eq 0 ]]; then
        A_STATUS="clean"
        return 0
    fi
    if [[ "$mode" != repair ]]; then
        A_STATUS="drift"
        return 0
    fi
    if ! its_audit_repair "$base"; then
        A_STATUS="unrepairable"
        return 0
    fi
    A_REPAIRED=("${AS_KEYS[@]}")
    its_audit_scan "$impl" "$resolved"
    A_LINES=("${AS_HITS[@]}")
    if [[ -n "$AS_FAIL" ]] || [[ ${#AS_KEYS[@]} -gt 0 ]]; then
        A_STATUS="unrepairable"; A_WHY="reaudit_failed"
        return 0
    fi
    A_STATUS="repaired"
    return 0
}

# Mainnet config file of implementation $1.
its_conf_file() {
    if [[ "$1" == lnd ]]; then
        printf '%s' "${TS_RB_APPDATA}/lnd/lnd.conf"
    else
        printf '%s' "${TS_RB_CLN_DIR}/config"
    fi
}

# ---------------------------------------------------------------------------------------------
# The pinned tool
# ---------------------------------------------------------------------------------------------

# Prints the sha256 a development override registered for this boot, if any (root-owned file in
# the run directory, written by fetch --dev-override; it lapses with the next boot).
its_dev_override_sha() {
    local f="${TS_RB_RUN_DIR}/dev-override.sha256" st v
    [[ -f "$f" ]] && [[ ! -L "$f" ]] || return 0
    its_dir_safe "$TS_RB_RUN_DIR" || return 0
    st=$(stat -c '%u %a' -- "$f" 2>/dev/null) || return 0
    [[ "${st%% *}" == "$TS_RB_ROOT_UID" ]] || return 0
    (( (8#${st##* } & 8#022) == 0 )) || return 0
    v=$(head -c 65 -- "$f" 2>/dev/null | tr -d '\n') || return 0
    [[ "$v" =~ ^[0-9a-f]{64}$ ]] && printf '%s' "$v"
    return 0
}

# Trust check of the installed tool: regular file, owned by root, not writable by group or
# others, sha256 in TS_ACCEPTED_SHA256 (or the development override of this boot). Sets T_SHA.
# Returns 0 trusted, 3 missing, 4 untrusted.
its_tool_trust() {
    local st sha h dev
    T_SHA=""
    if [[ ! -e "$TS_RB_TOOL" ]] && [[ ! -L "$TS_RB_TOOL" ]]; then
        return 3
    fi
    if [[ -L "$TS_RB_TOOL" ]] || [[ ! -f "$TS_RB_TOOL" ]]; then
        return 4
    fi
    st=$(stat -c '%u %a' -- "$TS_RB_TOOL" 2>/dev/null) || return 4
    [[ "${st%% *}" == "$TS_RB_ROOT_UID" ]] || return 4
    (( (8#${st##* } & 8#022) == 0 )) || return 4
    sha=$(sha256sum -- "$TS_RB_TOOL" 2>/dev/null) || return 4
    sha="${sha%% *}"
    dev=$(its_dev_override_sha)
    for h in "${TS_ACCEPTED_SHA256[@]}" $dev; do
        if [[ "$sha" == "$h" ]]; then
            T_SHA="$sha"
            return 0
        fi
    done
    T_SHA="$sha"
    return 4
}

# Runs the trusted tool's "verify --json --no-probe" once, with timeout $1 seconds, in a clean
# environment (nothing from the Lightning unit environment reaches it). The tool runs from a private
# copy re-hashed against T_SHA, so the bytes that run are the bytes that were checked. Sets Q_RC
# (124 or 137 on timeout) and Q_DOC (the document, capped at ITS_DOC_MAX + 1 bytes).
its_verify_run() {
    local t="$1" dir copy sha
    Q_RC=-1
    Q_DOC=""
    dir=$(mktemp -d "$(its_tool_tmp_base)/.tunnelsats-verify-${G_BASE:-tool}.XXXXXX" 2>/dev/null) || return 1
    ITS_TMPDIRS+=("$dir")
    copy="${dir}/tunnelsats.sh"
    cp -- "$TS_RB_TOOL" "$copy" 2>/dev/null || return 1
    sha=$(sha256sum -- "$copy" 2>/dev/null) || return 1
    [[ "${sha%% *}" == "$T_SHA" ]] || return 1
    env -i PATH="$ITS_SAFE_PATH" LC_ALL=C.UTF-8 \
        timeout --kill-after=5 "$t" bash "$copy" verify --json --no-probe </dev/null 2>/dev/null |
        head -c $((ITS_DOC_MAX + 1)) > "${dir}/doc"
    Q_RC="${PIPESTATUS[0]}"
    Q_DOC="${dir}/doc"
    return 0
}

# jq program for the guard: validates a verify document (fields, not the exit code) and prints the
# reason plus the fields the decision needs, separated by US (0x1f).
read -r -d '' ITS_JQ_VALIDATE <<'JQ' || true
def int: type == "number" and . == floor;
def s: if type == "string" then gsub("[[:cntrl:]]"; " ") else "" end;
def req: ["install_state", "attest", "nft_killswitch", "slice_id", "ip_rules", "table_51820", "ln_dropin"];
def isreq: . as $i | any(req[]; . == $i);
def one($c; $id): [$c[] | select(.id == $id)] | if length == 1 then .[0] else {} end;
def reason:
  if (.contract != $contract) or (.command != "verify") then "verify_invalid"
  elif ((.exit_code | int) | not) or (.exit_code != $rc) then "verify_invalid"
  elif ((.ok | type) != "boolean") or (.ok != ($rc == 0)) then "verify_invalid"
  elif $rc == 3 then "not_installed"
  elif $rc == 9 then "unmanaged"
  elif $rc == 4 then "verify_unsafe"
  elif ($rc != 0) and ($rc != 5) then "verify_failed"
  elif .probes != "skipped" then "verify_invalid"
  elif (.managed != true) or (.profile != "raspiblitz") or (.install_state != "installed")
       or (.unit != $unit) or (.impl != $impl) then "unit_mismatch"
  elif .emergency_block == true then "emergency_block"
  elif .emergency_block != false then "verify_invalid"
  elif .verdict != (if $rc == 0 then "protected" else "degraded" end) then "verify_inconsistent"
  elif (.checks | type) != "array" then "verify_inconsistent"
  elif any(.checks[]; (type != "object") or ((.id | type) != "string") or ((.class | type) != "string")
           or ((.result | type) != "string")) then "verify_inconsistent"
  else .checks as $c
    | if any(req[]; . as $r | ([$c[] | select(.id == $r)] | length) != 1) then "verify_inconsistent"
      elif any($c[]; (.result != "pass") and (.result != "fail") and (.result != "skip")) then "verify_inconsistent"
      elif any($c[]; (.result == "fail") and (.class != "degraded")) then "verify_inconsistent"
      elif any($c[]; (.result == "skip") and (.id | isreq)) then "verify_inconsistent"
      else "ok" end
  end;
if (length != 1) or ((.[0] | type) != "object") then "verify_invalid"
else .[0]
  | (if (.checks | type) == "array" then [.checks[] | objects] else [] end) as $c
  | (if (.endpoint | type) == "object" then .endpoint else {} end) as $ep
  | [ reason,
      (.verdict | s), (if (.emergency_block | type) == "boolean" then (.emergency_block | tostring) else "" end),
      (.unit | s), ($ep.host | s),
      ($ep.vpn_port | if int and . >= 1 and . <= 65535 then tostring else "" end),
      ($ep.ipv4 | s),
      (one($c; "wg_endpoint") | .result | s), (one($c; "wg_endpoint") | .detail | s),
      (one($c; "wg_handshake") | .result | s), (one($c; "wg_handshake") | .detail | s)
    ] | join("\u001f")
end
JQ

# Validates verify result $1 (exit code) / $2 (document) for the guarded unit. Sets V_REASON (ok or
# the tor-only reason of the decision table) and the extracted fields.
its_verify_validate() {
    local rc="$1" doc="$2" out="" size impl="$G_IMPL"
    V_REASON="verify_invalid" V_VERDICT="" V_EMERG="" V_UNIT="" V_HOST="" V_PORT="" V_IPV4=""
    V_EP_RESULT="" V_EP_DETAIL="" V_HS_RESULT="" V_HS_DETAIL=""
    if [[ "$rc" == 124 ]] || [[ "$rc" == 137 ]]; then
        V_REASON="verify_timeout"
        return 0
    fi
    if [[ ! "$rc" =~ ^[0-9]+$ ]]; then
        V_REASON="verify_failed"
        return 0
    fi
    size=$(stat -c %s -- "$doc" 2>/dev/null) || size=$((ITS_DOC_MAX + 1))
    if [[ "$size" -gt "$ITS_DOC_MAX" ]]; then
        return 0
    fi
    [[ "$impl" == cl ]] && impl="cln"
    out=$(jq -r -s --argjson rc "$rc" --argjson contract "$TS_PIN_CONTRACT" --arg unit "$G_UNIT" \
        --arg impl "$impl" "$ITS_JQ_VALIDATE" "$doc" 2>/dev/null) || out=""
    IFS=$'\x1f' read -r V_REASON V_VERDICT V_EMERG V_UNIT V_HOST V_PORT V_IPV4 V_EP_RESULT V_EP_DETAIL \
        V_HS_RESULT V_HS_DETAIL <<< "$out"
    [[ -n "$V_REASON" ]] || V_REASON="verify_invalid"
    return 0
}

# CLN: is the endpoint IPv4 confirmed for the announcement? Both wg_endpoint (the live peer endpoint
# equals ipv4:port) and wg_handshake (younger than 180 s) passed, so the address completed a
# WireGuard handshake with the configured server key. Sets C_STATE: confirmed, wait (the tunnel is
# up but has no handshake yet: waiting can help), dns_unresolved, ipv4_invalid, endpoint_mismatch or
# tunnel_down (waiting cannot help).
its_cln_confirm() {
    if [[ -z "$V_IPV4" ]]; then
        C_STATE="dns_unresolved"
    elif ! its_valid_public_ipv4 "$V_IPV4"; then
        C_STATE="ipv4_invalid"
    elif [[ "$V_EP_RESULT" == pass ]] && [[ "$V_HS_RESULT" == pass ]]; then
        C_STATE="confirmed"
    elif [[ "$V_EP_RESULT" == pass ]]; then
        C_STATE="wait"
    else
        case "$V_EP_DETAIL" in
            *" is down") C_STATE="tunnel_down" ;;
            "live endpoint (none) differs"* | "live endpoint none differs"*) C_STATE="wait" ;;
            *) C_STATE="endpoint_mismatch" ;;
        esac
    fi
}

# One verify call plus validation. Sets V_* and V_RC, keeps the document path in V_DOC.
its_guard_verify_once() {
    local t="$1" start
    its_now
    start="$NOW_MS"
    if its_verify_run "$t"; then
        its_verify_validate "$Q_RC" "$Q_DOC"
        V_RC="$Q_RC"
        V_DOC="$Q_DOC"
    else
        V_REASON="verify_failed"
        V_RC=""
    fi
    its_now
    V_MS=$(( ${V_MS:-0} + NOW_MS - start ))
    V_ATTEMPTS=$(( ${V_ATTEMPTS:-0} + 1 ))
}

# The verify step of the guard, including the bounded CLN handshake wait: while the tunnel is up but
# the address is not yet confirmed only for lack of a handshake, verify runs again until
# TS_RB_HANDSHAKE_WAIT seconds have passed (each poll gets at least 5 s, at most the verify timeout).
# A poll that times out ends the wait with the last valid result; any other poll result replaces
# it. No wait for LND (it resolves externalhosts itself, announces the resolved address and resolves
# it again periodically) and none in --dry-run.
its_guard_verify() {
    local deadline remaining t keep us=$'\x1f'
    V_MS=0
    V_ATTEMPTS=0
    its_guard_verify_once "$TS_RB_VERIFY_TIMEOUT"
    [[ "$V_REASON" == ok ]] || return 0
    [[ "$G_IMPL" == cl ]] || return 0
    its_cln_confirm
    [[ "$C_STATE" == wait ]] && [[ "$G_DRY" -eq 0 ]] || return 0
    its_now
    deadline=$(( NOW_MS + TS_RB_HANDSHAKE_WAIT * 1000 ))
    while [[ "$C_STATE" == wait ]]; do
        its_now
        remaining=$(( deadline - NOW_MS ))
        (( remaining > 0 )) || break
        if (( remaining > TS_RB_HANDSHAKE_POLL * 1000 )); then
            sleep "$TS_RB_HANDSHAKE_POLL"
        else
            sleep "$(( (remaining + 999) / 1000 ))"
        fi
        its_now
        remaining=$(( (deadline - NOW_MS) / 1000 ))
        (( remaining >= 1 )) || break
        t="$remaining"
        (( t < 5 )) && t=5
        (( t > TS_RB_VERIFY_TIMEOUT )) && t="$TS_RB_VERIFY_TIMEOUT"
        keep="${V_REASON}${us}${V_RC}${us}${V_VERDICT}${us}${V_EMERG}${us}${V_UNIT}${us}${V_HOST}${us}${V_PORT}${us}${V_IPV4}${us}${V_EP_RESULT}${us}${V_EP_DETAIL}${us}${V_HS_RESULT}${us}${V_HS_DETAIL}${us}${V_DOC}"
        its_guard_verify_once "$t"
        if [[ "$V_REASON" == verify_timeout ]]; then
            IFS="$us" read -r V_REASON V_RC V_VERDICT V_EMERG V_UNIT V_HOST V_PORT V_IPV4 V_EP_RESULT \
                V_EP_DETAIL V_HS_RESULT V_HS_DETAIL V_DOC <<< "$keep"
            break
        fi
        [[ "$V_REASON" == ok ]] || return 0
        its_cln_confirm
    done
    [[ "$C_STATE" == wait ]] && C_STATE="no_handshake"
    return 0
}

# Renders the flags from the validated document (exact flags of the concept). Sets R_FLAGS,
# R_REASON (ok or announce_unconfirmed), R_DETAIL and the announce fields. Fails if the host or
# vpn_port is invalid (never a half-rendered flag).
its_render() {
    R_FLAGS="" R_REASON="" R_DETAIL=""
    its_valid_host "$V_HOST" && its_valid_port "$V_PORT" || return 1
    D_ANN_HOST="$V_HOST"
    D_ANN_PORT="$V_PORT"
    if [[ "$G_IMPL" == lnd ]]; then
        R_FLAGS="--tor.skip-proxy-for-clearnet-targets --externalhosts=${V_HOST}:${V_PORT}"
        R_REASON="ok"
        # LND resolves the host itself and announces the resolved address: the record keeps the
        # endpoint's address at this start, so CHECK can tell it from any other clearnet address
        if its_valid_public_ipv4 "$V_IPV4"; then
            D_ANN_IPV4="$V_IPV4"
        fi
    else
        [[ -n "${C_STATE:-}" ]] || its_cln_confirm
        if [[ "$C_STATE" == confirmed ]]; then
            R_FLAGS="--bind-addr=0.0.0.0:9735 --announce-addr=${V_IPV4}:${V_PORT} --always-use-proxy=false --announce-addr-discovered=false"
            R_REASON="ok"
            D_ANN_IPV4="$V_IPV4"
        else
            R_FLAGS="--bind-addr=0.0.0.0:9735 --always-use-proxy=false --announce-addr-discovered=false"
            R_REASON="announce_unconfirmed"
            [[ "$C_STATE" == wait ]] && C_STATE="no_handshake"
            R_DETAIL="$C_STATE"
        fi
    fi
    [[ "$R_FLAGS" =~ $ITS_VALUE_RE ]]
}

# ---------------------------------------------------------------------------------------------
# Start guard
# ---------------------------------------------------------------------------------------------

# Derives the guard context from implementation $1 (lnd|cl) and chain $2. Fails on other input.
its_guard_init() {
    local p
    case "$2" in
        mainnet) p="" ;;
        testnet) p="t" ;;
        signet) p="s" ;;
        *) return 1 ;;
    esac
    case "$1" in
        lnd) G_BASE="${p}lnd"; G_VAR="TUNNELSATS_LND_ARGS" ;;
        cl) G_BASE="${p}lightningd"; G_VAR="TUNNELSATS_CLN_ARGS" ;;
        *) return 1 ;;
    esac
    G_IMPL="$1"
    G_CHAIN="$2"
    G_UNIT="${G_BASE}.service"
    G_ENVF="${TS_RB_RUN_DIR}/hybrid-${G_BASE}.env"
    G_REC="${TS_RB_RUN_DIR}/guard-${G_BASE}.json"
    return 0
}

# Writes "<VAR>=<value>" to this unit's env file: atomic, root 0644, read back byte for byte.
# A dry run writes nothing and reports success.
its_guard_write_env() {
    local value="$1" tmp
    [[ "$value" =~ $ITS_VALUE_RE ]] || return 1
    [[ "$G_DRY" -eq 1 ]] && return 0
    its_run_dir_ok || return 1
    tmp=$(mktemp "${TS_RB_RUN_DIR}/.hybrid-${G_BASE}.XXXXXX" 2>/dev/null) || return 1
    if ! printf '%s=%s\n' "$G_VAR" "$value" > "$tmp" 2>/dev/null || ! chmod 0644 -- "$tmp" 2>/dev/null || \
        ! mv -fT -- "$tmp" "$G_ENVF" 2>/dev/null; then
        rm -f -- "$tmp"
        return 1
    fi
    printf '%s=%s\n' "$G_VAR" "$value" | cmp -s - "$G_ENVF"
}

its_guard_set() {
    D_DECISION="$1"
    D_REASON="$2"
    D_EXIT="$3"
}

its_guard_stray_log() {
    if [[ "$G_STRAY" -eq 1 ]]; then
        its_log "tunnelsats-guard[${G_UNIT}]: stray ${G_VAR} ignored (set outside the guard's env file)"
    fi
}

# At-rest audit of this unit's config (mainnet only reaches it). Repairs toward Tor-only, or plans
# the repair in a dry run. Fails if the config cannot be made Tor-only.
its_guard_at_rest() {
    local mode="repair" k
    [[ "$G_DRY" -eq 1 ]] && mode="plan"
    its_audit "$G_IMPL" "$(its_conf_file "$G_IMPL")" "$mode" "$G_BASE"
    D_AT_REST="$A_STATUS"
    for k in "${A_REPAIRED[@]}"; do
        its_log "tunnelsats-guard[${G_UNIT}]: at-rest repair: ${k} removed from ${A_CONF} (Tor-only at rest)"
    done
    [[ "$A_STATUS" != unrepairable ]]
}

# The decision (section 3 of the design): sets D_DECISION, D_REASON, D_DETAIL, D_FLAGS, D_EXIT.
its_guard_decide() {
    local inherited defines=0 tsflag tor tsimpl rc
    D_DECISION="" D_REASON="" D_DETAIL="" D_FLAGS="" D_EXIT=0 D_AT_REST="not_checked"
    D_ANN_HOST="" D_ANN_IPV4="" D_ANN_PORT=""
    A_REPAIRED=() A_BACKUP=""
    V_RC="" V_VERDICT="" V_EMERG="" V_UNIT="" V_MS="" V_ATTEMPTS="" V_DOC="" T_SHA="" C_STATE=""
    inherited="${!G_VAR:-}"
    its_conf_defines "$G_VAR" && defines=1
    tsflag=$(its_conf_get tunnelsats) || tsflag=""
    G_STRAY=0
    if [[ "$defines" -eq 1 ]] || { [[ -n "$inherited" ]] && [[ ! -e "$G_ENVF" ]]; }; then
        G_STRAY=1
    fi

    # Not a TunnelSats start (every node without TunnelSats, every test chain): never flags
    if [[ "$G_CHAIN" != mainnet ]] || [[ "$tsflag" != on ]]; then
        if [[ "$G_CHAIN" != mainnet ]]; then
            its_guard_set noop not_mainnet 0
        else
            its_guard_set noop tunnelsats_off 0
        fi
        if [[ -e "$G_ENVF" ]] || [[ -L "$G_ENVF" ]] || [[ -n "$inherited" ]] || [[ "$defines" -eq 1 ]]; then
            if ! its_guard_write_env ""; then
                its_guard_set blocked env_write_failed 1
                return 0
            fi
        fi
        its_guard_stray_log
        return 0
    fi

    # TunnelSats on, mainnet unit: from here on every exit leaves the empty value
    if ! its_guard_write_env ""; then
        its_guard_set blocked env_write_failed 1
        return 0
    fi
    its_guard_stray_log
    tor=$(its_conf_get runBehindTor) || tor=""
    if [[ "$tor" != on ]]; then
        its_guard_set blocked tor_off 1
        return 0
    fi
    if ! its_guard_at_rest; then
        its_guard_set blocked "at_rest_unrepairable:${A_WHY}" 1
        return 0
    fi
    tsimpl=$(its_conf_get tunnelsatsImpl) || tsimpl=""
    if [[ "$G_IMPL" != "$tsimpl" ]]; then
        its_guard_set tor-only other_impl 0
        return 0
    fi
    if [[ "$A_ELIGIBLE" -ne 1 ]]; then
        its_guard_set tor-only "not_eligible:${A_NE_REASON}" 0
        return 0
    fi
    its_tool_trust
    rc=$?
    if [[ "$rc" -eq 3 ]]; then
        its_guard_set tor-only tool_missing 0
        return 0
    elif [[ "$rc" -ne 0 ]]; then
        its_guard_set tor-only tool_untrusted 0
        return 0
    fi
    its_guard_verify
    if [[ "$V_REASON" != ok ]]; then
        its_guard_set tor-only "$V_REASON" 0
        return 0
    fi
    if ! its_render; then
        D_ANN_HOST="" D_ANN_IPV4="" D_ANN_PORT=""
        its_guard_set tor-only announce_invalid 0
        return 0
    fi
    if ! its_guard_write_env "$R_FLAGS"; then
        its_guard_write_env "" || true
        D_ANN_HOST="" D_ANN_IPV4="" D_ANN_PORT=""
        its_guard_set blocked env_write_failed 1
        return 0
    fi
    D_FLAGS="$R_FLAGS"
    D_DETAIL="$R_DETAIL"
    its_guard_set hybrid "$R_REASON" 0
    return 0
}

# Prints the decision document (the record at /run/tunnelsats/guard-<unit>.json).
its_guard_doc() {
    local boot="" inv="${INVOCATION_ID:-}" keys=""
    boot=$(head -c 64 -- "$TS_RB_BOOT_ID" 2>/dev/null | tr -d '\n') || boot=""
    [[ "$boot" =~ ^[0-9a-f-]{36}$ ]] || boot=""
    [[ "$inv" =~ ^[0-9a-f]{32}$ ]] || inv=""
    [[ ${#A_REPAIRED[@]} -gt 0 ]] && keys=$(IFS=,; printf '%s' "${A_REPAIRED[*]}")
    jq -n -c \
        --arg unit "$G_UNIT" --arg impl "$G_IMPL" --arg chain "$G_CHAIN" --arg boot "$boot" \
        --arg inv "$inv" --arg at "$D_AT" --arg decision "$D_DECISION" --arg reason "$D_REASON" \
        --arg detail "$D_DETAIL" --arg flags "$D_FLAGS" --arg ahost "$D_ANN_HOST" \
        --arg aipv4 "$D_ANN_IPV4" --arg aport "$D_ANN_PORT" --arg vrc "$V_RC" \
        --arg verdict "$V_VERDICT" --arg emerg "$V_EMERG" --arg vunit "$V_UNIT" --arg sha "$T_SHA" \
        --arg vms "$V_MS" --arg vatt "$V_ATTEMPTS" --arg rest "$D_AT_REST" --arg keys "$keys" \
        --arg backup "$A_BACKUP" --arg stray "$G_STRAY" '
        def nn: if . == "" then null else . end;
        def ni: if . == "" then null else tonumber end;
        {schema: "raspiblitz.tunnelsats.guard/1", unit: $unit, impl: $impl, chain: $chain,
         boot_id: ($boot | nn), invocation_id: ($inv | nn), decided_at: $at,
         decision: $decision, reason: $reason, detail: $detail, flags: $flags,
         announce: {host: ($ahost | nn), ipv4: ($aipv4 | nn), port: ($aport | ni)},
         verify: {rc: ($vrc | ni), verdict: ($verdict | nn),
                  emergency_block: (if $emerg == "true" then true elif $emerg == "false" then false else null end),
                  unit: ($vunit | nn), tool_sha256: ($sha | nn), duration_ms: ($vms | ni), attempts: ($vatt | ni)},
         at_rest: {status: $rest, repaired_keys: (if $keys == "" then [] else ($keys | split(",")) end),
                   backup: ($backup | nn)},
         stray: ($stray == "1")}'
}

# Writes the record and keeps the verify document of this decision (root 0644, atomic). A failed
# write is logged and never changes the decision: the env file is what protects.
its_guard_record() {
    local doc
    [[ "$G_DRY" -eq 1 ]] && return 0
    if [[ "$D_DECISION" == noop ]] && [[ ! -d "$TS_RB_RUN_DIR" ]]; then
        return 0
    fi
    if ! its_dir_safe "$TS_RB_RUN_DIR" || ! doc=$(its_guard_doc) || \
        ! its_atomic_write "$G_REC" "${doc}"$'\n' 0644; then
        its_log "tunnelsats-guard[${G_UNIT}]: the decision record could not be written"
        return 1
    fi
    if [[ -n "$V_DOC" ]] && [[ -f "$V_DOC" ]] && [[ "$(stat -c %s -- "$V_DOC" 2>/dev/null)" -le "$ITS_DOC_MAX" ]]; then
        chmod 0644 -- "$V_DOC" 2>/dev/null && mv -fT -- "$V_DOC" "${TS_RB_RUN_DIR}/guard-${G_BASE}.verify.json" 2>/dev/null || true
    fi
    return 0
}

its_guard_summary() {
    local ann="-" rep="-" dur
    if [[ "$D_DECISION" == hybrid ]]; then
        if [[ "$G_IMPL" == lnd ]]; then
            ann="${D_ANN_HOST}:${D_ANN_PORT}"
        elif [[ -n "$D_ANN_IPV4" ]]; then
            ann="${D_ANN_IPV4}:${D_ANN_PORT}"
        fi
    fi
    [[ ${#A_REPAIRED[@]} -gt 0 ]] && rep=$(IFS=,; printf '%s' "${A_REPAIRED[*]}")
    its_now
    dur=$(( NOW_MS - D_START ))
    its_log "tunnelsats-guard[${G_UNIT}]: decision=${D_DECISION} reason=${D_REASON}${D_DETAIL:+ detail=${D_DETAIL}} verify_rc=${V_RC:--} verdict=${V_VERDICT:--} emergency_block=${V_EMERG:--} announce=${ann} repaired=${rep} duration_ms=${dur}$([[ "$G_DRY" -eq 1 ]] && printf ' dry_run=1')"
}

# guard <lnd|cl> <mainnet|testnet|signet> [--dry-run] [--json]
# Exit 0: the start proceeds (noop, tor-only, hybrid). 1: blocked. 2: usage (blocks the start).
its_cmd_guard() {
    local json=0 a
    G_DRY=0
    its_now
    D_START="$NOW_MS"
    for a in "${@:3}"; do
        case "$a" in
            --dry-run) G_DRY=1 ;;
            --json) json=1 ;;
            *) its_log "tunnelsats-guard: usage: guard <lnd|cl> <mainnet|testnet|signet> [--dry-run] [--json]"; return 2 ;;
        esac
    done
    if ! its_guard_init "${1:-}" "${2:-}"; then
        its_log "tunnelsats-guard: usage: guard <lnd|cl> <mainnet|testnet|signet> [--dry-run] [--json]"
        return 2
    fi
    its_guard_decide
    D_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    its_guard_record
    its_guard_summary
    if [[ "$json" -eq 1 ]]; then
        its_guard_doc
    fi
    its_cleanup
    return "$D_EXIT"
}

# ---------------------------------------------------------------------------------------------
# audit <lnd|cl> [--repair] [--json]
# ---------------------------------------------------------------------------------------------

# Prints a document of this script: $1 = verb, $2 = exit code, $3 = errors (JSON array), then
# --arg/--argjson pairs and a jq object expression ($5...) merged into it.
its_doc() {
    local verb="$1" rc="$2" errors="$3" expr="$4"
    shift 4
    jq -n -c --arg command "its.${verb}" --argjson rc "$rc" --argjson errors "$errors" "$@" \
        '{contract: 1, command: $command, ok: ($rc == 0), exit_code: $rc, errors: $errors} + ('"$expr"')'
}

its_err() {   # $1 code, $2 class, $3 message
    jq -n -c --arg c "$1" --arg k "$2" --arg m "$3" '[{code: $c, class: $k, message: $m}]'
}

its_cmd_audit() {
    local impl="${1:-}" repair=0 json=0 a rc state errors="[]" keys lines
    for a in "${@:2}"; do
        case "$a" in
            --repair) repair=1 ;;
            --json) json=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
    done
    case "$impl" in
        lnd | cl) ;;
        *) its_usage >&2; return 2 ;;
    esac
    if [[ "$repair" -eq 1 ]]; then
        if ! its_is_root; then
            errors=$(its_err E_NOT_ROOT usage "audit --repair must run as root")
            [[ "$json" -eq 1 ]] && its_doc audit 2 "$errors" '{}'
            its_log "# audit --repair must run as root"
            return 2
        fi
        if [[ "$impl" == lnd ]]; then a="lnd.service"; else a="lightningd.service"; fi
        state=$("$TS_RB_SYSTEMCTL" show -p ActiveState --value -- "$a" 2>/dev/null) || state="unknown"
        case "$state" in
            inactive | failed | "") ;;
            *)
                errors=$(its_err E_UNIT_ACTIVE refused "${a} is ${state}: the start guard repairs the config at its next start")
                [[ "$json" -eq 1 ]] && its_doc audit 1 "$errors" '{status: "not_checked"}'
                its_log "# ${a} is ${state}: not repairing while it runs (the start guard repairs at its next start)"
                return 1
                ;;
        esac
        its_audit "$impl" "$(its_conf_file "$impl")" repair "${a%.service}"
    else
        its_audit "$impl" "$(its_conf_file "$impl")" check "$impl"
    fi
    case "$A_STATUS" in
        clean | repaired) rc=0 ;;
        drift) rc=4 ;;
        *) rc=1; errors=$(its_err E_AT_REST_UNREPAIRABLE operational "the config cannot be made Tor-only: ${A_WHY}") ;;
    esac
    if [[ ${#A_REPAIRED[@]} -gt 0 ]]; then
        keys=$(printf '%s\n' "${A_REPAIRED[@]}" | jq -R . | jq -s -c .)
    else
        keys=$(printf '%s\n' "${A_KEYS[@]}" | jq -R 'select(. != "")' | jq -s -c .)
    fi
    lines=$(printf '%s\n' "${A_LINES[@]}" | jq -R 'select(. != "")' | jq -s -c .)
    if [[ "$json" -eq 1 ]]; then
        its_doc audit "$rc" "$errors" '{impl: $impl, status: $status, reason: ($why | if . == "" then null else . end),
            keys: $keys, lines: $lines, eligible: ($eligible == "1"),
            not_eligible_reason: ($ne | if . == "" then null else . end),
            backup: ($backup | if . == "" then null else . end), config: ($conf | if . == "" then null else . end)}' \
            --arg impl "$impl" --arg status "$A_STATUS" --arg why "$A_WHY" --argjson keys "$keys" \
            --argjson lines "$lines" --arg eligible "$A_ELIGIBLE" --arg ne "$A_NE_REASON" --arg backup "$A_BACKUP" \
            --arg conf "$A_CONF"
    else
        echo "status=${A_STATUS}${A_WHY:+ reason=${A_WHY}} keys=$(IFS=,; printf '%s' "${A_KEYS[*]:-none}") eligible=${A_ELIGIBLE}${A_NE_REASON:+ not_eligible_reason=${A_NE_REASON}}"
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------------------------
# status [--json]: no network, no secrets, no home IP
# ---------------------------------------------------------------------------------------------

# Prints absent, empty, flags or invalid for env file $1.
its_env_state() {
    local f="$1" content re_empty='^TUNNELSATS_(LND|CLN)_ARGS=$' re_flags='^TUNNELSATS_(LND|CLN)_ARGS=--[A-Za-z0-9.:=/ -]+$'
    if [[ ! -e "$f" ]] && [[ ! -L "$f" ]]; then
        printf 'absent'
        return 0
    fi
    content=$(head -c 1024 -- "$f" 2>/dev/null) || content="-"
    if [[ "$content" =~ $re_empty ]]; then
        printf 'empty'
    elif [[ "$content" =~ $re_flags ]]; then
        printf 'flags'
    else
        printf 'invalid'
    fi
}

# Prints <decision>:<reason>@<decided_at> of guard record $1, or none.
its_guard_state() {
    local out
    [[ -f "$1" ]] || { printf 'none'; return 0; }
    out=$(jq -r 'select(.schema == "raspiblitz.tunnelsats.guard/1")
        | [.decision, .reason, .decided_at] | map(tostring | gsub("[^A-Za-z0-9_.:@-]"; "_")) | "\(.[0]):\(.[1])@\(.[2])"' \
        "$1" 2>/dev/null) || out=""
    printf '%s' "${out:-invalid}"
}

its_cmd_status() {
    local json=0 a impl ts tor pin tool_inst="no" tool_hash="n/a" dev="no" managed="n/a" vrc="n/a"
    local verdict="n/a" emerg="n/a" vunit="n/a" host="n/a" vport="n/a" strays="" out rc
    local g_lnd g_cl e_lnd e_cl rblock lrestore
    for a in "$@"; do
        case "$a" in
            --json) json=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
    done
    ts=$(its_conf_get tunnelsats) || ts="off"
    impl=$(its_conf_get tunnelsatsImpl) || impl="-"
    tor=$(its_conf_get runBehindTor) || tor="off"
    [[ "$ts" =~ ^[a-z]{1,8}$ ]] || ts="invalid"
    [[ "$impl" =~ ^(lnd|cl|-)$ ]] || impl="invalid"
    [[ "$tor" =~ ^[a-z]{1,8}$ ]] || tor="invalid"
    pin="${TS_PIN_VERSION}@${TS_PIN_COMMIT:0:12}"
    [[ -n "$(its_dev_override_sha)" ]] && dev="yes"
    its_tool_trust
    rc=$?
    if [[ "$rc" -ne 3 ]]; then
        tool_inst="yes"
        if [[ "$T_SHA" == "$TS_PIN_SHA256" ]]; then
            tool_hash="current"
        elif [[ "$rc" -eq 0 ]]; then
            tool_hash="accepted_older"
        else
            tool_hash="unknown"
        fi
    fi
    if [[ "$rc" -eq 0 ]] && its_is_root; then
        G_BASE="status"
        if its_verify_run "$TS_RB_VERIFY_TIMEOUT"; then
            vrc="$Q_RC"
            out=$(jq -r -s 'def v(f): (try f catch null) as $x | if $x == null then "n/a" else $x end;
                if length == 1 and (.[0] | type) == "object" then .[0] else {} end
                | [v(.managed), v(.verdict), v(.emergency_block), v(.unit), v(.endpoint.host), v(.endpoint.vpn_port)]
                | map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f")' "$Q_DOC" 2>/dev/null) || out=""
            IFS=$'\x1f' read -r managed verdict emerg vunit host vport <<< "$out"
            case "$managed" in true) managed="yes" ;; false) managed="no" ;; *) managed="n/a" ;; esac
            [[ "$verdict" =~ ^[a-z_]{1,20}$ ]] || verdict="n/a"
            [[ "$emerg" =~ ^(true|false)$ ]] || emerg="n/a"
            [[ "$vunit" =~ ^[a-z]{1,16}\.service$ ]] || vunit="n/a"
            its_valid_host "$host" || host="n/a"
            its_valid_port "$vport" || vport="n/a"
        fi
        its_cleanup
    fi
    g_lnd=$(its_guard_state "${TS_RB_RUN_DIR}/guard-lnd.json")
    g_cl=$(its_guard_state "${TS_RB_RUN_DIR}/guard-lightningd.json")
    e_lnd=$(its_env_state "${TS_RB_RUN_DIR}/hybrid-lnd.env")
    e_cl=$(its_env_state "${TS_RB_RUN_DIR}/hybrid-lightningd.env")
    its_conf_defines TUNNELSATS_LND_ARGS && strays+="TUNNELSATS_LND_ARGS,"
    its_conf_defines TUNNELSATS_CLN_ARGS && strays+="TUNNELSATS_CLN_ARGS,"
    strays="${strays%,}"
    rblock=$(its_block_state_word)
    lrestore=$(its_last_restore_word)
    if [[ "$json" -eq 1 ]]; then
        its_doc status 0 '[]' '{tunnelsats: $ts, tunnelsatsImpl: $impl, runBehindTor: $tor, pin: $pin,
            tool_installed: $ti, tool_hash: $th, dev_override: $dev, managed: $managed, verify_rc: $vrc,
            verdict: $verdict, emergency_block: $emerg, unit: $vunit, endpoint_host: $host, vpn_port: $vport,
            guard_lnd: $glnd, guard_lightningd: $gcl, env_lnd: $elnd, env_lightningd: $ecl,
            stray_definitions: $strays, restore_block: $rblock, last_restore: $lrestore}' \
            --arg ts "$ts" --arg impl "$impl" --arg tor "$tor" --arg pin "$pin" --arg ti "$tool_inst" \
            --arg th "$tool_hash" --arg dev "$dev" --arg managed "$managed" --arg vrc "$vrc" \
            --arg verdict "$verdict" --arg emerg "$emerg" --arg vunit "$vunit" --arg host "$host" \
            --arg vport "$vport" --arg glnd "$g_lnd" --arg gcl "$g_cl" --arg elnd "$e_lnd" \
            --arg ecl "$e_cl" --arg strays "${strays:-none}" --arg rblock "$rblock" --arg lrestore "$lrestore"
        return 0
    fi
    echo "tunnelsats=${ts} tunnelsatsImpl=${impl} runBehindTor=${tor}"
    echo "pin=${pin} tool_installed=${tool_inst} tool_hash=${tool_hash} dev_override=${dev}"
    echo "managed=${managed} verify_rc=${vrc} verdict=${verdict} emergency_block=${emerg} unit=${vunit}"
    echo "endpoint_host=${host} vpn_port=${vport}"
    echo "guard_lnd=${g_lnd} guard_lightningd=${g_cl}"
    echo "env_lnd=${e_lnd} env_lightningd=${e_cl} stray_definitions=${strays:-none}"
    echo "restore_block=${rblock} last_restore=${lrestore}"
    return 0
}

# ---------------------------------------------------------------------------------------------
# State directory, journal, documents of this script
# ---------------------------------------------------------------------------------------------

its_state_dir() {
    printf '%s' "${TS_RB_APPDATA}/tunnelsats"
}

# Makes sure the state directory (root 0700) exists and, given $1, its subdirectory $1 (root 0700).
its_state_subdir() {
    local s="${TS_RB_APPDATA}/tunnelsats"
    if [[ ! -d "$s" ]]; then
        mkdir -m 0700 -- "$s" 2>/dev/null || return 1
    fi
    [[ -n "${1:-}" ]] || return 0
    if [[ ! -d "${s}/$1" ]]; then
        mkdir -m 0700 -- "${s}/$1" 2>/dev/null || return 1
    fi
    return 0
}

its_dist_file() {
    printf '%s' "${TS_RB_APPDATA}/tunnelsats/dist/tunnelsats-${TS_PIN_VERSION}-${TS_PIN_COMMIT:0:12}.sh"
}

# Journal line with tag $1 (best effort).
its_journal() {
    "$TS_RB_LOGGER" -t "$1" -- "$2" >/dev/null 2>&1 || true
}

# Copies $1 to $2 atomically with mode $3 (temp file next to the target, fsync, rename).
its_atomic_copy() {
    local tmp
    tmp=$(mktemp "${2%/*}/.${2##*/}.XXXXXX" 2>/dev/null) || return 1
    if ! cp -- "$1" "$tmp" 2>/dev/null || ! chmod "$3" -- "$tmp" 2>/dev/null || ! sync -- "$tmp" 2>/dev/null || \
        ! mv -fT -- "$tmp" "$2" 2>/dev/null; then
        rm -f -- "$tmp"
        return 1
    fi
    return 0
}

# Prints a failure document of this script: $1 verb, $2 exit code, $3 code, $4 class, $5 message.
its_fail_doc() {
    its_doc "$1" "$2" "$(its_err "$3" "$4" "$5")" '{}'
    its_log "# ${1}: ${3}: ${5}"
}

its_require_root() {
    its_is_root && return 0
    its_fail_doc "$1" 2 E_NOT_ROOT usage "${1} must run as root"
    return 1
}

# Succeeds if the stored WireGuard config is a regular root 0600 file with PrivateKey and Endpoint.
its_stored_conf_ok() {
    local f="$1" st
    [[ -f "$f" ]] && [[ ! -L "$f" ]] || return 1
    st=$(stat -c '%u %a' -- "$f" 2>/dev/null) || return 1
    [[ "$st" == "${TS_RB_ROOT_UID} 600" ]] || return 1
    grep -Eq '^[[:space:]]*PrivateKey[[:space:]]*=' "$f" && grep -Eq '^[[:space:]]*Endpoint[[:space:]]*=' "$f"
}

# ---------------------------------------------------------------------------------------------
# fetch [--offline] [--json]: the pinned tunnelsats.sh (commit, web-flow signature, sha256)
# ---------------------------------------------------------------------------------------------

its_fetch_reset() {
    F_PATH="" F_ACTUAL="" F_SIG="not_checked" F_SOURCE="$1" F_CODE="" F_CLASS="operational" F_MSG=""
}

its_fetch_fail() {
    F_CODE="$1"
    F_CLASS="$2"
    F_MSG="$3"
}

# The stored copy, no network: used only if its sha256 equals the pin (it was verified when it was
# stored); a copy that does not is deleted. Returns 0, 3 (not fetched yet) or 1 (hash mismatch).
its_fetch_offline() {
    local f sha
    its_fetch_reset stored
    f="$(its_dist_file)"
    if [[ -L "$f" ]] || [[ ! -f "$f" ]]; then
        its_fetch_fail E_NOT_FETCHED not_configured "no stored copy of tunnelsats.sh ${TS_PIN_VERSION} (run fetch)"
        return 3
    fi
    sha=$(sha256sum -- "$f" 2>/dev/null) || sha=""
    F_ACTUAL="${sha%% *}"
    if [[ "$F_ACTUAL" != "$TS_PIN_SHA256" ]]; then
        rm -f -- "$f"
        its_fetch_fail E_HASH_MISMATCH integrity "the stored copy does not match the pinned sha256 and was deleted"
        return 1
    fi
    F_PATH="$f"
    F_SIG="stored"
    return 0
}

# Seconds left of the fetch budget (F_DEADLINE), at most 120 per step. Fails when none is left.
its_fetch_left() {
    local left
    its_now
    left=$(( (F_DEADLINE - NOW_MS) / 1000 ))
    (( left >= 1 )) || return 1
    (( left <= 120 )) || left=120
    printf '%s' "$left"
}

# git for the download: clean environment (no user or system config, no prompts), the time left.
its_git() {
    local t
    t=$(its_fetch_left) || return 124
    env -i PATH="$ITS_SAFE_PATH" HOME="$F_HOME" LC_ALL=C GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 \
        timeout --kill-after=5 "$t" git "$@" </dev/null >/dev/null 2>&1
}

# Downloads exactly the pinned commit (shallow, sparse, one blob), then checks the commit id, the
# web-flow signature (blitz.git-verify.sh, commit mode), the sha256 and the VERSION and TS_CONTRACT
# lines, and stores the copy atomically (root 0644 in the root 0700 state directory). Never a
# branch, never an unpinned file. All network steps share TS_RB_FETCH_BUDGET seconds.
its_fetch_online() {
    local d repo head sha f old t rc
    its_fetch_reset network
    its_now
    F_DEADLINE=$(( NOW_MS + TS_RB_FETCH_BUDGET * 1000 ))
    if ! its_state_subdir dist || ! d=$(mktemp -d "$(its_tool_tmp_base)/.tunnelsats-fetch.XXXXXX" 2>/dev/null); then
        its_fetch_fail E_DOWNLOAD_FAILED operational "the temp or state directory cannot be used"
        return 1
    fi
    ITS_TMPDIRS+=("$d")
    repo="${d}/repo"
    F_HOME="${d}/home"
    mkdir -p -- "$repo" "$F_HOME"
    if ! its_git -C "$repo" init -q || ! its_git -C "$repo" remote add origin "$TS_REPO_URL" || \
        ! its_git -C "$repo" config remote.origin.promisor true || \
        ! its_git -C "$repo" config remote.origin.partialclonefilter blob:none || \
        ! its_git -C "$repo" sparse-checkout set --no-cone /scripts/tunnelsats.sh || \
        ! its_git -C "$repo" fetch -q --depth 1 --filter=blob:none origin "$TS_PIN_COMMIT" || \
        ! its_git -C "$repo" checkout -q --detach FETCH_HEAD; then
        if its_fetch_left >/dev/null; then
            its_fetch_fail E_DOWNLOAD_FAILED operational "downloading commit ${TS_PIN_COMMIT:0:12} failed"
        else
            its_fetch_fail E_DOWNLOAD_FAILED operational "downloading commit ${TS_PIN_COMMIT:0:12} did not finish within ${TS_RB_FETCH_BUDGET} s"
        fi
        return 1
    fi
    head=$(env -i PATH="$ITS_SAFE_PATH" HOME="$F_HOME" LC_ALL=C GIT_CONFIG_NOSYSTEM=1 git -C "$repo" rev-parse HEAD 2>/dev/null) || head=""
    if [[ "$head" != "$TS_PIN_COMMIT" ]]; then
        its_fetch_fail E_PIN_MISMATCH integrity "the downloaded commit is not the pinned one"
        return 1
    fi
    if ! t=$(its_fetch_left); then
        its_fetch_fail E_DOWNLOAD_FAILED operational "the download did not finish within ${TS_RB_FETCH_BUDGET} s"
        return 1
    fi
    (cd "$repo" && timeout --kill-after=5 "$t" "${TS_RB_ROOT}/config.scripts/blitz.git-verify.sh" "$TS_PIN_SIGNER" \
        "$TS_PIN_KEY_URL" "$TS_PIN_KEY_FPR") >&2 </dev/null
    rc=$?
    if [[ "$rc" -eq 124 ]] || [[ "$rc" -eq 137 ]]; then
        its_fetch_fail E_DOWNLOAD_FAILED operational "the signature check did not finish within ${TS_RB_FETCH_BUDGET} s"
        return 1
    elif [[ "$rc" -ne 0 ]]; then
        F_SIG="bad"
        its_fetch_fail E_SIGNATURE integrity "the signature of the pinned commit could not be verified (signer ${TS_PIN_SIGNER}, key ${TS_PIN_KEY_FPR})"
        return 1
    fi
    F_SIG="good"
    sha=$(sha256sum -- "${repo}/scripts/tunnelsats.sh" 2>/dev/null) || sha=""
    F_ACTUAL="${sha%% *}"
    if [[ "$F_ACTUAL" != "$TS_PIN_SHA256" ]]; then
        its_fetch_fail E_HASH_MISMATCH integrity "scripts/tunnelsats.sh does not match the pinned sha256"
        return 1
    fi
    if ! grep -qxF "VERSION=\"${TS_PIN_VERSION}\"" "${repo}/scripts/tunnelsats.sh" || \
        ! grep -qxF "TS_CONTRACT=${TS_PIN_CONTRACT}" "${repo}/scripts/tunnelsats.sh"; then
        its_fetch_fail E_CONTRACT integrity "the VERSION or TS_CONTRACT line differs from the pin"
        return 1
    fi
    f="$(its_dist_file)"
    if ! its_atomic_copy "${repo}/scripts/tunnelsats.sh" "$f" 0644; then
        its_fetch_fail E_WRITE_FAILED operational "the verified copy could not be stored"
        return 1
    fi
    for old in "${f%/*}"/tunnelsats-*.sh; do
        if [[ -e "$old" ]] && [[ "$old" != "$f" ]]; then
            rm -f -- "$old"
        fi
    done
    F_PATH="$f"
    return 0
}

# fetch --dev-override FILE --dev-sha256 HEX (development only, absent from menus and provisioning):
# a root-owned file with an explicitly given sha256, stored as dist/dev-override.sh. The guard
# accepts that hash for this boot only (run directory); restore and REPAIR keep using the pin.
its_fetch_dev() {
    local src="$1" want="$2" st sha f
    its_fetch_reset dev_override
    if [[ ! "$want" =~ ^[0-9a-f]{64}$ ]] || [[ -L "$src" ]] || [[ ! -f "$src" ]]; then
        its_fetch_fail E_USAGE usage "--dev-override needs a regular file and --dev-sha256 with 64 hex digits"
        return 2
    fi
    st=$(stat -c '%u %a' -- "$src" 2>/dev/null) || st="none 777"
    if [[ "${st%% *}" != "$TS_RB_ROOT_UID" ]] || (( (8#${st##* } & 8#022) != 0 )); then
        its_fetch_fail E_DEV_OVERRIDE refused "the override file must be owned by root and not writable by others"
        return 1
    fi
    sha=$(sha256sum -- "$src" 2>/dev/null) || sha=""
    F_ACTUAL="${sha%% *}"
    if [[ "$F_ACTUAL" != "$want" ]]; then
        its_fetch_fail E_HASH_MISMATCH integrity "the override file does not match --dev-sha256"
        return 1
    fi
    f="${TS_RB_APPDATA}/tunnelsats/dist/dev-override.sh"
    if ! its_state_subdir dist || ! its_run_dir_ok || ! its_atomic_copy "$src" "$f" 0644 || \
        ! its_atomic_write "${TS_RB_RUN_DIR}/dev-override.sha256" "${want}"$'\n' 0644; then
        its_fetch_fail E_WRITE_FAILED operational "the override could not be stored"
        return 1
    fi
    F_PATH="$f"
    its_journal tunnelsats "DEV OVERRIDE: tunnelsats.sh with sha256 ${want} accepted until the next boot"
    its_log "# DEV OVERRIDE registered for this boot (sha256 ${want}); restore and REPAIR keep using the pin"
    return 0
}

its_fetch_doc() {
    local rc="$1" errors="[]"
    [[ -n "$F_CODE" ]] && errors=$(its_err "$F_CODE" "$F_CLASS" "$F_MSG")
    its_doc fetch "$rc" "$errors" '{pinned_version: $pv, pinned_commit: $pc, pinned_sha256: $ps,
        actual_sha256: ($actual | if . == "" then null else . end),
        signature: {result: $sig, signer: $signer, fingerprint: $fpr},
        source: $src, path: ($path | if . == "" then null else . end),
        error: ($code | if . == "" then null else . end)}' \
        --arg pv "$TS_PIN_VERSION" --arg pc "$TS_PIN_COMMIT" --arg ps "$TS_PIN_SHA256" --arg actual "$F_ACTUAL" \
        --arg sig "$F_SIG" --arg signer "$TS_PIN_SIGNER" --arg fpr "$TS_PIN_KEY_FPR" --arg src "$F_SOURCE" \
        --arg path "$F_PATH" --arg code "$F_CODE"
}

its_cmd_fetch() {
    local offline=0 json=0 dev_file="" dev_sha="" rc
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --offline) offline=1 ;;
            --json) json=1 ;;
            --dev-override) dev_file="${2:-}"; shift ;;
            --dev-sha256) dev_sha="${2:-}"; shift ;;
            *) its_usage >&2; return 2 ;;
        esac
        shift
    done
    its_require_root fetch || return 2
    if [[ -n "$dev_file" ]] || [[ -n "$dev_sha" ]]; then
        its_fetch_dev "$dev_file" "$dev_sha"
    elif [[ "$offline" -eq 1 ]]; then
        its_fetch_offline
    else
        its_fetch_online
    fi
    rc=$?
    its_cleanup
    if [[ "$json" -eq 1 ]]; then
        its_fetch_doc "$rc"
    elif [[ "$rc" -eq 0 ]]; then
        echo "# fetch: ok (${F_SOURCE}, signature ${F_SIG}): ${F_PATH}"
    else
        echo "# fetch: ${F_CODE}: ${F_MSG}"
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------------------------
# Contract calls to the pinned tool: install, uninstall, verify, detect (cl becomes cln only here)
# ---------------------------------------------------------------------------------------------

# Runs script $1 (it must hash to $2) from a private root 0700 copy, with timeout $3 seconds, in a
# clean environment with stdin /dev/null; arguments $4... Sets X_RC and X_DOC (stdout, capped);
# stderr (progress) passes through.
its_tool_run() {
    local src="$1" sha="$2" t="$3" dir copy got
    shift 3
    X_RC=1
    X_DOC=""
    dir=$(mktemp -d "$(its_tool_tmp_base)/.tunnelsats-tool.XXXXXX" 2>/dev/null) || return 1
    ITS_TMPDIRS+=("$dir")
    copy="${dir}/tunnelsats.sh"
    cp -- "$src" "$copy" 2>/dev/null || return 1
    got=$(sha256sum -- "$copy" 2>/dev/null) || return 1
    [[ "${got%% *}" == "$sha" ]] || return 1
    env -i PATH="$ITS_SAFE_PATH" LC_ALL=C.UTF-8 timeout --kill-after=10 "$t" bash "$copy" "$@" </dev/null |
        head -c "$ITS_OUT_MAX" > "${dir}/out"
    X_RC="${PIPESTATUS[0]}"
    X_DOC="${dir}/out"
    return 0
}

# Prints the tool's document unchanged and returns its exit code. A timeout, a missing or broken
# document or another contract becomes a document of this script ($1 = verb).
its_pass_through() {
    local verb="$1" contract
    if [[ "$X_RC" == 124 ]] || [[ "$X_RC" == 137 ]]; then
        its_fail_doc "$verb" 1 E_TIMEOUT operational "tunnelsats.sh ${verb} did not finish in time"
        return 1
    fi
    contract=$(jq -r -s 'if length == 1 and (.[0] | type) == "object" then (.[0].contract | tostring) else "invalid" end' \
        "$X_DOC" 2>/dev/null) || contract="invalid"
    if [[ "$contract" == invalid ]]; then
        its_fail_doc "$verb" 1 E_TOOL_OUTPUT operational "tunnelsats.sh ${verb} printed no single JSON document (exit ${X_RC})"
        return 1
    fi
    if [[ "$contract" != "$TS_PIN_CONTRACT" ]]; then
        its_fail_doc "$verb" 1 E_CONTRACT integrity "tunnelsats.sh speaks contract ${contract:0:16}, RaspiBlitz pins ${TS_PIN_CONTRACT}"
        return 1
    fi
    cat -- "$X_DOC"
    return "$X_RC"
}

# Runs the tool and prints its document (json $1 = 1) or its plain output. $2 verb, $3 script,
# $4 sha256, $5 timeout, then the tool's arguments.
its_tool_out() {
    local json="$1" verb="$2" src="$3" sha="$4" t="$5" rc
    shift 5
    [[ "$json" -eq 1 ]] && set -- "$@" --json
    if ! its_tool_run "$src" "$sha" "$t" "$@"; then
        its_fail_doc "$verb" 1 E_TOOL_COPY operational "the verified tunnelsats.sh could not be prepared for ${verb}"
        its_cleanup
        return 1
    fi
    if [[ "$json" -eq 1 ]]; then
        its_pass_through "$verb"
        rc=$?
    else
        cat -- "$X_DOC"
        rc="$X_RC"
    fi
    its_cleanup
    return "$rc"
}

# install --impl <lnd|cl> [--json]: the verified stored copy runs install --managed raspiblitz.
its_cmd_install() {
    local impl="" cimpl json=0 dev=0 conf src sha rc
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --impl) impl="${2:-}"; shift ;;
            --json) json=1 ;;
            --dev-override) dev=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
        shift
    done
    case "$impl" in
        lnd) cimpl="lnd" ;;
        cl) cimpl="cln" ;;
        *) its_fail_doc install 2 E_USAGE usage "install needs --impl lnd or --impl cl"; return 2 ;;
    esac
    its_require_root install || return 2
    its_run_dir_ok || true
    conf="$(its_state_dir)/tunnelsats.conf"
    if ! its_stored_conf_ok "$conf"; then
        its_fail_doc install 3 E_NOT_CONFIGURED not_configured "no stored TunnelSats config (root 0600 with PrivateKey and Endpoint)"
        return 3
    fi
    if [[ "$dev" -eq 1 ]]; then
        src="$(its_state_dir)/dist/dev-override.sh"
        sha=$(its_dev_override_sha)
        if [[ -z "$sha" ]] || [[ ! -f "$src" ]]; then
            its_fail_doc install 1 E_DEV_OVERRIDE refused "no development override registered for this boot"
            return 1
        fi
    else
        its_fetch_offline
        rc=$?
        if [[ "$rc" -ne 0 ]]; then
            its_fail_doc install "$rc" "$F_CODE" "$F_CLASS" "$F_MSG"
            return "$rc"
        fi
        src="$F_PATH"
        sha="$TS_PIN_SHA256"
    fi
    its_tool_out "$json" install "$src" "$sha" 900 install --managed raspiblitz --impl "$cimpl" --network mainnet \
        --config "$conf" --non-interactive --yes
}

# adopt --impl <lnd|cl> [--json]: the verified stored copy runs adopt --managed raspiblitz.
its_cmd_adopt() {
    local impl="" cimpl json=0 dev=0 conf src sha rc
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --impl) impl="${2:-}"; shift ;;
            --json) json=1 ;;
            --dev-override) dev=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
        shift
    done
    case "$impl" in
        lnd) cimpl="lnd" ;;
        cl) cimpl="cln" ;;
        *) its_fail_doc adopt 2 E_USAGE usage "adopt needs --impl lnd or --impl cl"; return 2 ;;
    esac
    its_require_root adopt || return 2
    its_run_dir_ok || true
    conf="$(its_state_dir)/tunnelsats.conf"
    if ! its_stored_conf_ok "$conf"; then
        its_fail_doc adopt 3 E_NOT_CONFIGURED not_configured "no stored TunnelSats config (root 0600 with PrivateKey and Endpoint)"
        return 3
    fi
    if [[ "$dev" -eq 1 ]]; then
        src="$(its_state_dir)/dist/dev-override.sh"
        sha=$(its_dev_override_sha)
        if [[ -z "$sha" ]] || [[ ! -f "$src" ]]; then
            its_fail_doc adopt 1 E_DEV_OVERRIDE refused "no development override registered for this boot"
            return 1
        fi
    else
        its_fetch_offline
        rc=$?
        if [[ "$rc" -ne 0 ]]; then
            its_fail_doc adopt "$rc" "$F_CODE" "$F_CLASS" "$F_MSG"
            return "$rc"
        fi
        src="$F_PATH"
        sha="$TS_PIN_SHA256"
    fi
    its_tool_out "$json" adopt "$src" "$sha" 900 adopt --managed raspiblitz --impl "$cimpl" --network mainnet \
        --config "$conf" --non-interactive --yes
}

# Selects the installed tool when it is trusted, else the verified stored copy. Sets S_SRC, S_SHA.
its_select_tool() {
    if its_tool_trust; then
        S_SRC="$TS_RB_TOOL"
        S_SHA="$T_SHA"
        return 0
    fi
    its_fetch_offline || return $?
    S_SRC="$F_PATH"
    S_SHA="$TS_PIN_SHA256"
    return 0
}

# uninstall [--json]: uninstall --managed with the installed tool if trusted, else the stored copy.
its_cmd_uninstall() {
    local json=0 a rc
    for a in "$@"; do
        case "$a" in
            --json) json=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
    done
    its_require_root uninstall || return 2
    its_select_tool
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        its_fail_doc uninstall "$rc" "$F_CODE" "$F_CLASS" "$F_MSG"
        return "$rc"
    fi
    its_tool_out "$json" uninstall "$S_SRC" "$S_SHA" 600 uninstall --managed --non-interactive --yes
}

# verify [--no-probe] [--json]: the installed tool after the trust check; without an install the
# stored copy (it answers not installed or unmanaged). An untrusted installed tool is refused.
its_cmd_verify() {
    local json=0 t=120 a rc
    local -a args=(verify)
    for a in "$@"; do
        case "$a" in
            --json) json=1 ;;
            --no-probe) args+=(--no-probe); t=35 ;;
            *) its_usage >&2; return 2 ;;
        esac
    done
    its_require_root verify || return 2
    its_tool_trust
    rc=$?
    if [[ "$rc" -eq 4 ]]; then
        its_fail_doc verify 1 E_TOOL_UNTRUSTED integrity "the installed tunnelsats tool is not a pinned version (REPAIR installs the pinned one)"
        return 1
    fi
    its_select_tool
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        its_fail_doc verify "$rc" "$F_CODE" "$F_CLASS" "$F_MSG"
        return "$rc"
    fi
    its_tool_out "$json" verify "$S_SRC" "$S_SHA" "$t" "${args[@]}"
}

# detect [--json]: read-only, the verified stored copy (fetched first if needed).
its_cmd_detect() {
    local json=0 a
    for a in "$@"; do
        case "$a" in
            --json) json=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
    done
    its_require_root detect || return 2
    if ! its_fetch_offline && ! its_fetch_online; then
        its_cleanup
        its_fail_doc detect 1 "$F_CODE" "$F_CLASS" "$F_MSG"
        return 1
    fi
    its_tool_out "$json" detect "$F_PATH" "$TS_PIN_SHA256" 120 detect
}

# ---------------------------------------------------------------------------------------------
# The marked block in custom-installs.sh (restore after an SD-card update)
# ---------------------------------------------------------------------------------------------

ITS_BLOCK_BEGIN="# >>> TunnelSats block (managed by internet.tunnelsats.sh, do not edit) >>>"
ITS_BLOCK_END="# <<< TunnelSats block <<<"

# The block, POSIX sh, no exit, every command inside if or ||: a set -e in the user's file cannot
# stop at the block and the block cannot end the file early.
its_block_text() {
    cat <<'EOF'
# >>> TunnelSats block (managed by internet.tunnelsats.sh, do not edit) >>>
# Restores the TunnelSats tunnel after an SD-card update; Lightning stays Tor-only until it is back.
if [ -x /home/admin/config.scripts/internet.tunnelsats.sh ]; then
  /home/admin/config.scripts/internet.tunnelsats.sh restore || echo "# TunnelSats: restore failed (exit $?); Lightning stays Tor-only. SSH menu > SUBSCRIBE > TunnelSats > REPAIR"
else
  echo "# TunnelSats: this RaspiBlitz image has no TunnelSats integration; Lightning stays Tor-only"
fi
# <<< TunnelSats block <<<
EOF
}

# Succeeds if custom-installs file $1 may be read and rewritten: a regular file (not a symlink), at
# most 1 MiB, no NUL bytes. Sets B_CODE/B_MSG otherwise.
its_custom_file_ok() {
    local f="$1" size n
    B_CODE="" B_MSG=""
    if [[ -L "$f" ]] || [[ ! -f "$f" ]]; then
        B_CODE="E_CUSTOM_INSTALLS_UNSAFE"; B_MSG="${f} is not a regular file"
        return 1
    fi
    size=$(stat -c %s -- "$f" 2>/dev/null) || size=-1
    if [[ "$size" -lt 0 ]] || [[ "$size" -gt 1048576 ]]; then
        B_CODE="E_CUSTOM_INSTALLS_UNSAFE"; B_MSG="${f} cannot be read or is larger than 1 MiB"
        return 1
    fi
    n=$(tr -d '\000' < "$f" 2>/dev/null | wc -c) || n=-1
    if [[ "$n" != "$size" ]]; then
        B_CODE="E_CUSTOM_INSTALLS_UNSAFE"; B_MSG="${f} holds NUL bytes"
        return 1
    fi
    return 0
}

# The block text; with $1 = 1 without the final newline (it then ends a file that had none).
its_block_emit() {
    if [[ "${1:-0}" -eq 1 ]]; then
        printf '%s' "$(its_block_text)"
    else
        its_block_text
    fi
}

# Scans file $1 for the markers (whole lines, a trailing CR ignored for the comparison). Sets
# B_STATE (absent, present, malformed), B_BEGIN and B_END (line numbers), B_MARKERS and B_NLINES.
its_block_scan() {
    local f="$1" i line nb=0 ne=0
    local -a lines=()
    B_STATE="absent" B_BEGIN=0 B_END=0 B_MARKERS=() B_NLINES=0
    mapfile -t lines < "$f" || return 1
    B_NLINES=${#lines[@]}
    for i in "${!lines[@]}"; do
        line="${lines[i]%$'\r'}"
        if [[ "$line" == "$ITS_BLOCK_BEGIN" ]]; then
            nb=$((nb + 1)); B_BEGIN=$((i + 1)); B_MARKERS+=("$((i + 1))")
        elif [[ "$line" == "$ITS_BLOCK_END" ]]; then
            ne=$((ne + 1)); B_END=$((i + 1)); B_MARKERS+=("$((i + 1))")
        fi
    done
    if [[ "$nb" -eq 0 ]] && [[ "$ne" -eq 0 ]]; then
        B_STATE="absent"
    elif [[ "$nb" -eq 1 ]] && [[ "$ne" -eq 1 ]] && [[ "$B_BEGIN" -lt "$B_END" ]]; then
        B_STATE="present"
    else
        B_STATE="malformed"
    fi
    return 0
}

# Succeeds if the block scanned in file $1 is present and its END marker ends the file without a
# newline (the file had no final newline before the block was added).
its_block_at_eof_nonl() {
    [[ "$B_STATE" == present ]] && [[ "$B_END" -eq "$B_NLINES" ]] && [[ -n "$(tail -c 1 -- "$1")" ]]
}

its_block_state_word() {
    if [[ ! -e "$TS_RB_CUSTOM" ]] && [[ ! -L "$TS_RB_CUSTOM" ]]; then
        printf 'absent'
    elif its_custom_file_ok "$TS_RB_CUSTOM" && its_block_scan "$TS_RB_CUSTOM"; then
        printf '%s' "$B_STATE"
    else
        printf 'invalid'
    fi
}

# Prints <result>@<at> of the last provisioning restore, none, or n/a without root.
its_last_restore_word() {
    local f="${TS_RB_APPDATA}/tunnelsats/last-restore.json" out
    if ! its_is_root; then
        printf 'n/a'
        return 0
    fi
    if [[ ! -f "$f" ]]; then
        printf 'none'
        return 0
    fi
    out=$(jq -r '[.result, .at] | map(tostring | gsub("[^A-Za-z0-9_.:-]"; "_")) | "\(.[0])@\(.[1])"' "$f" 2>/dev/null) || out=""
    printf '%s' "${out:-invalid}"
}

its_block_doc() {   # $1 verb, $2 exit code, $3 errors, $4 changed (true|false)
    its_doc "$1" "$2" "$3" '{file: $file, state: $state, begin_line: ($b | tonumber), end_line: ($e | tonumber),
        marker_lines: ($m | if . == "" then [] else split(",") | map(tonumber) end), changed: ($changed == "true"),
        created: ($created == "true"), backup: ($backup | if . == "" then null else . end)}' \
        --arg file "$TS_RB_CUSTOM" --arg state "${B_STATE:-absent}" --arg b "${B_BEGIN:-0}" --arg e "${B_END:-0}" \
        --arg m "$(IFS=,; printf '%s' "${B_MARKERS[*]:-}")" --arg changed "$4" --arg created "${B_CREATED:-false}" \
        --arg backup "${B_BACKUP:-}"
}

# Takes the lock that serializes changes to custom-installs.sh (fd in B_LOCKFD).
its_block_lock() {
    its_lock_dir_ok || return 1
    exec {B_LOCKFD}>"${TS_RB_LOCK_DIR}/custom-installs.lock" || return 1
    flock -w 10 "$B_LOCKFD"
}

its_block_unlock() {
    if [[ -n "${B_LOCKFD:-}" ]]; then
        exec {B_LOCKFD}>&-
        B_LOCKFD=""
    fi
}

# Replaces custom-installs.sh with the content of temp file $1 (written in the same directory):
# owner, group and mode of $2 (or root 0644 for a new file), fsync, rename, fsync the directory.
its_block_commit() {
    local tmp="$1" ref="$2" st u g m
    if [[ -n "$ref" ]]; then
        st=$(stat -c '%u %g %a' -- "$ref" 2>/dev/null) || return 1
        read -r u g m <<< "$st"
        chown -- "${u}:${g}" "$tmp" 2>/dev/null || return 1
        chmod -- "$m" "$tmp" 2>/dev/null || return 1
    else
        chmod 0644 -- "$tmp" 2>/dev/null || return 1
    fi
    sync -- "$tmp" 2>/dev/null || return 1
    mv -fT -- "$tmp" "$TS_RB_CUSTOM" 2>/dev/null || return 1
    sync -- "${TS_RB_CUSTOM%/*}" 2>/dev/null || true
    return 0
}

# block-insert [--check]: one marked, idempotent block directly after the shebang line (or at the
# top); the rest of the file stays byte for byte. --check builds the result without writing.
its_block_insert() {
    local check="$1" src tmpl="${TS_RB_ROOT}/assets/custom-installs.sh" first="" tmp ref="" bak nonl=0
    B_CREATED="false" B_BACKUP=""
    if [[ ! -e "$TS_RB_CUSTOM" ]] && [[ ! -L "$TS_RB_CUSTOM" ]]; then
        if ! its_custom_file_ok "$tmpl"; then
            B_CODE="E_TEMPLATE_MISSING"; B_MSG="the custom-installs.sh template is missing"
            return 1
        fi
        src="$tmpl"
        B_CREATED="true"
    else
        its_custom_file_ok "$TS_RB_CUSTOM" || return 1
        src="$TS_RB_CUSTOM"
        ref="$TS_RB_CUSTOM"
    fi
    its_block_scan "$src" || { B_CODE="E_CUSTOM_INSTALLS_UNSAFE"; B_MSG="${src} cannot be read"; return 1; }
    if [[ "$B_STATE" == malformed ]]; then
        B_CODE="E_BLOCK_MALFORMED"; B_MSG="unmatched TunnelSats markers at lines $(IFS=,; printf '%s' "${B_MARKERS[*]}"): fix them by hand"
        return 1
    fi
    # a block that ends the file without a newline keeps doing so (the file had no final newline)
    nonl=0
    its_block_at_eof_nonl "$src" && nonl=1
    if [[ "$B_STATE" == present ]] && cmp -s <(sed -n "${B_BEGIN},${B_END}p" "$src") <(its_block_emit "$nonl"); then
        B_CHANGED="false"
        return 0
    fi
    if ! bash -n "$src" 2>/dev/null; then
        B_CODE="E_CUSTOM_INSTALLS_SYNTAX"; B_MSG="${src} does not pass bash -n; the block is not added"
        return 1
    fi
    tmp=$(mktemp "${TS_RB_CUSTOM%/*}/.custom-installs.sh.tunnelsats.XXXXXX" 2>/dev/null) || {
        B_CODE="E_WRITE_FAILED"; B_MSG="no temp file next to ${TS_RB_CUSTOM}"; return 1; }
    if [[ "$B_STATE" == present ]]; then
        { head -n "$((B_BEGIN - 1))" -- "$src"; its_block_emit "$nonl"; tail -n "+$((B_END + 1))" -- "$src"; } > "$tmp"
    else
        IFS= read -r first < "$src" || true
        if [[ "$first" == '#!'* ]] && [[ "$(wc -l < "$src")" -eq 0 ]]; then
            # only a shebang line without a newline: the block takes over the missing final newline
            { printf '%s\n' "$first"; its_block_emit 1; } > "$tmp"
        elif [[ "$first" == '#!'* ]]; then
            { printf '%s\n' "$first"; its_block_text; tail -n +2 -- "$src"; } > "$tmp"
        else
            { its_block_text; cat -- "$src"; } > "$tmp"
        fi
    fi
    if ! bash -n "$tmp" 2>/dev/null; then
        rm -f -- "$tmp"
        B_CODE="E_BLOCK_SYNTAX"; B_MSG="the result would not pass bash -n; nothing was changed"
        return 1
    fi
    if [[ "$check" -eq 1 ]]; then
        rm -f -- "$tmp"
        B_CHANGED="false"
        B_CREATED="false"
        return 0
    fi
    # Single-slot backup of the state before TunnelSats first changed the file
    bak="${TS_RB_APPDATA}/tunnelsats/backup/custom-installs.sh.pre-tunnelsats"
    if [[ -n "$ref" ]] && [[ ! -e "$bak" ]]; then
        if ! its_state_subdir backup || ! its_atomic_copy "$ref" "$bak" 0600; then
            rm -f -- "$tmp"
            B_CODE="E_BACKUP_FAILED"; B_MSG="the backup of custom-installs.sh could not be written; nothing was changed"
            return 1
        fi
        B_BACKUP="$bak"
    fi
    if ! its_block_commit "$tmp" "$ref"; then
        rm -f -- "$tmp"
        B_CODE="E_WRITE_FAILED"; B_MSG="${TS_RB_CUSTOM} could not be replaced"
        return 1
    fi
    B_CHANGED="true"
    its_block_scan "$TS_RB_CUSTOM"
    if [[ "$B_STATE" != present ]]; then
        B_CODE="E_BLOCK_READBACK"; B_MSG="the block is not present after writing"
        return 1
    fi
    return 0
}

# block-remove: drops the BEGIN line, the END line and the lines between them, nothing else. If the
# block ended the file without a newline, the file had none before it: the line before the block
# gets its missing final newline back.
its_block_remove() {
    local tmp was_ok=0 nonl=0
    B_CREATED="false" B_BACKUP=""
    if [[ ! -e "$TS_RB_CUSTOM" ]] && [[ ! -L "$TS_RB_CUSTOM" ]]; then
        B_STATE="absent" B_CHANGED="false"
        return 0
    fi
    its_custom_file_ok "$TS_RB_CUSTOM" || return 1
    its_block_scan "$TS_RB_CUSTOM" || { B_CODE="E_CUSTOM_INSTALLS_UNSAFE"; B_MSG="cannot be read"; return 1; }
    case "$B_STATE" in
        absent) B_CHANGED="false"; return 0 ;;
        malformed)
            B_CODE="E_BLOCK_MALFORMED"; B_MSG="unmatched TunnelSats markers at lines $(IFS=,; printf '%s' "${B_MARKERS[*]}"): fix them by hand"
            return 1
            ;;
    esac
    its_block_at_eof_nonl "$TS_RB_CUSTOM" && nonl=1
    bash -n "$TS_RB_CUSTOM" 2>/dev/null && was_ok=1
    tmp=$(mktemp "${TS_RB_CUSTOM%/*}/.custom-installs.sh.tunnelsats.XXXXXX" 2>/dev/null) || {
        B_CODE="E_WRITE_FAILED"; B_MSG="no temp file next to ${TS_RB_CUSTOM}"; return 1; }
    { head -n "$((B_BEGIN - 1))" -- "$TS_RB_CUSTOM"; tail -n "+$((B_END + 1))" -- "$TS_RB_CUSTOM"; } > "$tmp"
    if [[ "$nonl" -eq 1 ]] && [[ -s "$tmp" ]] && [[ -z "$(tail -c 1 -- "$tmp")" ]]; then
        truncate -s -1 -- "$tmp"
    fi
    if [[ "$was_ok" -eq 1 ]] && ! bash -n "$tmp" 2>/dev/null; then
        rm -f -- "$tmp"
        B_CODE="E_BLOCK_SYNTAX"; B_MSG="the result would not pass bash -n; nothing was changed"
        return 1
    fi
    if ! its_block_commit "$tmp" "$TS_RB_CUSTOM"; then
        rm -f -- "$tmp"
        B_CODE="E_WRITE_FAILED"; B_MSG="${TS_RB_CUSTOM} could not be replaced"
        return 1
    fi
    B_CHANGED="true"
    its_block_scan "$TS_RB_CUSTOM"
    if [[ "$B_STATE" != absent ]]; then
        B_CODE="E_BLOCK_READBACK"; B_MSG="the block is still present after writing"
        return 1
    fi
    return 0
}

# block-insert [--check] | block-remove | block-status, all with [--json].
its_cmd_block() {
    local verb="$1" check=0 json=0 a rc errors="[]"
    shift
    for a in "$@"; do
        case "$a" in
            --check) [[ "$verb" == block-insert ]] || { its_usage >&2; return 2; }; check=1 ;;
            --json) json=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
    done
    B_STATE="absent" B_BEGIN=0 B_END=0 B_MARKERS=() B_CHANGED="false" B_CREATED="false" B_BACKUP="" B_CODE="" B_MSG=""
    if [[ "$verb" == block-status ]]; then
        rc=0
        if [[ -e "$TS_RB_CUSTOM" ]] || [[ -L "$TS_RB_CUSTOM" ]]; then
            if ! its_custom_file_ok "$TS_RB_CUSTOM" || ! its_block_scan "$TS_RB_CUSTOM"; then
                rc=1
            fi
        fi
    else
        its_require_root "$verb" || return 2
        if ! its_block_lock; then
            B_CODE="E_BUSY"; B_MSG="another change to custom-installs.sh is running"
            rc=1
        elif [[ "$verb" == block-insert ]]; then
            its_block_insert "$check"
            rc=$?
        else
            its_block_remove
            rc=$?
        fi
        its_block_unlock
    fi
    [[ -n "$B_CODE" ]] && errors=$(its_err "$B_CODE" operational "$B_MSG")
    if [[ "$json" -eq 1 ]]; then
        its_block_doc "$verb" "$rc" "$errors" "$B_CHANGED"
    else
        echo "state=${B_STATE} changed=${B_CHANGED}${B_CODE:+ error=${B_CODE}}"
        [[ -n "$B_MSG" ]] && its_log "# ${verb}: ${B_MSG}"
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------------------------
# restore: what the block runs during provisioning after an SD-card update
# ---------------------------------------------------------------------------------------------

# One line to the journal (tunnelsats-restore) and one to stdout (raspiblitz.log) or stderr.
its_rlog() {
    its_journal tunnelsats-restore "$1"
    if [[ "${R_JSON:-0}" -eq 1 ]]; then
        its_log "# TunnelSats: $1"
    else
        echo "# TunnelSats: $1"
    fi
}

its_restore_record() {   # $1 result, $2 error code
    local f="${TS_RB_APPDATA}/tunnelsats/last-restore.json" doc decision=""
    [[ -d "${TS_RB_APPDATA}/tunnelsats" ]] || return 0
    [[ -n "${R_BASE:-}" ]] && decision=$(jq -r '.decision // empty' "${TS_RB_RUN_DIR}/guard-${R_BASE}.json" 2>/dev/null)
    doc=$(jq -n -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg result "$1" --arg error "$2" \
        --arg version "$TS_PIN_VERSION" --arg restarted "${R_RESTARTED:-}" --arg decision "${decision:-}" \
        '{at: $at, result: $result, error: ($error | if . == "" then null else . end), tool_version: $version,
          ln_restarted: (if $restarted == "true" then true elif $restarted == "false" then false else null end),
          guard_decision: ($decision | if . == "" then null else . end)}') || return 1
    its_atomic_write "$f" "${doc}"$'\n' 0644 || its_log "# TunnelSats: last-restore.json could not be written"
}

its_restore_doc() {   # $1 exit code, $2 result, $3 error code, $4 error class (default operational)
    [[ "${R_JSON:-0}" -eq 1 ]] || return 0
    local errors="[]"
    [[ -n "$3" ]] && errors=$(its_err "$3" "${4:-operational}" "restore: $2")
    its_doc restore "$1" "$errors" '{result: $result, ln_restarted: (if $r == "true" then true elif $r == "false" then false else null end)}' \
        --arg result "$2" --arg r "${R_RESTARTED:-}"
}

# Succeeds if the pinned tool reports a managed install for unit $2 (script $1).
its_restore_managed() {
    its_tool_run "$1" "$TS_PIN_SHA256" 35 verify --json --no-probe || return 1
    [[ "$(jq -r -s 'if length == 1 then (.[0].managed == true and .[0].unit == $u) else false end' \
        --arg u "$2" "$X_DOC" 2>/dev/null)" == true ]]
}

its_cmd_restore() {
    local a impl cimpl unit conf code
    R_JSON=0 R_BASE="" R_RESTARTED=""
    for a in "$@"; do
        case "$a" in
            --json) R_JSON=1 ;;
            *) its_usage >&2; return 2 ;;
        esac
    done
    if ! its_is_root; then
        its_rlog "restore must run as root"
        its_restore_doc 1 failed E_NOT_ROOT
        return 1
    fi
    if [[ "$(its_conf_get tunnelsats)" != on ]]; then
        its_rlog "not active, nothing to restore"
        its_restore_doc 0 not_active ""
        return 0
    fi
    if [[ "$(its_conf_get runBehindTor)" != on ]]; then
        its_rlog "Tor is off and TunnelSats needs it: nothing installed, Lightning does not start while TunnelSats is on. Switch Tor on (SSH menu > SETTINGS), then SSH menu > SUBSCRIBE > TunnelSats > REPAIR, or REMOVE TunnelSats there"
        its_restore_record refused E_TOR_REQUIRED
        its_restore_doc 1 refused E_TOR_REQUIRED refused
        return 1
    fi
    impl=$(its_conf_get tunnelsatsImpl) || impl=""
    case "$impl" in
        lnd) cimpl="lnd"; unit="lnd.service"; R_BASE="lnd" ;;
        cl) cimpl="cln"; unit="lightningd.service"; R_BASE="lightningd" ;;
        *)
            its_rlog "tunnelsatsImpl is not set; Lightning stays Tor-only (SSH menu > SUBSCRIBE > TunnelSats > REPAIR)"
            its_restore_record not_configured E_NOT_CONFIGURED
            its_restore_doc 3 not_configured E_NOT_CONFIGURED
            return 3
            ;;
    esac
    conf="$(its_state_dir)/tunnelsats.conf"
    if ! its_stored_conf_ok "$conf"; then
        its_rlog "stored config missing or not root 0600; Lightning stays Tor-only (IMPORT again or REMOVE)"
        its_restore_record not_configured E_NOT_CONFIGURED
        its_restore_doc 3 not_configured E_NOT_CONFIGURED
        return 3
    fi
    its_run_dir_ok || true
    if ! its_fetch_offline; then
        its_rlog "no verified stored copy of tunnelsats.sh ${TS_PIN_VERSION} (${F_CODE}); downloading the pinned one"
        if ! its_fetch_online; then
            its_rlog "download failed (${F_CODE}); nothing installed, Lightning stays Tor-only"
            its_restore_record failed "$F_CODE"
            its_restore_doc 1 failed "$F_CODE"
            its_cleanup
            return 1
        fi
    fi
    if its_restore_managed "$F_PATH" "$unit"; then
        its_rlog "managed mode is already in place for ${unit}"
    else
        its_rlog "installing managed mode for ${unit} (tunnelsats.sh ${TS_PIN_VERSION})"
        if ! its_tool_run "$F_PATH" "$TS_PIN_SHA256" 900 install --managed raspiblitz --impl "$cimpl" \
            --network mainnet --config "$conf" --non-interactive --yes --json; then
            code="E_TOOL_COPY"
        elif [[ "$X_RC" == 124 ]] || [[ "$X_RC" == 137 ]]; then
            code="E_TIMEOUT"
        elif [[ "$(jq -r -s --argjson rc "$X_RC" --argjson c "$TS_PIN_CONTRACT" \
            'length == 1 and (.[0] | type) == "object" and .[0].contract == $c and .[0].exit_code == $rc' \
            "$X_DOC" 2>/dev/null)" != true ]]; then
            code="E_TOOL_OUTPUT"
        elif [[ "$X_RC" -eq 0 ]]; then
            code=""
            R_RESTARTED=$(jq -r -s '.[0].ln_restarted | if type == "boolean" then tostring else empty end' "$X_DOC" 2>/dev/null)
        else
            code=$(jq -r -s '.[0].errors[0].code // empty' "$X_DOC" 2>/dev/null)
            [[ "$code" =~ ^E_[A-Z0-9_]{1,40}$ ]] || code="E_INSTALL_FAILED"
            if [[ "$X_RC" -eq 7 ]] && [[ "$code" == E_MANAGED_PRESENT ]] && its_restore_managed "$F_PATH" "$unit"; then
                code=""
            fi
        fi
        if [[ -n "$code" ]]; then
            its_rlog "install failed (${code}); Lightning stays Tor-only. SSH menu > SUBSCRIBE > TunnelSats > REPAIR"
            its_restore_record failed "$code"
            its_restore_doc 1 failed "$code"
            its_cleanup
            return 1
        fi
        its_rlog "managed mode restored$([[ "$R_RESTARTED" == true ]] && printf '; Lightning restarted')"
    fi
    if ! its_tick_timer on >/dev/null; then
        its_rlog "the tick timer could not be set up"
    fi
    its_restore_record ok ""
    its_restore_doc 0 ok ""
    its_cleanup
    return 0
}

# ---------------------------------------------------------------------------------------------
# tick-timer on|off|status: the RaspiBlitz-owned 5-minute tick (restart notice)
# ---------------------------------------------------------------------------------------------

its_tick_service_text() {
    printf '%s\n' "[Unit]" "Description=TunnelSats RaspiBlitz tick (restart notice)" "[Service]" "Type=oneshot" \
        "ExecStart=${ITS_PROD_MODULE} tick --json"
}

its_tick_timer_text() {
    printf '%s\n' "[Unit]" "Description=TunnelSats RaspiBlitz tick every 5 minutes" "[Timer]" "OnBootSec=5min" \
        "OnUnitActiveSec=5min" "[Install]" "WantedBy=timers.target"
}

its_tick_timer() {
    local svc="${TS_RB_UNIT_DIR}/tunnelsats-tick.service" tmr="${TS_RB_UNIT_DIR}/tunnelsats-tick.timer" state
    case "${1:-}" in
        on)
            its_atomic_write "$svc" "$(its_tick_service_text)"$'\n' 0644 || return 1
            its_atomic_write "$tmr" "$(its_tick_timer_text)"$'\n' 0644 || return 1
            "$TS_RB_SYSTEMCTL" daemon-reload >/dev/null 2>&1 || return 1
            "$TS_RB_SYSTEMCTL" enable --now tunnelsats-tick.timer >/dev/null 2>&1 || return 1
            echo "active"
            ;;
        off)
            if [[ -e "$tmr" ]] || [[ -e "$svc" ]]; then
                "$TS_RB_SYSTEMCTL" disable --now tunnelsats-tick.timer >/dev/null 2>&1 || true
                rm -f -- "$svc" "$tmr" || return 1
                "$TS_RB_SYSTEMCTL" daemon-reload >/dev/null 2>&1 || true
            fi
            [[ ! -e "$svc" ]] && [[ ! -e "$tmr" ]] || return 1
            echo "absent"
            ;;
        status)
            if [[ ! -e "$tmr" ]]; then
                echo "absent"
            else
                state=$("$TS_RB_SYSTEMCTL" is-active tunnelsats-tick.timer 2>/dev/null) || true
                [[ "$state" == active ]] && echo "active" || echo "inactive"
            fi
            ;;
        *) its_usage >&2; return 2 ;;
    esac
    return 0
}

its_cmd_tick_timer() {
    if [[ "${1:-}" != status ]] && ! its_is_root; then
        its_log "# tick-timer must run as root"
        return 1
    fi
    its_tick_timer "$@"
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

main() {
    # Executed, not sourced: production paths and a fixed PATH, nothing from the environment
    PATH="$ITS_SAFE_PATH"
    export PATH
    LC_ALL=C
    export LC_ALL
    umask 022
    unset "${!TS_RB_@}"
    its_init_paths
    set -u
    trap 'its_cleanup' EXIT
    trap 'its_cleanup; exit 143' TERM
    trap 'its_cleanup; exit 130' INT
    local verb="${1:-}"
    [[ $# -gt 0 ]] && shift
    case "$verb" in
        guard) its_cmd_guard "$@" ;;
        audit) its_cmd_audit "$@" ;;
        status) its_cmd_status "$@" ;;
        fetch) its_cmd_fetch "$@" ;;
        install) its_cmd_install "$@" ;;
        adopt) its_cmd_adopt "$@" ;;
        uninstall) its_cmd_uninstall "$@" ;;
        verify) its_cmd_verify "$@" ;;
        detect) its_cmd_detect "$@" ;;
        block-insert | block-remove | block-status) its_cmd_block "$verb" "$@" ;;
        restore) its_cmd_restore "$@" ;;
        tick-timer) its_cmd_tick_timer "$@" ;;
        -h | --help | help) its_usage; return 0 ;;
        *) its_usage >&2; return 2 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
    exit $?
fi
