# Public-download TLS regression checks

Run `bash test/public-download-tls.sh` with Python 3, Bash, **GNU wget**, OpenSSL and ShellCheck installed. This is also the entry point for `.github/workflows/public-download-tls.yml`, which runs on pull requests, pushes to the existing `fix/public-download-ssl-verification` source branch, and manual dispatch. The runner checks Bash syntax for all six affected production scripts and itself, runs the repository's existing ShellCheck error-level gate (plus all levels for the new runner), and checks Python syntax before executing the TLS tests. No checks are disabled.

The tests never run installers, real sudo, GPG imports, service operations, or package upgrades. Temporary fixtures honor `TMPDIR`. All transfers use real GNU wget against ephemeral loopback servers, with bounded timeouts/retries and no proxy or wget configuration. A test-only CA enables positive controls without changing system trust.

## Coverage

- The actual signer-key download commands from LND install/update, Pool and chantools, plus the authorized-key download from the amd64 packer initializer, run with both absent and pre-existing output files. Each combination tests untrusted certificates, hostname mismatch, HTTP 500, truncated responses, and trusted success. Failed downloads must exit before a recording GPG/continuation sentinel; success must replace stale bytes with the exact fixture body. No `set -e` is added to these snippets: their production failure guards must work themselves.
- The actual Sphinx readiness block runs in all six connection modes and an unknown-mode fail-closed control, through both direct and recording torsocks-stub routes. Every combination tests untrusted certificates, hostname mismatch, trusted success, unexpected response content, HTTP 500, truncated `INDEX`, and plain HTTP. Only the two explicit self-signed modes may bypass certificate verification. Pre-seeded response/TLS variables test that stale state is reset. Both route selection and the reported readiness result are asserted.
- These are 148 transfer/readiness scenarios in three unittest methods. Every changed download failure guard and both Sphinx TLS/routing branches take success and failure paths. This is bounded command/block coverage, not whole-installer coverage or an instrumented line-coverage percentage.

The truncated-response case found a real readiness defect: GNU wget can emit `INDEX` before reporting an incomplete transfer. Sphinx now clears the response on download failure instead of reporting readiness from those partial bytes.

## Isolation and limits

For an image containing the tools above, the same runner can execute with a read-only source mount, dropped capabilities and external networking disabled (loopback remains available):

```sh
docker run --rm --network none --read-only --cap-drop ALL \
  --tmpfs /tmp:rw,nosuid,noexec -v "$PWD:/src:ro" -w /src \
  YOUR_TEST_IMAGE bash test/public-download-tls.sh
```

The torsocks stub tests routing choice, not Tor transport. Plain HTTP/onion transport is not made confidential by these changes. No full LND/Pool/chantools installation, release artifact signature validation, appliance/hardware operation, or current public-host TLS check is performed. The fixture signer key is synthetic data, not valid OpenPGP material. Existing signature/checksum policy is otherwise unchanged; these tests demonstrate that failed key retrieval cannot continue into its consumer, not that the entire existing authenticity implementation is sound. CA/vendor trust updates remain necessary.
