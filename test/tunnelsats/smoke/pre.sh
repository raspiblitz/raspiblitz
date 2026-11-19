#!/bin/bash
#
# ExecStartPre=+ command of the systemd smoke units (systemd_smoke.sh). Records its uid, then
# writes this unit's env file with the production functions of internet.tunnelsats.sh
# (its_guard_init, its_render, its_guard_write_env), the way the start guard does.
#
# Usage: pre.sh <lnd|cl> <work directory>. The mode for this start is read from
# <work>/ctl/<impl>.mode: hybrid (rendered flags), empty (empty value) or none (no file).
# TS_SMOKE_LIB (default /usr/local/lib/ts-smoke, where systemd_smoke.sh installs the script) lets a
# sanity run outside systemd point at the checkout.

# Variables set here are read by the sourced production functions.
# shellcheck disable=SC2034

set -eu

impl="$1"
work="$2"
id -u > "${work}/out/pre-${impl}.uid"
mode="$(cat "${work}/ctl/${impl}.mode")"
[ "$mode" = none ] && exit 0

TS_RB_RUN_DIR="${work}/run"
# shellcheck source=/dev/null
. "${TS_SMOKE_LIB:-/usr/local/lib/ts-smoke}/internet.tunnelsats.sh"
G_DRY=0
its_guard_init "$impl" mainnet
flags=""
if [ "$mode" = hybrid ]; then
    # endpoint of the verify fixtures; CLN with a confirmed announce address
    V_HOST="de2.tunnelsats.com"
    V_PORT="24556"
    V_IPV4="1.2.3.4"
    C_STATE="confirmed"
    its_render
    flags="$R_FLAGS"
fi
its_guard_write_env "$flags"
