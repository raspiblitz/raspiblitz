# Offline feeadjuster regression tests

From the repository root (Docker and host Python 3 required):

```sh
docker build -t feeadjuster-tests:local -f test/feeadjuster.Dockerfile test
python3 test/feeadjuster.py
# Read production inputs from a local revision without changing checkout:
python3 test/feeadjuster.py --revision <original-commit>
# Select a single regression:
python3 test/feeadjuster.py --test test_z_distinct_uid_private_stage_cwd
# Replay a previously captured JSON map of production filenames to contents:
python3 test/feeadjuster.py --payload /path/to/captured-scripts.json
```

The Ubuntu 22.04 image installs distro Python 3, bash, jq, dpkg and sudo (plus
APT's ordinary dependencies), with a fixture bitcoin UID/GID 1000. Building uses
package-mirror access;
**executing the tests has no networking**. No pip packages are required.

The host runner sends actual, unmodified `cl-plugin.feeadjuster.sh`,
`cl.install-service.sh`, `cl.check.sh` and, when present in the selected source,
`cl-plugin.feeadjuster-config.py`, plus the container-only worker over stdin.
There are **no host bind mounts**, credentials, Docker socket, node data or real
plugin execution. Each invocation creates a disposable container with
`--network=none`, no-new-privileges and bounded resources. All capabilities are
dropped except CHOWN, SETUID and SETGID, required for the distinct-UID regression;
DAC_OVERRIDE and DAC_READ_SEARCH remain absent. Scenarios recreate synthetic
`/home`, CLN config, cache and service fixtures. Scripts run whole, not extracted
functions or rewritten paths. SHA-256 digests identify production inputs.

Recording, inert fixtures stand in for git, `/usr/local/bin/uv`, sudo,
lightning-cli, systemctl, and config/network/cache helpers. Git creates inert
text files and never executes upstream code. The usual sudo fixture executes
as the existing container user. **The dedicated distinct-UID regression instead
actually calls `os.setgroups`, `os.setgid(1000)` and `os.setuid(1000)` before
executing bitcoin commands.** It owns the synthetic bitcoin tree as UID/GID 1000,
verifies the outer UID 0 cannot enter a bitcoin-owned mode-0700 probe directory,
then runs the unchanged installer. Thus a parent-shell `cd` before switching UID
fails under real Unix permissions; successful sync must be recorded with
UID/GID 1000 in the private stage, whose owner and mode are also checked. This
is not a same-user sudo simulation, but neither is it a real sudo-policy test
or a full admin-user login environment.

Real bash, Python, coreutils and jq handle files, symlinks and JSON. Most injected
failures are one-shot so restoration can run; rollback-failure scenarios
intentionally keep failing the specified operation. Each injection must be
observed. Failure details include argv, status, stdout/stderr and events.

Coverage:

- mainnet/testnet/signet/default enable, fresh enable, commit/norestart argument
  orders, ready/nonready and norestart runtime gating;
- invalid/duplicate arguments, malformed commit hashes, EOF without mutation;
- missing/old/malformed uv and simulated bitcoin execution denial before git;
- clone/fetch/checkout (or legacy reset)/sync/chmod/link/config/start failures,
  preserving previous markers, links, CLN config and shared checkout;
- ordinary start-failure restoration, plus failed rollback restart/link/config
  restoration: nonzero status, explicit incomplete-rollback diagnostic and
  retained staged sources rather than a false success;
- malformed/missing/wrong-type/ambiguous plugin-list responses fail closed;
- stop RPC errors **after** the fixture has stopped the old runtime, for both
  on and off: re-query, restore old runtime and preserve installation state;
- repeat enables use isolated checkouts; other networks and shared source bytes
  and mode remain unchanged; dependency sync precedes linking and runtime start;
- real distinct-UID mode-0700 staging and cwd behavior;
- actual prestart execution as bitcoin under the kernel no-new-privileges flag,
  with real sudo present, proving parking does not require privilege escalation;
- off parks fee options as tagged comments while leaving non-fee lines unchanged;
  actual service generation cannot re-enable it; the test reads the generated
  unit's `ExecStartPre` and executes the actual `cl.check.sh prestart` against
  synthetic files; parked options survive, and on restores them before the
  mocked runtime accepts start. Systemctl is inert throughout: no service starts.

Assertions are semantic, not dependent on a staging directory's random basename.
Markers are compared by key/value. CLN config is compared byte-for-byte except
for the intentional parked fee lines; the roundtrip must restore exact bytes.
No update verb or dependency bootstrap path is introduced.

Not covered: live RPC/plugin/fee behavior, uv resolver correctness, git remote
integrity, real systemd or sudo policy, concurrent invocation races,
filesystem-full conditions or abrupt process/power loss. These are offline
installer regressions, **not a live fee test or live-node acceptance test**.
