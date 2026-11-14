# uv and the eMudhra SSL certificate compromise

uv has an independent bundled trust store. Updating Debian's `ca-certificates` does not remediate an older default uv installation. The upstream [security advisory](https://github.com/astral-sh/uv/security/advisories/GHSA-hq85-5cpj-mr62) identifies 0.13.4 as the first fixed version. [uv PR 22777](https://github.com/astral-sh/uv/pull/22777) also updates rustls-webpki to reject the compromised intermediate public keys.

The Core Lightning installer and backup-plugin installer previously accepted any existing uv binary. Their `sudo -u bitcoin uv sync` and `uv run` invocations do not select OS roots explicitly. New installations now select uv 0.13.6; existing installations older than 0.13.4 fail before uv resolves dependencies, with an actionable update message. The backup guard runs even if the plugin is already loaded, because initialization and restoration still invoke uv. This patch deliberately does not overwrite an existing uv installation automatically.

## Verification

On an aarch64 Debian 12 RaspiBlitz node with the corrected OS CA package:

| Executable and policy | Four published incident hosts | Normal PyPI index |
| --- | --- | --- |
| Existing uv 0.10.4 default | Two accepted TLS and reached the plain-text response; two rejected | Passed |
| Existing uv 0.10.4 `--native-tls` | All rejected with `UnknownIssuer` | Passed |
| Official uv 0.13.6 default | All rejected with `CertDistrusted` | Passed |
| Official uv 0.13.6 `--native-tls` | All rejected with `CertDistrusted` | Passed |

The four HTTPS hosts were the publisher's documented `dv-g3b-emudhra.we-have-a-problem.com`, `dv-g3b-aaa-emudhra.we-have-a-problem.com`, `dv-g3b-noct-emudhra.we-have-a-problem.com`, and `dv-g3b-aaa-noct-emudhra.we-have-a-problem.com`, not invented key-rollover hostnames. The normal index was `https://pypi.org/simple`. Each invocation used `uv --no-config --no-cache [--native-tls] pip compile --no-build --index-url URL req.in -o OUTPUT -v`, with `certifi==2026.10.23` as the input. The tests disabled automatic Python downloads and cleared certificate-policy environment overrides. No application packages were installed or built, and no services were restarted. A content-type error after the incident response is TLS acceptance, not a successful security rejection.

After replacing the installed uv with the verified binary, default-policy metadata probes rejected all 14 incident endpoints and resolved the normal PyPI requirement. The same 15 checks passed as both the administrative user and the `bitcoin` user. The two narrowly patched installed scripts passed syntax checks and their actual version guards. No service restart or full application build was performed.

The candidate archive's published checksum and GitHub artifact attestation both verified:

- `uv-aarch64-unknown-linux-gnu.tar.gz`: SHA-256 `229e194255c7958d86d56e8790d969a6f74736592133f0dfd0076f754c642c1d`.
- Extracted `uv`: SHA-256 `7d60258dc76bca41d7b3591cdd829fa9633827fad944970bf5e1fb2a8c01476d`.

`python3 test/uv_trust_version_test.py` passed on Debian. It extracts and executes both actual version guards using Debian's real `dpkg --compare-versions`, with only the reported uv version mocked. It checks nine version-output cases per guard, pinned install sources, and guard placement before dependency resolution. Both changed shell scripts passed `bash -n`; `git diff --check` passed. Full Core Lightning installation, backup restoration, and package-building paths were not executed.

## Isolated production-path regression tests

Run `UV_TEST_PLATFORM=linux/arm64 python3 test/uv_installer_execution_test.py`
and repeat with `UV_TEST_PLATFORM=linux/amd64`. Docker is required; the first run
may pull the Python/Debian image before the network-disabled test container starts.
The focused GitHub Actions workflow runs on native amd64 and arm64 runners for
pull requests, manual dispatch, and pushes to the existing `fix/uv-emudhra-trust`
branch (also the originally requested `fix/uv-cve-2026-44891` name).

The suite streams the complete, byte-unchanged production scripts and worker over
stdin, without host mounts, then invokes `bash cl.install.sh install` and
`bash cl-plugin.backup.sh on mainnet`. It does not extract or copy version guards.
Containers have no network, no capabilities, and no privilege escalation; temporary
files live in disposable container filesystems/tmpfs. Package managers, downloads,
RPC, build tools and services are inert recording fixtures. File operations, Bash
control flow, `dpkg --compare-versions`, and `uname -m` execute for real. The sudo
fixture executes commands without changing identity: this is not a sudo/ownership
test. Source digests are printed in each run.

Each architecture runs 20 cases: missing, vulnerable, minimum-fixed (0.13.4),
fixed, malformed version, empty/partial installer download failure, installer
execution failure, and uv sync failure for both scripts; cargo failure for CLN;
already-loaded plugin for backup. Assertions check the injected operation was
reached and that failure prevents build, backup initialization and service changes.
Loaded plugins skip sync but still check uv and run initialization. Architecture
comes from the actual container, not a mocked `uname`: CLN delegates target choice
to Cargo (no explicit `--target`), backup delegates it to the remote uv installer.
The suite tests those production delegations on both architectures, not upstream
Cargo compilation or the upstream installer's internal artifact-selection logic.
The older guard-only suite remains supplementary coverage for additional versions.

These tests exposed swallowed `uv sync` failures in both scripts and a swallowed
Rust installer download failure. The scripts now stop on those errors; pipeline
status is checked with scoped `pipefail`, including the backup installer pipeline.
No TLS probes, real packages, full compilation, backup databases or Raspberry Pi
hardware are exercised by this suite. The node/TLS observations above are prior
manual evidence, not reproduced by these isolated tests.

## Remote-installer trust boundary

The backup fallback downloads and executes a version-pinned HTTPS script as root.
**This code path does not verify the script with a checksum or attestation.** Its
architecture selection and any subsequent downloads are also delegated to that
remote code. The prior manually verified archive/attestation above does not verify
this installer path. The Rust bootstrap likewise executes a remote HTTPS script.

The missing-uv test supplies an intentionally unsigned inert shell payload and
asserts it actually executes, installs the uv fixture, and continues; no checksum
or GPG command occurs in that backup path. Partial-download tests supply executable
content and then return a curl error, asserting the installer aborts before sync
or service changes even if the payload created uv. `pipefail` detects transfer
failure but cannot undo code already streamed into the shell or authenticate it.
These are explicit trust-boundary tests, not a claim of cryptographic verification.

## Configuration boundary

No global TLS policy, local CA files, or existing application configuration is changed. A version floor cannot certify an administrator's custom trust or insecure-host overrides. Review `SSL_CERT_FILE`, `SSL_CERT_DIR`, `UV_INSECURE_HOST`/`allow-insecure-host`, and uv configuration independently. Per the [versioned uv documentation](https://github.com/astral-sh/uv/blob/0.13.6/docs/concepts/authentication/certificates.md), non-empty custom CA file/directory settings replace the default certificate source rather than add to it. Those custom stores must also be remediated.

uv 0.13.6 supports `--system-certs`, `UV_SYSTEM_CERTS=true`, or `system-certs = true` to select OS trust, preserving administrator-installed OS CAs. `--native-tls` remains a deprecated alias. OS-store selection is an alternative only after verifying the effective OS store, custom CA overrides, and the installed uv version's supported semantics. It is not needed to remediate the verified default 0.13.6 candidate, and no environment-wide setting is proposed here.
