#!/usr/bin/env python3
"""Manual regression: actual client defaults, incident fixtures, and optional TLS.

Run in an isolated venv with requests, httpx, and pip installed. Supply the
published incident chain directory (16 PEM chains) and OpenSSL 3 executable.
This does not import the application or read service configuration.
"""

import argparse
import concurrent.futures
import hashlib
import json
import pathlib
import re
import ssl
import subprocess
import tempfile

from pip._internal.cli.index_command import _create_truststore_ssl_context
from pip._internal.network.session import PipSession

BLOCKED = {
    "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
    "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4",
}


def contexts(pip_only=False):
    if pip_only:
        context = _create_truststore_ssl_context()
        assert context is not None, "pip truststore was not enabled"
        return {"pip_explicit_roots": context._ctx}
    import httpx
    import requests

    session = requests.Session()
    session.trust_env = False
    adapter = session.get_adapter("https://pypi.org")
    request = requests.Request("GET", "https://pypi.org").prepare()
    conn = adapter.get_connection_with_tls_context(request, True)
    adapter.cert_verify(conn, request.url, True, None)
    request_context = ssl.create_default_context(cafile=conn.ca_certs)
    session.close()
    with httpx.Client(trust_env=False) as client:
        httpx_context = client._transport._pool._ssl_context
    pip_context = _create_truststore_ssl_context()
    assert pip_context is not None, "pip truststore was not enabled"
    return {
        "requests": request_context,
        "httpx": httpx_context,
        # truststore's native system roots are not enumerable on every OS.
        # The underlying context exposes explicitly loaded vendor roots; live
        # tests below exercise the complete actual pip context, not this export.
        "pip_explicit_roots": pip_context._ctx,
    }


def live_probe(item):
    name, host, negative = item
    if name == "requests":
        import requests

        client = requests.Session()
        client.trust_env = False
    elif name == "httpx":
        import httpx

        client = httpx.Client(trust_env=False)
    else:
        client = PipSession(ssl_context=_create_truststore_ssl_context())
        client.trust_env = False
    try:
        client.get("https://" + host, timeout=20)
        return name, host, "accepted", not negative
    except Exception as exc:
        # DNS, connection, HTTP, and timeout errors must not count as rejection.
        text = repr(exc)
        validation = (
            "CERTIFICATE_VERIFY_FAILED" in text
            or "SSLVerificationError" in type(exc).__name__
        )
        return (
            name,
            host,
            "certificate_rejected" if validation else type(exc).__name__,
            negative and validation,
        )
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chains", type=pathlib.Path, required=True)
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--expect", choices=["affected", "clean"], required=True)
    parser.add_argument("--pip-expect", choices=["affected", "clean"])
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--pip-only", action="store_true")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    fixtures = sorted(args.chains.rglob("*.pem"))
    assert len(fixtures) == 16, "Expected all 16 published incident chains"
    assert len({hashlib.sha256(p.read_bytes()).digest() for p in fixtures}) == 16
    results = {"versions": {}, "offline": [], "live": []}
    from importlib.metadata import version

    packages = ("pip",) if args.pip_only else ("certifi", "pip", "requests", "httpx")
    results["versions"] = {p: version(p) for p in packages}
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for name, context in contexts(args.pip_only).items():
            expected = (
                (args.pip_expect or args.expect)
                if name == "pip_explicit_roots"
                else args.expect
            )
            roots = context.get_ca_certs(binary_form=True)
            fingerprints = {hashlib.sha256(c).hexdigest() for c in roots}
            affected = sorted(fingerprints & BLOCKED)
            assert bool(affected) == (expected == "affected"), (name, affected)
            bundle = tmp / "roots.pem"
            bundle.write_text("".join(ssl.DER_cert_to_PEM_cert(c) for c in roots))
            statuses = []
            for fixture in fixtures:
                certs = re.findall(
                    r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
                    fixture.read_text(),
                    re.S,
                )
                leaf, chain = tmp / "leaf.pem", tmp / "chain.pem"
                leaf.write_text(certs[0] + "\n")
                chain.write_text("\n".join(certs[1:]) + "\n")
                command = [
                    args.openssl,
                    "verify",
                    "-CAfile",
                    str(bundle),
                    "-no-CApath",
                    "-no-CAstore",
                    "-untrusted",
                    str(chain),
                    str(leaf),
                ]
                process = subprocess.run(command, text=True, capture_output=True)
                if process.returncode == 0:
                    statuses.append("accepted")
                else:
                    assert "unable to get local issuer certificate" in process.stderr, (
                        process.stderr
                    )
                    statuses.append("unknown_issuer")
            accepted = statuses.count("accepted")
            assert accepted == (8 if expected == "affected" else 0), (name, statuses)
            results["offline"].append(
                {
                    "consumer": name,
                    "roots": len(roots),
                    "affected": affected,
                    "chains": len(statuses),
                    "accepted": accepted,
                }
            )
    if args.live:
        # Clean-state acceptance only; affected baselines are checked offline.
        assert args.expect == "clean" and (args.pip_expect or args.expect) == "clean"
        hosts = [
            p.name.removesuffix(".pem") for p in fixtures if p.parent.name == "regular"
        ]
        assert len(hosts) == 14, "Rollover chains have no live hosts"
        consumers = ("pip",) if args.pip_only else ("requests", "httpx", "pip")
        work = [(n, h, True) for n in consumers for h in hosts]
        work += [(n, "pypi.org", False) for n in consumers]
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results["live"] = list(pool.map(live_probe, work))
    args.output.write_text(json.dumps(results, indent=2) + "\n")
    assert all(row[3] for row in results["live"]), results["live"]
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
