# Python trust regression tests

Tests for `home.admin/config.scripts/blitz.python-trust.sh` and its callers
(`build_sdcard.sh`, `_provision.update.sh`, `blitz.web.api.sh`,
`bonus.joinmarket.sh`). CI runs them via `.github/workflows/python-trust.yml`.

## Bootstrap and shell tests

Use Python 3.10 or 3.11 (pip 23.0.1 predates Python 3.12). The suite downloads
pip/certifi wheels from PyPI into a temp dir and only writes temporary venvs.
Production shell blocks are executed with inert command fixtures; nothing
touches services or system packages.

```sh
python3.11 -m unittest discover -s tests -p 'test_python_trust_*.py' -v
```

## Debian system pip

`python-trust-system.py` writes to `/usr/local`, so run it only inside its
disposable container:

```sh
docker build -f tests/python-trust.Dockerfile -t python-trust-system .
docker run --rm --network=none --cap-drop=ALL --security-opt=no-new-privileges python-trust-system
```

## Manual TLS regression (not in CI)

`python-trust-regression.py` checks requests/httpx/pip defaults against the
public incident chains from <https://emudhra.we-have-a-problem.com/>. Run it in
an isolated venv:

```sh
python tests/python-trust-regression.py --chains "$CHAINS" --openssl "$OPENSSL3" \
  --expect clean --live --output after.json
```

These tests do not cover full image builds, reboots, or live systemd repair.
