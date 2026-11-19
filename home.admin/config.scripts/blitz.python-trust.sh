#!/usr/bin/env bash
# Independent Python stores do not inherit removals from ca-certificates.
# Run as the venv owner. Never rewrite bundles or override dependency constraints.
set -euo pipefail
mode=${1:?Usage: blitz.python-trust.sh pip|system-pip|app PYTHON [BOOTSTRAP_CA_FILE]}
python=${2:?Specify the Python executable}
bootstrap_ca=${3:-/etc/ssl/certs/ca-certificates.crt}
case "$mode" in
  pip|system-pip|app) ;;
  *) echo "Unknown trust check mode" >&2; exit 1 ;;
esac

check_bundle() {
  "$python" - "$1" "$bootstrap_ca" <<'PY'
import hashlib
import os
import pathlib
import re
import ssl
import sys

mode = sys.argv[1]
# Requests environment overrides pip's --cert. Preserve that effective order;
# SSL_CERT_FILE and the positional bundle are lower-priority bootstrap fallbacks.
from pip._internal.commands import create_command
options, _ = create_command("install").parse_args([])
overrides = [os.environ.get("REQUESTS_CA_BUNDLE"), os.environ.get("CURL_CA_BUNDLE"),
             options.cert, os.environ.get("SSL_CERT_FILE")]
overrides = [path for path in overrides if path]
selected = next(iter(overrides), sys.argv[2])
if mode == "bootstrap":
    bundle = selected
elif mode == "pip":
    from pip._vendor import certifi
    bundle = certifi.where()
elif mode == "app":
    import certifi
    bundle = certifi.where()
else:
    bundle = mode
blocked = {
    "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
    "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4",
}
# Check even shadowed explicit files: later requirements/application clients may
# select them differently. Directories/lazy native stores are outside this check.
for path in dict.fromkeys([bundle] + overrides):
    pem = pathlib.Path(path).read_text(encoding="ascii")
    certs = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem, re.S)
    if not certs:
        sys.exit("No trust anchors found; refusing to continue")
    roots = {hashlib.sha256(ssl.PEM_cert_to_DER_cert(c)).hexdigest() for c in certs}
    if roots & blocked:
        sys.exit("Affected emSign anchor remains in Python trust store; update its owner package")
    # Parse the complete file, not only the matching PEM blocks.
    ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT).load_verify_locations(path)
print(selected if mode == "bootstrap" else "Python trust bundle check passed")
PY
}

if [ "$mode" != app ]; then
  "$python" - <<'PY'
import sys
if sys.version_info < (3, 10):
    sys.exit("Python >=3.10 is required for the fixed pip>=26.2.2; upgrade the image/Python first")
PY
  bootstrap_ca=$(check_bundle bootstrap)
  # Old pip defaults to certifi alone and does not know legacy-certs. Modern
  # pip preloads vendor roots into truststore, so --cert alone is additive.
  legacy=()
  legacy_option=$("$python" - <<'PY'
import pip
from pip._internal.commands import create_command
from pip._vendor.packaging.version import Version
command = create_command("install")
options, _ = command.parse_args([])
if options.trusted_hosts:
    raise SystemExit("Refusing insecure trusted-host override during pip bootstrap")
from urllib.parse import urlsplit
sources = list(options.find_links)
if not options.no_index:
    sources += [options.index_url] + list(options.extra_index_urls)
if any(urlsplit(source).scheme not in ("", "file", "https") for source in sources):
    raise SystemExit("Pip bootstrap requires HTTPS indexes/download links or local wheels")
if "legacy-certs" in command.parser.get_option("--use-deprecated").choices:
    print("--use-deprecated=legacy-certs")
elif Version(pip.__version__) >= Version("24.2"):
    raise SystemExit("This pip enables truststore but lacks legacy-certs; no verified system-only bootstrap is available")
elif "truststore" in options.features_enabled:
    raise SystemExit("Old pip has opt-in truststore enabled; disable that option for system-only bootstrap")
PY
)
  if [ -n "$legacy_option" ]; then
    legacy=("$legacy_option")
  fi
  target=()
  if [ "$mode" = system-pip ]; then
    # Debian's posix_local scheme doubles /local with --prefix=/usr/local.
    # --target never uninstalls the distribution's pip. Do not use PEP 668's
    # override or remove EXTERNALLY-MANAGED to perform this repair.
    local_packages=$("$python" - <<'PY'
import pathlib
import sys
if sys.platform != "linux" or sys.prefix != sys.base_prefix:
    sys.exit("system-pip requires Debian system Python, not a venv")
target = f"/usr/local/lib/python{sys.version_info.major}.{sys.version_info.minor}/dist-packages"
if target not in sys.path or not pathlib.Path("/etc/debian_version").is_file():
    sys.exit("Unsupported system Python installation scheme; expected Debian local dist-packages")
print(target)
PY
)
    target=(--target "$local_packages")
  fi
  REQUESTS_CA_BUNDLE="$bootstrap_ca" CURL_CA_BUNDLE="$bootstrap_ca" SSL_CERT_FILE="$bootstrap_ca" \
    "$python" -m pip ${legacy[@]+"${legacy[@]}"} --cert "$bootstrap_ca" \
    install --upgrade ${target[@]+"${target[@]}"} 'pip>=26.2.2'
  if [ "$mode" = system-pip ]; then
    "$python" - "$local_packages" <<'PY'
import pathlib
import pip
import sys
if pathlib.Path(pip.__file__).parent != pathlib.Path(sys.argv[1]) / "pip":
    sys.exit("System Python is not importing the repaired local pip; refusing to continue")
PY
    check_bundle pip
    for entry in pip pip3 "pip$($python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"; do
      install -m 755 "$local_packages/bin/$entry" "/usr/local/bin/$entry"
    done
  fi
  mode=pip
fi
check_bundle "$mode"
