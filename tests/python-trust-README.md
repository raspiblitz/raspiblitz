# Python protection after the eMudhra certificate compromise

The OS trust update does not remove compromised eMudhra trust paths from
Python bundles. BlitzAPI owns its application dependency locks in
[fusion44/blitz_api](https://github.com/fusion44/blitz_api), referenced by
`build_sdcard.sh` and `blitz.web.api.sh`. There is no public
`raspiblitz/blitz_api` repository. The script is `blitz.web.api.sh`, not
`blitz.api.sh`.

## Focused changes

BlitzAPI updates only certifi in `requirements.txt` and `uv.lock`, from
2026.6.17 to 2026.10.19. No other dependency is changed. Older deployed
BlitzAPI releases can receive the same certifi-only package update without
installing the current development branch's unrelated requirements.

RaspiBlitz updates pip independently and checks the resulting vendored
bundle. `blitz.python-trust.sh pip PYTHON [BOOTSTRAP_CA_FILE]` requests
`pip>=26.2.2`. Bootstrap CA-file precedence is the first nonempty value in:

1. `REQUESTS_CA_BUNDLE`;
2. `CURL_CA_BUNDLE` (Requests' fallback when the first is unset/empty);
3. pip's effective install `cert` option (`PIP_CERT` or pip configuration,
   resolved by pip itself);
4. `SSL_CERT_FILE`;
5. the explicit third positional `BOOTSTRAP_CA_FILE` argument;
6. `/etc/ssl/certs/ca-certificates.crt` if that argument is omitted/empty.

The positional argument is a fallback, not a force-override of existing client
policy. Requests environment values take precedence over pip's `--cert` in
actual requests sessions. The helper selects and validates the file before
any pip download, then scopes that same file to `--cert` and Requests/SSL
variables for the bootstrap command only. It does not change the caller's
settings, package constraints, indexes, configuration files, or trust bundles.
All nonempty environment/pip CA-file overrides (including shadowed files) are
checked for affected anchors and parseability before bootstrap and again in
pip/app postconditions: later requirements and application clients can select
them differently. The positional/default file is checked when selected for
bootstrap; it is not an application configuration override. A missing,
affected, malformed, or directory-valued CA-file override fails closed. No scan
of `SSL_CERT_DIR`, lazy OpenSSL CA directories, macOS native trust, or per-request
application overrides is claimed. Refreshed,
reviewed OS trust remains a deployment precondition, even when an explicit
file authenticates bootstrap; this helper does not refresh OS trust itself.
The outer RaspiBlitz sudo boundary matters: preserving policy only inside
JoininBox is too late if its owner invocation has already discarded it.
BlitzAPI helper calls and subsequent pip downloads/requirements resolution,
JoininBox's owner installer and RaspiBlitz posthook, and image helper/pip calls
preserve only the names of exported `PIP_*`, `REQUESTS_CA_BUNDLE`,
`CURL_CA_BUNDLE`, `SSL_CERT_FILE`, and `SSL_CERT_DIR` variables through sudo.
Values are not copied into command arguments or logged. Caller `PATH`, Python
execution variables, and the general environment are not whitelisted. Policy
must already reach the RaspiBlitz script: an operator invoking it via an outer
sudo must explicitly preserve these same policy names there as well. These
hooks cannot recover variables discarded before script entry.

An incompatible pip pin, stale index, unsafe selected/explicit CA file, or
affected post-install bundle stops the operation. Supply a separate reviewed
bootstrap fallback as the third argument, or retain explicit client CA policy
using the precedence above. The rich-toolkit PyPI workaround is per-command:
it sets only `PIP_INDEX_URL` and a whitespace-only `PIP_EXTRA_INDEX_URL` to clear
extra indexes (an empty value is ignored by pip). It retains configured CA and
constraint policy, leaves `/etc/pip.conf` unchanged, and fails on install error.

`--cert` alone does not remove modern pip's already-loaded vendored roots.
The helper inspects pip's accepted deprecated-option choices: modern pip uses
`--use-deprecated=legacy-certs`, while fresh pip 23.0.1 uses its existing
certifi-only mode without an unsupported switch. Old pip with opt-in truststore
is refused. Python below 3.10 is rejected explicitly because the fixed pip
requires Python >=3.10. Normal pip truststore operation resumes after upgrade.

Image creation and data upgrades run `system-pip /usr/bin/python3` before
subsequent Python downloads. This Debian-only mode installs with an exact
`--target=/usr/local/lib/pythonX.Y/dist-packages`, checks the imported pip path
and bundle, and installs generated entrypoints in `/usr/local/bin`. It does not
uninstall distribution pip or use `--prefix=/usr/local`, which Debian's
`posix_local` scheme can expand to `/usr/local/local`. No PEP 668 override is
added. The actual Debian system-mode acceptance is recorded below.

Image bootstrap explicitly refreshes `ca-certificates` through signed APT,
rebuilds the effective bundle, and checks its DER roots offline before either
fetching standalone helper code over HTTPS or invoking the checkout helper.
Index, package, bundle, and root-check failures stop before Python downloads.
Local anchors and package holds/pins are not overridden. Standalone CI builds
need no early `/home/admin/config.scripts` installation.

This is a focused companion to vendor trust PR #5326, not a copy of it.
Combined with #5326, data updates refresh vendor trust immediately after
prechecks, then run the Python helper after the migration preamble comments.
The separate insertion points avoid a merge conflict and guarantee the OS
refresh precedes pip bootstrap. The later image vendor hook still owns Node.js
and the complete vendor-version checks. This Python-only branch does not add
that data-update remediation, so merge/deploy it together with #5326.

BlitzAPI install/update checks its standalone certifi before starting services,
and repairs pip even if the application commit has not changed. Failures leave
services stopped rather than restarting with an affected bundle. The fixed
BlitzAPI dependency lock must be available before using this fail-closed path.
JoinMarket's installer repairs pip on both new and already-installed paths;
its OS-root Twisted runtime does not need an application certifi dependency.
Updates performed directly inside external JoininBox are outside this hook.
At JoininBox HEAD `3115bd91af8b39a40c75009163ef2e1424020e95`,
`scripts/install.joinmarket.sh:248-253` calls JoinMarket's `install.sh` for
update, testPR, and commit installs, then returns without the RaspiBlitz check.
JoinMarket's own installer at `c2dd2534afa59ddcb7f7d9a67e4b57cefcf9e4a4`
(`install.sh:182-199`) upgrades pip and setuptools inside `venv_setup`
before dependency downloads. A post-install JoininBox-only hook is therefore
not enough to secure those downloads. This requires a separate upstream
JoinMarket bootstrap repair plus a postcondition on every JoininBox owner path;
this RaspiBlitz change does not claim persistent protection of direct updates.
Until those upstream changes land, an operator must stop the relevant clients,
review the external installer/bootstrap path, and recheck the resulting venv.
Do not assume a previous successful RaspiBlitz hook survives venv recreation.
The pending JoininBox owner repair covers the old JoinMarket first pip download
and requires Python >=3.10. Deployment still needs a maintainer-signed new
[JoininBox release](https://github.com/openoms/joininbox/releases) containing
that repair, followed by a reviewed `JBTAG` update and the existing signature
verification. `JBTAG=v0.9.0` is deliberately unchanged here: a fork or unsigned
commit is not a substitute for that owner release. Before invoking the copied
owner installer, RaspiBlitz now requires the helper, archived-installer backport,
and installer itself to match their tracked bytes in the already verified tag.
It also requires the reviewed prerequisite/bootstrap/backport hook lines in the
actual copied installer. Missing files, stale untracked helpers surviving
`git reset --hard`, a legacy installer, or copied-file mismatches fail with an
explicit maintained-signed-release requirement before owner invocation.
Consequently the unchanged old pin is intentionally refused for new installs;
policy forwarding or a late posthook cannot make it safe. This gate does not
repair or intercept independent JoininBox self-updates.

## Verified release artifacts

The PyPI release JSON and downloaded wheel SHA-256 values were checked directly:

* [certifi 2026.10.19](https://pypi.org/pypi/certifi/2026.10.19/json), Python >=3.7,
  wheel SHA-256 `42d35340cc5b9ba78e818ddbff0c5b1c2b779de448a340fd1b989f5fa8670e1b`.
* [pip 26.2.2](https://pypi.org/pypi/pip/26.2.2/json), Python >=3.10,
  wheel SHA-256 `fd7f4dfa8190e014013b9f08f3e973f4e4c26ffd179a204895533a7254813a70`.
  Its wheel's `pip/_vendor/vendor.txt` explicitly lists certifi 2026.10.19.
  This is a verified fixed release, not a claim that every earlier pip release
  is affected or that installing standalone certifi fixes pip.

Both wheels omit these affected root DER SHA-256 fingerprints:

* `86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b`
* `d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4`

## Local regression evidence

The local macOS CPython 3.12 test venv used the node's requests 2.32.5 and httpx
0.28.1 versions, with actual adapter/transport defaults and pip's real
`_create_truststore_ssl_context`. Before remediation, certifi 2025.4.26 and
pip 26.0.1 each accepted 8 of the 16 unique published incident chains offline.
Updating standalone certifi alone reduced requests/httpx to zero accepted
chains while pip still accepted eight. Updating pip separately reduced all
three consumers to zero. Rejections were issuer-validation failures, with
OpenSSL 3's default CA path/store disabled.

The fixed requests, httpx, and actual pip session each rejected all 14 public
incident hosts with certificate-validation errors and accepted a verified
TLS positive control at pypi.org. The two rollover fixtures have no live hosts
and were verified offline only. Explicit roots from pip's underlying context
were exported for offline tests; native OS trust is not fully enumerable on
all platforms. Live pip probes exercised the full native-plus-vendor context.

The actual bootstrap upgraded pip 26.0.1 to 26.2.2 while standalone certifi
remained unchanged. An incompatible `pip==26.0.1` constraint failed rather
than being overridden. An affected bootstrap bundle was refused. An extra
local anchor in a reviewed bootstrap bundle remained byte-for-byte unchanged
across the real bootstrap. This checks bundle preservation, not a custom-CA
server handshake. Shell syntax checks passed. BlitzAPI's frozen lock installed
successfully; its three standalone client-root tests and Ruff checks passed.

These isolated development tests did not change production. A subsequent
Debian 12 / RaspiBlitz 1.12.1 node test installed checksum-verified pip 26.2.2
in both affected venvs and certifi 2026.10.23 in BlitzAPI, using local wheels
with --no-index --no-deps. Dependency checks passed before and after.
BlitzAPI's real requests, httpx, and default pip sessions passed 54 live
controls; JoinMarket's pip passed 18. Each client rejected 14 incident hosts
and accepted four normal HTTPS controls. BlitzAPI and both Celery services
were restarted, all main PIDs changed, and the API documentation returned
HTTP 200. Existing API configuration was preserved byte-for-byte. The
installer source hooks themselves were not used for that maintenance.
The OS/Node and Bitcoin Core/LND changes are separate.

## Automated bootstrap regressions

```sh
python3.11 -m unittest discover -s tests -p 'test_python_trust_bootstrap.py' -v
```

This suite downloads real pip 23.0.1, 26.0.1, and 26.2.2 wheels over HTTPS,
then runs isolated upgrades, including two actual HTTPS helper bootstraps.
It covers incompatible constraints, a stale local index, affected bootstrap
roots, opt-in old truststore, an unchanged affected postcondition, unsupported
Python, isolated target installation/entrypoints, and update-code restart
branches with external commands stubbed. All original 18 tests remain; two
additional tests exercise all 15 outer policy invocations with an env-reset sudo
model, including values containing whitespace/newlines, all CA settings, and
exclusion of unrelated execution variables. The production update block also
runs real pip with incompatible helper and later requirements constraints;
both failures leave services stopped. It never starts a real service.
All 21 existing tests, including the per-command rich-toolkit configuration and
failure gate regression, remain. Four new regressions bring the suite to
25 tests. Three cover CA files: real private-CA HTTPS wheel upgrades exercise six selection paths on
both pip 23 and 26 (12 successful HTTPS bootstraps), paired with a wrong-fallback
certificate-validation failure; affected/malformed/missing explicit files are
refused before any HTTP request, including shadowed lower-priority files; and
both app and pip postconditions reject affected/broken overrides. The pip
postcondition fixture mutates an initially clean override at the install
boundary, so a precheck alone cannot pass it. HTTPS fixtures use the standard
library and existing `openssl`, with no added package dependencies. The fourth
executes the actual owner release gate with real temporary Git refs/copies and
eight synthetic cases: old release, untracked leftover helpers, an untracked
new installer, missing hooks, commented-out hooks, tampered copies, missing
copies, and a matching reviewed-hook fixture. Only the last reaches the
simulated owner invocation. This tests gate ordering and release linkage, not
upstream signature verification or a full JoinMarket native build.
Debian scheme selection in the automated suite uses platform/path fixtures.
Separately, all four helper modes were executed successfully on the Debian 12
node: system pip, BlitzAPI pip, BlitzAPI application certifi, and JoinMarket pip.
Hashes of all 491 distribution-managed pip source files remained unchanged.
The repaired system interpreter and `/usr/local/bin/pip3` selected pip 26.2.2
from the intended local package directory. Existing global dependency
diagnostics remained unchanged, not clean. This verifies the helper itself,
not full image or provisioning execution. Run the fresh-pip regression suite
with Python 3.10/3.11 because pip 23.0.1 predates Python 3.12.

## CI-enforced review regressions

`.github/workflows/python-trust.yml` runs on pushes to
`fix/independent-python-ca-trust`, pull requests, and manual dispatch. Its
Python 3.10/3.11 jobs run all 32 bootstrap and shell tests, check syntax for
all five changed shell scripts, and retain test logs even on failure.
A separate Debian 12 container job runs the system-pip test without network,
host mounts, or Linux capabilities. Building that fixture requires signed APT
repositories and HTTPS access to PyPI; it does not disable repository validation.

```sh
python3.11 -m unittest discover -s tests -p 'test_python_trust_*.py' -v
docker build -f tests/python-trust.Dockerfile -t python-trust-system .
docker run --rm --network=none --cap-drop=ALL --security-opt=no-new-privileges python-trust-system
```

The matrix extends the existing 25 tests rather than duplicating them:

| Review requirement | Executable assertions |
| --- | --- |
| Missing/old pip | `test_missing_pip_fails_before_download` refuses an unseeded venv; fresh pip 23 and modern pip 26 upgrades use real wheels and HTTPS; old opt-in truststore and unsupported Python fail closed. |
| CA/environment policy | `test_https_explicit_ca_precedence` authenticates a private HTTPS server through all six selection paths on pip 23/26, including empty environment fallbacks. Unsafe-CA tests reject affected, malformed, missing and directory-valued overrides before invoking pip, including shadowed files. Postchecks mutate a clean override at the install boundary. Outer-boundary tests enforce the exact whitelist on all 15 invocations. |
| Compromised roots | Real affected pip and standalone certifi wheel bundles fail the production checks; fixed bundles pass. Standalone certifi fixtures use standalone wheels, not vendored modules with pip-bound resource lookups. |
| Download failure | `test_download_transport_failure` reaches a real refused local connection; stale-index and constraint tests fail real dependency resolution. Image tests inject helper-fetch, temporary-file, signed-index, package, bundle, root-check and helper failures on checkout/standalone paths, checking cleanup and download ordering. |
| Unchanged API commit | `test_update_paths` still requires pip repair and app verification, skips requirements only on an unchanged commit, and checks the three-service start order. |
| Dependency failure | `test_api_install_dependency_and_trust_gates` executes install gates for pip, Cython, rich-toolkit, requirements and app checks. `test_outer_update_constraints_stop_restart` uses real pip conflicts through the production update block. |
| JoinMarket release binding | Existing release-gate tests use real Git tags and copied files across eight legacy/tampered/missing/reviewed fixtures. `test_joinmarket_existing_and_new_posthook` checks existing and new install branches, owner failure and posthook failure. |
| Service fail-closed behavior | Update tests refuse restart after missing remote branches, pip/app/dependency failure, fetch/reset failure or failed commit readback. Failed stops abort before mutation; failed starts report failure. New regression cases exposed missing status checks and a nonfatal Cython error, which now abort. |
| System/provisioning | `python-trust-system.py` runs the unchanged helper twice against Debian's real system Python and pip, verifies three generated entrypoints, and hashes distribution pip files plus the PEP 668 marker before/after. The actual data-upgrade hook propagates failures and retains its log redirection. |

These are executable branch contracts, not a claim of 100% changed-line or
whole-installer branch coverage. Install/update tests execute source blocks with
inert external-command fixtures. They do not execute full image builds, signature
verification, JoinMarket native compilation, or live systemd repair. Successful
source tests do not establish deployment acceptance. `SSL_CERT_DIR`, native
stores, and per-request overrides remain outside the helper's file checks.
The signed JoininBox release and companion OS trust refresh remain deployment
prerequisites; CI does not bypass either gate. Repository administrators must
select this workflow as a required check if they want merge protection.

## Reproduce

Download the public chain archive linked from
<https://emudhra.we-have-a-problem.com/> and use its `chains` directory.
Run these in an isolated venv, not on a production service:

```sh
python tests/python-trust-regression.py --chains "$CHAINS" \
  --openssl "$OPENSSL3" --expect affected --output before.json
# Upgrade only standalone certifi, leaving pip 26.0.1:
python tests/python-trust-regression.py --chains "$CHAINS" \
  --openssl "$OPENSSL3" --expect clean --pip-expect affected --output certifi-only.json
# Upgrade pip independently, then:
python tests/python-trust-regression.py --chains "$CHAINS" \
  --openssl "$OPENSSL3" --expect clean --live --output after.json
```

The test disables client environment/proxy overrides deliberately to exercise
vendor defaults. Explicit production consumer overrides must be audited
separately. The helper preserves those configuration files and local anchors;
it does not try to override an operator's request-level CA selection.

## Proposed maintenance commands and rollback

Only the operator should run these, after verifying the OS bundle is fixed.
`OWNER`, `VENV`, `BACKUP`, and `SCRIPTS` are explicitly selected service paths,
with a different backup directory for each venv. Stop all three BlitzAPI
services for its maintenance; JoinMarket runtime changes are not needed.

```sh
# Save each venv at its original absolute installation path for rollback.
sudo -u "$OWNER" cp -a "$VENV" "$BACKUP"
sudo -u "$OWNER" "$SCRIPTS/blitz.python-trust.sh" pip "$VENV/bin/python"
# BlitzAPI only; do not install unrelated current-dev requirements:
sudo -u "$OWNER" "$VENV/bin/python" -m pip install --no-deps 'certifi==2026.10.19'
sudo -u "$OWNER" "$SCRIPTS/blitz.python-trust.sh" app "$VENV/bin/python"
```

Run the pip helper separately for the BlitzAPI venv and JoinMarket jmvenv.
Do not install certifi/requests/httpx into JoinMarket just for remediation.
The dependency scope is pip alone in each venv, plus certifi alone in BlitzAPI.
Keep explicit constraints in force; resolve an incompatible pin through its
owner rather than using `--ignore-installed` or removing constraints.

After package checks and targeted service tests, restart BlitzAPI, its Celery
worker, and Celery beat, then verify their loaded versions and TLS behavior.
For rollback, stop affected services, retain the failed venv separately, and
restore the saved directory to the exact original absolute path so existing
entry-point shebangs remain correct. The snapshot contains affected trust:
do not resume unrestricted networking with it. Prefer correcting the failed
package constraint or maintaining an explicitly reviewed system-only client
configuration while rolling forward. Source rollback alone does not undo
installed venv packages.

## Final helper acceptance on Debian

The final helper was executed again on the actual Debian Raspberry Pi, using a
new disposable venv seeded with distro pip 23.0.1. It upgraded to pip 26.2.2,
and all 18 live pip TLS controls passed. The final `app` postcondition also
passed as the installed BlitzAPI user against its actual venv. Production
packages and services were not changed during this acceptance run. This is
helper acceptance, not a full installer, image-build, or reboot test.

Both merge orders with the reviewed OS/Node/Java trust patch passed 25 Python
regressions and 17 vendor Bats checks, producing the same combined tree.
JoininBox's owner repair is published separately in
[openoms/joininbox#203](https://github.com/openoms/joininbox/pull/203); a maintained
signed release containing it is still required before updating `JBTAG`.

## Suggested public summaries

RaspiBlitz title: **Fix Python SSL trust after the eMudhra certificate compromise**

Python environments can continue trusting certificates affected by the eMudhra
compromise even after RaspiBlitz's system certificates are updated. This updates
pip's separate certificate bundle, checks BlitzAPI's application bundle before
restarting its services, and covers JoinMarket's installer without changing its
runtime dependencies. Isolated pip 23/26 bootstrap regressions and public TLS
controls passed. Manual node maintenance also passed client TLS and service
restart checks; the revised installer hooks still require node acceptance.
Direct JoininBox updates need a separate upstream bootstrap fix.

BlitzAPI title: **Stop trusting compromised eMudhra certificates in Python clients**

BlitzAPI's pinned certificate bundle can still trust certificates affected by
the eMudhra compromise even after the node's system certificates are updated.
This updates only certifi in the existing dependency locks so requests and
httpx reject those chains while valid HTTPS continues working. Pip has its own
certificate bundle and needs the separate RaspiBlitz installer update.
