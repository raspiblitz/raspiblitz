# Running tests

## Install bats
```
sudo apt install bats
```

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
bats --verbose-run ./bonus.boltzcli.bats
```

## Notes
- `bonus.boltzcli.bats` requires a running Lightning node (CLN or LND) and will skip if neither is available
