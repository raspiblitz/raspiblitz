# Running tests

## Install bats
```
sudo apt install bats
```

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
```

## Offline kernel dependency regression (Linux)

Requires `bats`, `python3`, `apt-get`, and `dpkg`. From the repository root:

```
bats test/kernel-upgrade.bats
# Or without Bats:
python3 test/kernel_upgrade_solver.py
```

Run as an ordinary user; no sudo, node access, package installation, or reboot
is needed. The test extracts only the system upgrade argv from `build_sdcard.sh`,
`blitz.release.sh`, and `_bootstrap.sh`; it never executes those scripts. Real
APT reads a temporary file-only repository and isolated package status/config,
then runs `--simulate`. Tests cover the old command holding a new kernel ABI
dependency back, the production command accepting it, conflicts without removals,
and explicit package holds. The fixture packages are synthetic and do not
represent a published kernel or establish that any vulnerability is fixed.

The release command's source-list override is superseded by the local fixture;
repository selection, availability of vendor fixes, maintainer scripts, booting,
and the release `-quick` branch are outside this solver test. Existing flags
(including build `-f` and dpkg config options) are otherwise preserved.
The dedicated `test-kernel-upgrade.yml` workflow runs this regression without
triggering the unrelated PostgreSQL integration workflow.
