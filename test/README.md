# Running tests

## Install bats
```
sudo apt install bats
```

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
bats --verbose-run ./bonus.btcpayserver.bats
```

`bonus.btcpayserver.bats` stubs `sudo` and needs no RaspiBlitz, it also runs in CI
(`.github/workflows/btcpayserver-script-tests.yml`).
