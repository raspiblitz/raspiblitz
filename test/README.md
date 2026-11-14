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

## Core Lightning wallet creation (cl.hsmtool.sh, cl.hsmsecret.py)
Needs `pip install mnemonic==0.19 coverage`, the real-CLN tests also need docker.
Run in CI by `.github/workflows/cl-hsmtool-tests.yml`.
```
python3 -m coverage run --branch --include='*/cl.hsmsecret.py' -m unittest -v test_cl_hsmsecret.py
python3 -m coverage report -m --fail-under=100
bats ./cl.hsmtool.hsmsecret.bats
CL_HSMTOOL_REQUIRE_DOCKER=1 bats ./cl.hsmtool.real-cln.bats
```

## Python unit tests
```
pip install requests
python3 -m unittest -v test_ip2tor_pay.py
```
