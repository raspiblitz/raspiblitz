#!/usr/bin/env python3
"""Offline incident regression using externally supplied, real certificate chains."""
import argparse
import hashlib
from pathlib import Path
import re
import ssl
import subprocess


def fingerprints(bundle):
    return {
        hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert)).hexdigest()
        for cert in re.findall(
            r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
            bundle.read_text(), re.S,
        )
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True, type=Path)
    parser.add_argument("--after", required=True, type=Path)
    parser.add_argument("--chains", required=True, type=Path)
    parser.add_argument("--openssl", default="openssl")
    args = parser.parse_args()
    roots = {
        "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
        "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4",
    }
    if not roots <= fingerprints(args.before):
        raise AssertionError("Before bundle must contain both incident trust anchors")
    if roots & fingerprints(args.after):
        raise AssertionError("After bundle still contains an incident trust anchor")
    chains = sorted(args.chains.rglob("*.pem"))
    expected = {
        f"{kind}-{gen}{cross}-emudhra.we-have-a-problem.com.pem"
        for kind in ("dv", "ov", "ev")
        for gen in ("g3b", "g3c")
        for cross in ("", "-aaa")
    } | {
        f"dv-g3b{cross}-noct{rollover}-emudhra.we-have-a-problem.com.pem"
        for cross in ("", "-aaa")
        for rollover in ("", "-rollover")
    }
    if len(chains) != 16 or {p.name for p in chains} != expected:
        raise AssertionError("Expected the complete 14 regular and 2 rollover chains")
    for chain in chains:
        results = []
        for bundle in (args.before, args.after):
            results.append(subprocess.run([
                args.openssl, "verify", "-no-CApath", "-no-CAstore",
                "-CAfile", str(bundle), "-untrusted", str(chain), str(chain),
            ], capture_output=True, text=True))
        if results[0].returncode != 0:
            raise AssertionError(f"Baseline does not reproduce exposure: {chain.name}")
        if results[1].returncode == 0 or "error 20 at" not in results[1].stderr:
            raise AssertionError(f"Expected unknown issuer rejection: {chain.name}")
        print(f"PASS {chain.name}: accepted before, unknown issuer after")
    print("PASS 16 real incident chains, including both cross-sign paths and key rollover")


if __name__ == "__main__":
    main()
