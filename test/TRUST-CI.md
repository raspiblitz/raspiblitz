# Trust regression CI

Run the same suite as `.github/workflows/test-trust.yml`, with Docker only:

```sh
docker build -f test/trust.Dockerfile -t raspiblitz-trust-tests .
docker run --rm --network none raspiblitz-trust-tests
docker run --rm raspiblitz-trust-tests bash test/run-trust-tests.sh live
```

No host CA paths, trust stores, service sockets or Docker socket are mounted.
The workflow runs on PRs, pushes to `dev` and `fix/vendor-ca-trust-refresh`, and
manual dispatch. Real TLS probes are required in CI, never appliance boot hooks.

| Check | Qualification |
| --- | --- |
| 19 Bats cases | Scoped APT refresh, strict partial-index failure, package/refresh failure, successful stale CA/Node no-op, holds, offline checks, non-runnable Node, installer branches, Java gate failures |
| 26 Python Java cases | Real keytool identity checks, generated private CA preservation, encrypted private-entry preservation, stage/write errors, wrong password, locking/races, ACL/xattr preservation, post-rename rollback, FinTS prefix and runtime guards |
| 4 Python hook cases (with subtests) | Success/fatal failure for build, fresh setup and update; normal/quick release branches; JDK/Maven install failures; FinTS custom startup rejection, final check, Maven success/failure and bound JRE environment |
| 6 Node cases | Actual loopback HTTPS with correct, missing, wrong and malformed private CA stores; strict negative/positive verdict handling |
| 16 OpenSSL incident-chain pairs | All real archived chains accepted before and unknown-issuer rejected after scoped remediation, including rollover |
| 32 offline Java checks | All 16 chains accepted before and PKIX rejected after |
| 68 live-mode Java checks | The same 32 offline checks plus 14 negative and 4 positive HTTPS hosts with each store |
| 18 live Node controls | 14 incident hosts certificate-rejected, 4 positive hosts authorized with HTTP 200 |

Syntax and **full-file** ShellCheck run on every changed `.sh` and `.bats` path,
not just the two clean new scripts. Python/Node syntax and Java compilation also
run. The static checker compares all ShellCheck diagnostics to the immutable
pre-PR base `c421693dcb09b00eafacbda6128174d2c658cb06` (`TRUST_TEST_BASE` can select
another baseline). It rejects new code/message/source-text occurrences while
reporting existing legacy diagnostics, rather than excluding entire files or
weakening severity. Current inventory: seven appliance shell scripts, the Bats
file and the suite runner. Bats uses its native parser, then ShellCheck; ordinary
shell scripts receive `bash -n` as well. Only cross-test Bats subshell warnings
SC2030/SC2031 are locally documented as inapplicable. Negative grep assertions
use explicit status checks, so they cannot be ignored inside Bats loops.

The hook tests execute exact extracted hook/installer blocks with inert command
fixtures, not whole disk builds, release preparation or provisioning. The Bats
suite also executes the redirected full setup and Node installer failure paths.
No full image build, full FinTS deployment, reboot, or on-appliance mutation is
claimed. APT update/refresh is not a general OS rollback transaction; the tested
rollback is the Java helper's atomic store transaction. Package-manager side
effects are outside that guarantee.

See [fixture provenance](fixtures/TRUST-FIXTURES.md). Historical Java is used only
in the disposable experiment to prove accepted-before exposure. No verification
bypass, blacklist modification, synthesized incident chain or accepted network
error is permitted. Live endpoints can change/expire; that must fail visibly,
not become a skip or expected certificate rejection. The older audit reports
remain historical evidence rather than current automated-test counts.
