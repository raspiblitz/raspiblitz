#!/bin/bash

# Vendor packages plus scoped Java incident anchors (emSign ECC Root CA - G3 and
# the AAA Certificate Services cross-sign route, Debian DLA-4845-1 / DSA-6572-1).
if [ "$#" -ne 1 ] || { [ "$1" != update ] && [ "$1" != check ]; }; then
  echo "Usage: blitz.trust.sh [update|check]"
  exit 1
fi

fail() {
  echo "FAIL - $* Check security repositories, package pins/holds, and runtime overrides." >&2
  exit 1
}

installed() {
  [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = installed ]
}

# Debian, Ubuntu, Armbian and Raspberry Pi OS share the APT/dpkg CA layout.
# Anything else is outside this vendor-package scope: warn, do not abort setup.
if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-query >/dev/null 2>&1; then
  echo "WARN - No APT/dpkg CA trust layout; vendor trust refresh skipped." >&2
  exit 0
fi

if [ "$1" = update ]; then
  packages=(ca-certificates)
  if installed nodejs; then packages+=(nodejs); fi
  if installed ca-certificates-java; then packages+=(ca-certificates-java); fi
  # Do not override holds/pins or accept a partial index refresh.
  sudo apt-get -o APT::Update::Error-Mode=any update || fail "APT index refresh failed."
  sudo apt-get install --only-upgrade -y "${packages[@]}" || fail "Trust package upgrade failed."
  sudo update-ca-certificates --fresh || fail "Trust bundle refresh failed."
fi

# Offline fail-closed postconditions, not network probes or package-command success.
# Debian DLA-4845-1 / DSA-6572-1 remove ECC G3 AND the AAA cross-sign route.
ID='' VERSION_ID='' minimum=''
# shellcheck disable=SC1091
[ -r /etc/os-release ] && source /etc/os-release
case "$ID:$VERSION_ID" in
  debian:12) minimum='20250419~deb12u2' ;;
  debian:13) minimum='20250419+deb13u1' ;;
esac
installed ca-certificates || fail "ca-certificates is not installed."
if [ -n "$minimum" ]; then
  ca_version=$(dpkg-query -W -f='${Version}' ca-certificates 2>/dev/null)
  dpkg --compare-versions "$ca_version" ge "$minimum" || fail "ca-certificates $ca_version needs >= $minimum."
else
  # Other distributions version the package differently (e.g. Ubuntu): check
  # the generated bundle for the two incident anchors instead.
  bundle=/etc/ssl/certs/ca-certificates.crt
  python3 - "$bundle" <<'PY' || fail "OS CA bundle $bundle is unreadable or still trusts an incident anchor."
import hashlib, re, ssl, sys
denied = {"86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
          "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4"}
pems = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", open(sys.argv[1]).read(), re.S)
sys.exit(not pems or any(hashlib.sha256(ssl.PEM_cert_to_DER_cert(c)).hexdigest() in denied for c in pems))
PY
  echo "No reviewed CA package baseline for ${ID:-unknown} ${VERSION_ID}; OS bundle excludes the incident anchors."
fi

# Official October 21, 2026 security releases, only on reviewed supported lines.
# Check the executable too: a PATH override must not hide behind a fixed package.
if installed nodejs || command -v node >/dev/null 2>&1; then
  node_version=$(node -v 2>/dev/null) || fail "Installed Node.js cannot run."
  [[ "$node_version" =~ ^v(22|24|26)\.[0-9]+\.[0-9]+$ ]] || fail "Unsupported Node.js $node_version."
  case "$node_version" in
    v22.*) minimum=22.23.4 ;;
    v24.*) minimum=24.22.1 ;;
    v26.*) minimum=26.12.1 ;;
  esac
  dpkg --compare-versions "${node_version#v}" ge "$minimum" || fail "Node.js $node_version needs >= $minimum on its major line."
fi

# Debian's OS refresh does not reliably propagate removals to Java (Debian
# #1069251). A Java fresh trigger can also delete directly imported debian:
# entries. Apply only the two reviewed incident identities, preserving others.
if installed ca-certificates-java || command -v java >/dev/null 2>&1; then
  # sudo may discard caller overrides. Reject them before crossing that boundary.
  for option in JAVA_HOME JRE_HOME JAVACMD JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS JAVA_OPTS MAVEN_OPTS MAVEN_ARGS MAVEN_CONFIG M2_HOME MAVEN_PROJECTBASEDIR MAVEN_BASEDIR; do
    [ -z "${!option}" ] || fail "Explicit $option needs separate Java trust review."
  done
  java_helper=/home/admin/config.scripts/blitz.trust.java.py
  if [ "$1" = update ]; then
    sudo python3 "$java_helper" update || fail "Java trust remediation failed."
  else
    sudo python3 "$java_helper" check || fail "Java trust check failed."
  fi
fi

echo "Vendor trust package baselines and scoped Java anchors verified. Restart consumers after updates."
echo "Independent application bundles and explicit CA overrides need separate checks."
