#!/usr/bin/env bats
# The marked TunnelSats block in custom-installs.sh (design 4.1, 4.2; tests 7.2). Runs the real
# block functions and verbs of internet.tunnelsats.sh; the expected block is the literal text of
# fixtures/block/block.txt (spec 4.1), not the production function.

# Variables set here are read by the sourced production functions.
# shellcheck disable=SC2034

load helpers

setup() {
    its_setup
    mkdir -p "$FX/admin/assets"
    TEMPLATE="${BATS_TEST_DIRNAME}/../../home.admin/assets/custom-installs.sh"
    cp "$TEMPLATE" "$FX/admin/assets/custom-installs.sh"
    TS_RB_CUSTOM="$FX/app-data/custom-installs.sh"
    BLOCK="${FIXTURES}/block/block.txt"
}

teardown() {
    its_teardown
}

block_json() {   # runs a block verb with --json, sets $status and $output
    run call its_cmd_block "$@" --json
}

no_temp_files() {
    [ -z "$(find "$FX/app-data" -maxdepth 1 -name '.custom-installs.sh.tunnelsats.*')" ]
}

@test "insert into the real template (no final newline): shebang, block, then the original bytes" {
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    [ -n "$(tail -c 1 "$TS_RB_CUSTOM")" ]
    block_json block-insert
    [ "$status" -eq 0 ]
    [ "$(jq -r '.state, .changed, .begin_line, .end_line' <<< "$output" | tr '\n' ' ')" = "present true 2 9 " ]
    { head -n 1 "$TEMPLATE"; cat "$BLOCK"; tail -n +2 "$TEMPLATE"; } > "$FX/expected"
    cmp "$FX/expected" "$TS_RB_CUSTOM"
    [ -n "$(tail -c 1 "$TS_RB_CUSTOM")" ]
    cmp "$TEMPLATE" "$FX/app-data/tunnelsats/backup/custom-installs.sh.pre-tunnelsats"
    [ "$(stat -c %a "$FX/app-data/tunnelsats/backup/custom-installs.sh.pre-tunnelsats")" = 600 ]
    no_temp_files
}

@test "a second insert is byte-identical; remove restores the original bytes" {
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    chmod 0640 "$TS_RB_CUSTOM"
    block_json block-insert
    cp "$TS_RB_CUSTOM" "$FX/once"
    block_json block-insert
    [ "$status" -eq 0 ]
    [ "$(jq -r .changed <<< "$output")" = false ]
    cmp "$FX/once" "$TS_RB_CUSTOM"
    block_json block-remove
    [ "$status" -eq 0 ]
    [ "$(jq -r '.state, .changed' <<< "$output" | tr '\n' ' ')" = "absent true " ]
    cmp "$TEMPLATE" "$TS_RB_CUSTOM"
    [ "$(stat -c %a "$TS_RB_CUSTOM")" = 640 ]
    block_json block-remove
    [ "$status" -eq 0 ]
    [ "$(jq -r .changed <<< "$output")" = false ]
    no_temp_files
}

@test "the lock on custom-installs.sh holds while the tool clears /run/tunnelsats" {
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    mkdir -m 0755 "$TS_RB_RUN_DIR"
    here its_block_lock
    rm -rf "$TS_RB_RUN_DIR"
    block_json block-insert
    its_block_unlock
    [ "$status" -eq 1 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_BUSY ]
    cmp "$TEMPLATE" "$TS_RB_CUSTOM"
    [ "$(stat -c %a "$TS_RB_LOCK_DIR")" = 700 ]
}

@test "a file without shebang gets the block at the top; an empty file holds just the block" {
    printf 'echo one\necho two' > "$TS_RB_CUSTOM"
    block_json block-insert
    { cat "$BLOCK"; printf 'echo one\necho two'; } > "$FX/expected"
    cmp "$FX/expected" "$TS_RB_CUSTOM"
    : > "$TS_RB_CUSTOM"
    block_json block-insert
    cmp "$BLOCK" "$TS_RB_CUSTOM"
}

