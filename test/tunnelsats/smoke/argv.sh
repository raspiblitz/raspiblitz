#!/bin/sh
#
# Main process of the systemd smoke units (systemd_smoke.sh): records its uid and its arguments,
# one per line, to the file named by TS_SMOKE_OUT.

{
    printf 'uid=%s\n' "$(id -u)"
    printf 'argc=%s\n' "$#"
    for a in "$@"; do
        printf 'arg=[%s]\n' "$a"
    done
} > "${TS_SMOKE_OUT:?}"
