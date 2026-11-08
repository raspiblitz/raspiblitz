#!/usr/bin/env python3
"""Opt-in real Java old/new store tests; no default-store fallback or TLS bypass."""
import argparse
import concurrent.futures
import json
from pathlib import Path
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--java", required=True)
    p.add_argument("--classes", required=True)
    p.add_argument("--before", required=True)
    p.add_argument("--after", required=True)
    p.add_argument("--chains", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--offline-only", action="store_true",
                   help="Run all 32 real archived-chain checks, without live HTTPS")
    args = p.parse_args()
    chains = sorted(args.chains.rglob("*.pem"))
    expected = {
        f"{kind}-{gen}{cross}-emudhra.we-have-a-problem.com.pem"
        for kind in ("dv", "ov", "ev") for gen in ("g3b", "g3c") for cross in ("", "-aaa")
    } | {
        f"dv-g3b{cross}-noct{rollover}-emudhra.we-have-a-problem.com.pem"
        for cross in ("", "-aaa") for rollover in ("", "-rollover")
    }
    assert len(chains) == 16 and {c.name for c in chains} == expected
    tasks = []
    for state in ("before", "after"):
        store = getattr(args, state)
        for chain in chains:
            tasks.append((state, store, "chain", str(chain), 0 if state == "before" else 2))
            if not args.offline_only and "rollover" not in chain.name:
                # These 14 live names match the publisher inventory and Node probe.
                # The two offline-only rollover fixtures are deliberately not probed.
                host = chain.stem
                tasks.append((state, store, "tls", f"https://{host}/", 0 if state == "before" else 2))
        if not args.offline_only:
            for host in ("bitcoincore.org", "api.github.com", "registry.npmjs.org", "pypi.org"):
                tasks.append((state, store, "tls", f"https://{host}/", 0))

    def run(task):
        state, store, mode, target, expected_code = task
        result = subprocess.run([args.java, "-cp", args.classes, "JavaTrustProbe", mode, store, target],
                                capture_output=True, text=True, timeout=45)
        output = result.stdout.strip()
        passed = result.returncode == expected_code
        if mode == "tls" and expected_code == 2:
            passed = passed and output.startswith("REJECT CERTIFICATE ")
        if mode == "tls" and expected_code == 0:
            passed = passed and output == "ACCEPT HTTP 200"
        return dict(state=state, mode=mode, target=target, expected_code=expected_code,
                    returncode=result.returncode, passed=passed, stdout=output, stderr=result.stderr.strip())

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(run, tasks):
            results.append(result)
            args.output.write_text(json.dumps(results, indent=2))
            print(("PASS" if result["passed"] else "FAIL"), result["state"], result["mode"],
                  result["target"], result["stdout"], flush=True)
    print(f"{sum(r['passed'] for r in results)}/{len(results)} passing checks")
    raise SystemExit(0 if all(r["passed"] for r in results) else 1)


if __name__ == "__main__":
    main()