@test "malformed markers (BEGIN only, END only, END first, two blocks) are refused, the file stays unchanged" {
    local begin end variant
    begin="$(head -n 1 "$BLOCK")"
    end="$(tail -n 1 "$BLOCK")"
    for variant in begin_only end_only end_first two_blocks; do
        case "$variant" in
            begin_only) printf '#!/bin/bash\n%s\necho user\n' "$begin" > "$TS_RB_CUSTOM" ;;
            end_only) printf '#!/bin/bash\necho user\n%s\n' "$end" > "$TS_RB_CUSTOM" ;;
            end_first) printf '#!/bin/bash\n%s\necho user\n%s\n' "$end" "$begin" > "$TS_RB_CUSTOM" ;;
            two_blocks) { echo '#!/bin/bash'; cat "$BLOCK" "$BLOCK"; echo 'echo user'; } > "$TS_RB_CUSTOM" ;;
        esac
        cp "$TS_RB_CUSTOM" "$FX/before"
        block_json block-insert
        [ "$status" -eq 1 ]
        [ "$(jq -r '.state, .errors[0].code' <<< "$output" | tr '\n' ' ')" = "malformed E_BLOCK_MALFORMED " ]
        cmp "$FX/before" "$TS_RB_CUSTOM"
        block_json block-remove
        [ "$status" -eq 1 ]
        cmp "$FX/before" "$TS_RB_CUSTOM"
        no_temp_files
    done
}

@test "a missing END marker never deletes to the end of the file" {
    { echo '#!/bin/bash'; head -n 7 "$BLOCK"; echo 'echo user line one'; echo 'echo user line two'; } > "$TS_RB_CUSTOM"
    cp "$TS_RB_CUSTOM" "$FX/before"
    block_json block-remove
    [ "$status" -eq 1 ]
    [ "$(jq -c .marker_lines <<< "$output")" = "[2]" ]
    cmp "$FX/before" "$TS_RB_CUSTOM"
}

@test "an older block version: only the lines between the markers are replaced" {
    { echo '#!/bin/bash'; echo 'echo before'; head -n 1 "$BLOCK"; echo 'echo old block body'; tail -n 1 "$BLOCK"; echo 'echo after'; } > "$TS_RB_CUSTOM"
    block_json block-insert
    [ "$status" -eq 0 ]
    { echo '#!/bin/bash'; echo 'echo before'; cat "$BLOCK"; echo 'echo after'; } > "$FX/expected"
    cmp "$FX/expected" "$TS_RB_CUSTOM"
}

@test "a shebang-only file without a final newline: insert, insert again, update and remove keep its bytes" {
    local shebang
    for shebang in '#!/bin/bash' $'#!/bin/bash\r'; do
        printf '%s' "$shebang" > "$TS_RB_CUSTOM"
        cp "$TS_RB_CUSTOM" "$FX/original"
        block_json block-insert
        [ "$status" -eq 0 ]
        { printf '%s\n' "$shebang"; printf '%s' "$(cat "$BLOCK")"; } > "$FX/expected"
        cmp "$FX/expected" "$TS_RB_CUSTOM"
        block_json block-insert
        [ "$(jq -r .changed <<< "$output")" = false ]
        cmp "$FX/expected" "$TS_RB_CUSTOM"
        # an older block version at the end of the file is replaced the same way
        { printf '%s\n' "$shebang"; head -n 1 "$BLOCK"; echo 'echo old block body'; printf '%s' "$(tail -n 1 "$BLOCK")"; } > "$TS_RB_CUSTOM"
        block_json block-insert
        [ "$(jq -r .changed <<< "$output")" = true ]
        cmp "$FX/expected" "$TS_RB_CUSTOM"
        block_json block-remove
        [ "$status" -eq 0 ]
        cmp "$FX/original" "$TS_RB_CUSTOM"
        rm -f "$FX/app-data/tunnelsats/backup/custom-installs.sh.pre-tunnelsats"
    done
    no_temp_files
}

@test "a user exit 0 and a set -e script keep the block first, and the block runs" {
    printf '#!/bin/bash\nexit 0\necho never\n' > "$TS_RB_CUSTOM"
    block_json block-insert
    [ "$(sed -n 2p "$TS_RB_CUSTOM")" = "$(head -n 1 "$BLOCK")" ]
    run bash "$TS_RB_CUSTOM"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# TunnelSats: this RaspiBlitz image has no TunnelSats integration; Lightning stays Tor-only"* ]]
    [[ "$output" != *never* ]]
    printf '#!/bin/bash\nset -e\nfalse\necho never\n' > "$TS_RB_CUSTOM"
    block_json block-insert
    run bash "$TS_RB_CUSTOM"
    [[ "$output" == *"no TunnelSats integration"* ]]
    [[ "$output" != *never* ]]
}

@test "CRLF marker lines are recognized" {
    { printf '#!/bin/bash\r\n'; sed 's/$/\r/' "$BLOCK"; printf 'echo user\r\n'; } > "$TS_RB_CUSTOM"
    run call its_cmd_block block-status --json
    [ "$status" -eq 0 ]
    [ "$(jq -r .state <<< "$output")" = present ]
    block_json block-remove
    [ "$status" -eq 0 ]
    printf '#!/bin/bash\r\necho user\r\n' > "$FX/expected"
    cmp "$FX/expected" "$TS_RB_CUSTOM"
}

