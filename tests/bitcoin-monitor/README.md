# Bitcoin monitor RPC regression tests

Run `tests/bitcoin-monitor/run.sh` from any directory with Docker available. The
image build downloads Debian packages; the tests run with networking disabled
except for container-local loopback, no capabilities, a read-only source mount,
and an init process to reap terminated descendants. Do not run the Python worker
directly on a node: it installs synthetic absolute-path fixtures in its disposable
container and explicitly refuses ordinary host execution.

The worker executes the complete, unmodified `bitcoin.monitor.sh` entrypoint,
not extracted functions. A mock `bitcoin-cli` is a real process connected to a
local TCP RPC fixture. Tests cover status success (all three networks), zero
peers, actual connection refusal, deadlines, stderr before timeout, invalid and
empty responses, network/connection-count/socket fallbacks, info and mempool
success/failure (including nonfinite, negative, fractional, and oversized counts,
progress outside [0,1], decimal/exponent normalization, and count boundaries),
stale sourced status, repeated iterations, and a TERM-resistant
RPC process with a descendant. The 1-second boundary cases respond at 0.8 and
1.2 seconds, allowing process startup margin. Recorded client/descendant PIDs
must no longer be live after the monitor returns; temporary output files must
be removed. GNU timeout's forced-kill exit (137) is treated like its ordinary
timeout exit (124).

A timeout must return a successful *status collection* with `btc_running=1`,
`btc_ready=0`, `btc_online=0`, and `btc_error_short='RPC timeout'`. It must not
pretend the service stopped or leave a stale ready flag. The sourced-output test
uses the same process-substitution contract as the background scan.

Limitations: fixtures do not run Bitcoin Core, real systemd, actual peer socket
discovery, or the complete background/recovery loop. System status and socket
counts are inert fixtures. This is process/deadline and monitor-output coverage,
not an end-to-end node or Bitcoin JSON-RPC protocol test. No service/recovery
commands or live configuration changes are made.
