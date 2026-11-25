# Running tests

## Install bats
```
sudo apt install bats
```

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
bats --verbose-run ./bonus.lnbits.bats
bats --verbose-run ./lnbits-update-policy.bats
```

### LNbits menu and wallet integration tests

Use a disposable RaspiBlitz installation with an installed, running LNbits predecessor, the **VoidWallet** backend, local-only test access, account creation enabled for the fixture, and either PostgreSQL or SQLite. Install the candidate scripts and keep the old LNbits service and data as the starting point. The runner uses the actual `admin` menu, `tmux`, Python 3, systemd and the local LNbits HTTP API. Its wallet has zero balance. The fixture stores its temporary wallet key in a root-only directory.

```bash
sudo install -d -m 0700 /run/raspiblitz-lnbits-e2e
sudo python3 test/lnbits-update-e2e.py prepare
# Save the full fixture here. Restore it before each independent update case.
sudo python3 test/lnbits-update-e2e.py retry
sudo python3 test/lnbits-update-e2e.py postgres-restore
```

The default predecessor is the official v1.7.0 commit. For a v1.2.1 fixture, pass `--from-commit 88b01e60795c488ae9fd8c2e634f3d218b901aaa` to an update case. `update` checks the menu, exact target revision, HTTP health, wallet ID, name and balance. `keep-stopped` checks the safe default after a failed backup, including a subsequent start attempt. `retry` repairs the backup destination while the error dialog is open and finishes the update. `failed-start` stops the first start of the updated service and retries from the visible error dialog. `stopped` checks that a previously inactive installation stays inactive after a successful command-line update.

Run `previous` on the **updated, healthy target version**. This case denies the release fetch locally, selects an explicit restart of the verified version and checks the wallet. Both v1.2.1 and v1.7.0 require the security update. Run `custom-unit` on a running fixture to verify that an effective systemd command with a different port is rejected before service interruption. On a healthy target, `interrupted` terminates the updater during a controlled failed systemd start, checks the persistent start guard, and recovers the wallet by retrying.

Run `postgres-restore` or `sqlite-restore` against the matching fixture after an update. Each case changes the test wallet name, rejects an unrelated archive, interrupts the first application start after a restore and checks the recovered wallet through its API. In operation the restore reports where the previous database or data directory was retained. Verify the recovered wallet before retiring that copy.