@test "an original that fails bash -n is refused and unchanged" {
    printf '#!/bin/bash\nif then fi (\n' > "$TS_RB_CUSTOM"
    cp "$TS_RB_CUSTOM" "$FX/before"
    block_json block-insert
    [ "$status" -eq 1 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_CUSTOM_INSTALLS_SYNTAX ]
    cmp "$FX/before" "$TS_RB_CUSTOM"
    no_temp_files
}

@test "a symlink, a file over 1 MiB or a file with NUL bytes is refused" {
    cp "$TEMPLATE" "$FX/real.sh"
    ln -s "$FX/real.sh" "$TS_RB_CUSTOM"
    block_json block-insert
    [ "$status" -eq 1 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_CUSTOM_INSTALLS_UNSAFE ]
    cmp "$TEMPLATE" "$FX/real.sh"
    rm "$TS_RB_CUSTOM"
    head -c 1048577 /dev/zero | tr '\0' '#' > "$TS_RB_CUSTOM"
    block_json block-insert
    [ "$status" -eq 1 ]
    printf '#!/bin/bash\necho a\0b\n' > "$TS_RB_CUSTOM"
    block_json block-insert
    [ "$status" -eq 1 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_CUSTOM_INSTALLS_UNSAFE ]
}

@test "a missing file is created from the template (root 0644) with the block" {
    block_json block-insert
    [ "$status" -eq 0 ]
    [ "$(jq -r '.created, .state' <<< "$output" | tr '\n' ' ')" = "true present " ]
    { head -n 1 "$TEMPLATE"; cat "$BLOCK"; tail -n +2 "$TEMPLATE"; } > "$FX/expected"
    cmp "$FX/expected" "$TS_RB_CUSTOM"
    [ "$(stat -c %a "$TS_RB_CUSTOM")" = 644 ]
    [ ! -e "$FX/app-data/tunnelsats/backup/custom-installs.sh.pre-tunnelsats" ]
}

@test "--check builds the result without writing anything" {
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    block_json block-insert --check
    [ "$status" -eq 0 ]
    [ "$(jq -r .changed <<< "$output")" = false ]
    cmp "$TEMPLATE" "$TS_RB_CUSTOM"
    [ ! -e "$FX/app-data/tunnelsats" ]
    rm "$TS_RB_CUSTOM"
    block_json block-insert --check
    [ "$status" -eq 0 ]
    [ ! -e "$TS_RB_CUSTOM" ]
    printf '#!/bin/bash\nif then fi (\n' > "$TS_RB_CUSTOM"
    block_json block-insert --check
    [ "$status" -eq 1 ]
}

@test "the backup is written on the first change only" {
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    block_json block-insert
    block_json block-remove
    echo 'echo later' >> "$TS_RB_CUSTOM"
    block_json block-insert
    cmp "$TEMPLATE" "$FX/app-data/tunnelsats/backup/custom-installs.sh.pre-tunnelsats"
}

@test "the block text passes dash -n (POSIX sh) and bash -n" {
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    block_json block-insert
    sed -n '2,9p' "$TS_RB_CUSTOM" > "$FX/block.sh"
    cmp "$BLOCK" "$FX/block.sh"
    dash -n "$FX/block.sh"
    bash -n "$FX/block.sh"
}

@test "block-status: absent, present, malformed with marker lines; no root needed" {
    TS_RB_ROOT_UID=99999
    run call its_cmd_block block-status --json
    [ "$status" -eq 0 ]
    [ "$(jq -r .state <<< "$output")" = absent ]
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    run call its_cmd_block block-status
    [ "$output" = "state=absent changed=false" ]
    { echo '#!/bin/bash'; cat "$BLOCK"; } > "$TS_RB_CUSTOM"
    run call its_cmd_block block-status --json
    [ "$(jq -r '.state, .begin_line, .end_line' <<< "$output" | tr '\n' ' ')" = "present 2 9 " ]
    { echo '#!/bin/bash'; cat "$BLOCK" "$BLOCK"; } > "$TS_RB_CUSTOM"
    run call its_cmd_block block-status --json
    [ "$(jq -c '[.state, .marker_lines]' <<< "$output")" = '["malformed",[2,9,10,17]]' ]
    block_json block-insert
    [ "$status" -eq 2 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_NOT_ROOT ]
}

@test "the status verb reports the restore block" {
    conf "tunnelsats=on" "tunnelsatsImpl='lnd'" "runBehindTor=on"
    cp "$TEMPLATE" "$TS_RB_CUSTOM"
    block_json block-insert
    run call its_cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"restore_block=present last_restore=none"* ]]
}
