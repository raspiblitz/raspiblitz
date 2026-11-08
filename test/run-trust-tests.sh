#!/bin/bash
# Run only inside the disposable test image; never mount a host trust directory.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 test/trust_static.py
bats test/blitz.trust.bats
node --test test/test_node_trust.js
umask 077
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
javac -d "$fixture" test/JavaTrustProbe.java
java -cp "$fixture" JavaTrustProbe build test/fixtures/java-trust-anchors.pem "$fixture/public-only.jks"
keytool -J-Duser.language=en -J-Duser.country=US -list -rfc -keystore "$fixture/public-only.jks" -storepass changeit > "$fixture/public-list.txt"
JAVA_TRUST_PUBLIC_LISTING="$fixture/public-list.txt" python3 -m unittest discover -s test -p 'test_*trust*.py' -v
# The before fixture adds only archived public incident anchors to the container's
# signed Debian public CA package. It is not a historical full-store/dpkg test.
python3 - "$fixture" <<'PY'
import hashlib
from pathlib import Path
import sys
import zipfile
p = Path(sys.argv[1])
anchors = Path('test/fixtures/java-trust-anchors.pem')
assert hashlib.sha256(anchors.read_bytes()).hexdigest() == 'd622a0e5ba04e89a4a75eac94a2faac752473f325294be037ec3cdb6d09909ec'
z = Path('test/fixtures/incident-chains.zip')
assert hashlib.sha256(z.read_bytes()).hexdigest() == 'afb9d69e8e5fc9eb0c08d5fe4baafc67edbcced2d63af2f9deb62edb6431d4a9'
with zipfile.ZipFile(z) as archive:
    for name in archive.namelist():
        target = (p / name).resolve()
        assert target.is_relative_to(p.resolve())
    archive.extractall(p)
(p / 'before.pem').write_bytes(Path('/etc/ssl/certs/ca-certificates.crt').read_bytes() + Path('test/fixtures/java-trust-anchors.pem').read_bytes())
PY
java -cp "$fixture" JavaTrustProbe build "$fixture/before.pem" "$fixture/before.jks"
cp "$fixture/before.jks" "$fixture/after.jks"
python3 home.admin/config.scripts/blitz.trust.java.py update --keystore "$fixture/after.jks"
keytool -J-Duser.language=en -J-Duser.country=US -list -rfc -keystore "$fixture/after.jks" -storepass changeit > "$fixture/after-list.txt"
python3 - "$fixture" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
(p / 'after.pem').write_text('\n'.join(re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', (p / 'after-list.txt').read_text(), re.S)))
PY
python3 test/trust_store_regression.py --before "$fixture/before.pem" --after "$fixture/after.pem" --chains "$fixture/chains"
args=(--java "$(command -v java)" --classes "$fixture" --before "$fixture/before.jks" --after "$fixture/after.jks" --chains "$fixture/chains" --output "$fixture/results.json")
if [ "${1:-offline}" = live ]; then
  python3 test/java_trust_regression.py "${args[@]}"
  node test/trust_tls_probe.js
else
  python3 test/java_trust_regression.py "${args[@]}" --offline-only
fi
