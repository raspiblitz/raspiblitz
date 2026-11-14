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
bats --verbose-run ./bonus.lnbits.bats
```

`bonus.btcpayserver.bats` and `bonus.lnbits.bats` stub `sudo` and need no RaspiBlitz, they also run in CI
(`.github/workflows/btcpayserver-script-tests.yml`, `.github/workflows/lnbits-script-tests.yml`).

## Python unit tests
```
pip install requests
python3 -m unittest -v test_ip2tor_pay.py
```
