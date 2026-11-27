# Running tests

For shutdown regressions, see [Watchdog and power-cycle tests](watchdog-shutdown.md).

## Install bats
```
sudo apt install bats
```

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
```
