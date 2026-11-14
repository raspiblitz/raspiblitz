# Isolated Tor updater regression tests

Run from the repository root:

```sh
bash tests/tor-update/run.sh
```

Docker builds the test tools, then runs the **unchanged production script** in a
fresh container with no network, host mounts, or real Tor executable. The test
packages contain only an inert `tor --version` shell fixture. All service calls
are recording fixtures; no host or live-node services are touched. The optional
`TOR_UPDATE_SKIP_BUILD=1` reuses an already built test-tools image, without
skipping syntax, ShellCheck, tests, or the trace gate.

## What is real and what is mocked

- Real GnuPG generates temporary signing keys and signs a local file repository.
  Real APT authenticates its signed index, checks package hashes, downloads and
  installs fixture packages. Real dpkg handles version comparisons, package
  replacement, metadata and rollback. No authentication bypass flags are used.
- The curl fixture serves local keys or fails either transport. The GPG display
  fixture maps the temporary key identity to the production pinned identity;
  it also tests a wrong full fingerprint with the same four-character prefix
  and a bundle containing an extra key. Key parsing and dearmoring remain real.
  The actual public Tor key and Tor repository availability are not verified.
- APT is routed to the local signed repository. Unrelated transport/development
  dependencies, source fetching and compilation are inert recording fixtures.
  The source updater's actual control flow and dpkg installation still run.
- `sudo` executes directly as container root; this is not a test of a deployed
  sudo policy. `systemctl` records state and injects failures, including a stop
  error **after** stopping and a restart error leaving the service stopped.

## Coverage

The suite exercises amd64/arm64 source-list selection, verified package success,
current/newer-version no-op behavior, the 0.4.9 minimum and missing/failing version
output, primary/fallback units, both key transports and fallback retry, wrong or
bundled keys, key-tool/write failures, real bad-signature/hash/download rejection,
source prerequisites/download/build/layout failures, missing/multiple packages,
installation failures after mutation, stop/start failures, SIGTERM, package and
binary rollback, and recovery failure diagnostics. Recovery files are checked
for root ownership, mode 0700, and exact package bytes. Each injected fault must
be reached; a harness error cannot count as an expected application failure.

Bash xtrace records production line numbers and the source digest. A source-derived
gate checks command/condition sites in the changed helpers and update block;
multiline expansions use Bash's final expansion line. It is a site-coverage
check, **not** a formal claim of 100% Bash branch coverage. Fault cases assert the
important success/failure/retry outcomes separately. Initial-install minimum
version checks also execute through the full production entry point. Unchanged
Snowflake installation and HDD/enable configuration are outside this suite.

## Operational limits

Rollback restores the Tor package and packaged executable, not every dependency,
configuration side effect, or external effect of maintainer scripts. The exact
previous package is downloaded through authenticated APT when available, with
an exact package/version/architecture-validated local cache fallback copied into
the root-private stage. If neither is available, the updater warns and continues
without package rollback. It still installs the authenticated configured APT
candidate, with 0.4.9 as a minimum rather than a pinned target. Failed updates
retain recovery files and report their location. Recovery restarts are attempted
even without a backup, and unsuccessful installation/restart remains a failure.
SIGKILL/power-loss recovery is not implemented.

Latest-only signed-repository cases cover upgrades without an old package,
cache fallback, corrupt or mismatched package/version/architecture rejection,
no-backup installation/restart failures and a future 0.4.10 candidate. Legacy
global trust is removed only after scoped trust and source writes succeed.
The embedded root backup shell has independent line numbers and is checked by
these outcome assertions rather than the outer script's xtrace site gate.

CI runs the same isolated suite for matching PRs and manual dispatch, including
manual runs on fork branches. Real Tor startup, cross-architecture Tor binaries
and public repository availability need separate verification.
