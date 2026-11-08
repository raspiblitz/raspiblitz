# Trust refresh and October 2026 eMudhra audit

Current automated coverage and Docker commands are in [TRUST-CI.md](TRUST-CI.md).
The verification counts and opt-in instructions below describe the original
October 29 audit; CI now requires the archived-chain and live TLS controls too.

## Finding and focused fix

Chrome's CRLSet and root-store changes do not update Debian's trust store.
Debian's fix is ca-certificates `20250419~deb12u2` for Bookworm and
`20250419+deb13u1` for Trixie. Debian removes both emSign ECC Root CA - G3
and AAA Certificate Services. Removing only the first leaves the Sectigo
cross-signed route available in old Debian bundles.

Node uses a separate bundled store by default. Node 22.23.4 updates the
roots and blocks compromised public keys. Node 22.23.2 accepted the real
DV G3B and no-CT test hosts in this audit. Node 22.23.4 rejected all 14
real TLS test hosts with CERT_REVOKED. Both accepted all four positive
controls with authorized TLS and HTTP 200.

`blitz.trust.sh update` refreshes APT indexes, updates only ca-certificates
and the installed nodejs package, and regenerates the Debian bundle and
hashed directory using the vendor tool. When ca-certificates-java is installed,
it upgrades that package and performs identity-specific Java incident-anchor
removal/checks because Debian's OS refresh does not propagate removals reliably.
See [the focused Java audit](JAVA-TRUST-AUDIT.md) for custom-entry preservation,
private-key limits, real JSSE evidence, and the deliberately narrower Debian
policy compared with OpenJDK's standalone-runtime workaround.
It does not install Node on a
minimal image. It does not edit user CA lists, local CA files, environment
variables, service configuration, or application settings. It uses the
already configured package repositories and respects their pins and holds.
It is called during image build after scripts are copied, normal release
preparation, and fresh-setup/data-update provisioning before services start.
The Node installer checks both existing-major and newly installed paths, so
later fatpack installation cannot bypass the earlier image gate.
Release preparation with `-quick` intentionally still skips OS updates.
Code-only sync is not a trust refresh. Run the helper explicitly for that path.

`blitz.trust.sh check` is an offline, read-only postcondition reused after
updates and by the Node installer, without recursive installer calls. It
requires installed ca-certificates at the reviewed Debian 12/13 minimum
above and, when Node is installed or on PATH, a runnable stable Node version
at least 22.23.4, 24.22.1, or 26.12.1 on its corresponding supported major.
These versions are listed by the official October 21 Node security advisory.
Unknown OS/Node lines fail closed pending policy review. The CA check assumes
official Debian package contents; it is not an effective-store scan or a
universal compromise detector. It does not certify modified bundles.

Installed Node detection uses dpkg db:Status-Status, independent of hold
selection. A stale mirror, missing security repository, or pin cannot turn
a successful stale no-op into success. Holds/pins are not overridden; an
APT refusal or failing version check stops the caller with a diagnostic.
NodeSource must actually offer the fixed package on the configured major.
No negative TLS probes or other network checks run in the offline command
or normal boot. Perform independent negative controls at deployment.
Package maintainer scripts may have their own effects. Consumers that
cache roots or an old runtime need restart or the normal upgrade reboot.

## Consumer audit and boundaries

| Consumer | Source finding | Coverage and limitation |
| --- | --- | --- |
| Debian image | build_sdcard.sh adds bookworm-security and performs an OS upgrade | New explicit refresh fails on partial APT update errors and package or refresh failure. Earlier build downloads still depend on the base image's existing trust. |
| Provision/update | _provision.update.sh previously had no generic CA refresh | Fresh setup and update both gate before blockchain and Lightning services start. It is not a recurring background updater. |
| Release | blitz.release.sh performs security upgrades unless -quick | Normal release now refreshes trust explicitly and fails if it cannot. Quick releases require independent verification. |
| curl and wget | No repository-wide alternate CA configuration found | Normal Debian OpenSSL consumers use the updated OS store. Explicit bundles, proxy trust, cached state, and bypass flags are outside this guarantee. |
| Python requests | Two subscription scripts create ordinary requests sessions. Image build installs pip requests and many apps create venvs | Debian certifi points to the OS bundle on the inspected node, according to supplied read-only evidence. Pip certifi and venv bundles can be independent and are not rewritten. Update each owning environment with a fixed certifi version, currently 2026.10.19, after dependency review. |
| Node | bonus.nodejs.sh selects NodeSource major 22 | Existing-major and new-install paths must pass the offline check, attempting the scoped package refresh on failure. Does not set NODE_EXTRA_CA_CERTS, which adds trust rather than replacing bundled roots. Does not override explicit app ca or service options. |
| Go | bonus.go.sh pins Go 1.19.5. Many applications are downloaded binaries rather than built here | Standard Linux Go system-root consumers benefit after restart. Custom/fallback/embedded pools, GODEBUG overrides, and independently built binaries need separate validation and potentially rebuilt runtimes. Updating the toolchain alone does not update existing executables. |
| Downloaded applications and containers | Install scripts retrieve external applications | Their source and transitive dependency bundles are not fully vendored here. No claim that all installed application TLS consumers are fixed. |

### TLS bypasses found, intentionally not changed here

- lnd.install.sh, lnd.update.sh, bonus.chantools.sh, and bonus.pool.sh
  use wget --no-check-certificate for PGP public-key downloads. Pinned
  fingerprint and manifest-signature checks exist, but require their own
  fail-closed review. This bypass is not repaired by a CA update.
- bonus.sphinxrelay.sh bypasses certificate verification on its configured
  publicURL readiness check. This is separate from normal verified downloads.
- alternative.platforms/amd64/packer/scripts/init.sh bypasses verification
  while downloading a Vagrant authorized public key. The fixture-image
  workflow also disables daily unattended APT updates.
- 00infoBlitz.sh and bonus.lnbits.sh use curl -k for loopback self-signed
  application calls. bonus.lnproxy.sh documents local self-signed calls.
- cl.hsmtool.sh uses --insecure as an application argument, not curl TLS.
- No direct Python verify=False, Node rejectUnauthorized=false or
  NODE_TLS_REJECT_UNAUTHORIZED=0, or Go InsecureSkipVerify was found in the
  checked repository. External fetched applications are not included in
  that negative finding.

## Exact identities

The compromised objects are eight P-384 intermediate keys, represented by
16 certificates including Sectigo cross-signs. Roots below are trust paths,
not a claim that their own private keys were compromised.

| Root identity | DER SHA-256 |
| --- | --- |
| emSign ECC Root CA - G3 | `86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B` |
| AAA Certificate Services, Debian Comodo_AAA_Services_root.crt | `D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4` |
| emSign Root TLS CA - G3, self-signed direct issuer | `7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D` |
| emSign Root CS CA - G3, self-signed direct issuer | `F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5` |

The TLS G3 root cross-signed by ECC G3 is a separate certificate,
`3094025792039A68AF6E553686410BDAB7C0D4A36B9084CBA64202E35D6EBBDD`.
Do not confuse the direct TLS issuer with the older ECC trust anchor.
No blanket removal of eMudhra names or unrelated G1/G2 roots is implemented.
The Debian vendor package owns removal policy, including collateral trust
changes for legitimate certificates chaining to the removed anchors.

All intermediate fingerprints below match Mozilla bug 2083449's public
inventory. The downloaded inventory PEMs were independently DER-hashed
and all 16 matched their declared SHA-256.

| Intermediate | Issuer route | DER SHA-256 |
| --- | --- | --- |
| EM DV TLS CA - G3B | eMudhra | `42C4ACCD12C4F59597925E1A08A7A90102608543809308D50EC427E118BA1493` |
| EM DV TLS CA - G3B | AAA | `45A883F349AEDFD5F3A649B5498FFB121712BA8B448F3F2A91DBC5A766FCDDBE` |
| EM OV TLS CA - G3B | eMudhra | `98B896625C0C230ADEEC3EB2CF6AAD5001ECF9156A68644E82374CE5833BC25B` |
| EM OV TLS CA - G3B | AAA | `5F1DED4DD590AF74631290CF073B122A2AAC6A1FA479778A0BD43579BD832699` |
| EM EV TLS CA - G3B | eMudhra | `E7568FE6E12331F4FD7DE61DA4C7559D0F8EB192A218D4741A3BA75184333838` |
| EM EV TLS CA - G3B | AAA | `579480AEA166290BD3C643589E795FC0D0E54E86505D180F1DFF99EFD3199512` |
| EM DV TLS CA - G3C | eMudhra | `0164D7CEAE5BB909C272AF151FF44B1177AE9B47D9424B94F1D9558C30934D19` |
| EM DV TLS CA - G3C | AAA | `62B7F9868263F72F6911FC78CEAF72C1979158B7368BF648683BB2AA39B02E72` |
| EM OV TLS CA - G3C | eMudhra | `CB6E15165AC802E9B3F993F16C25D41F4E81C21EBDE71AE1B012AC00BF9C7C3F` |
| EM OV TLS CA - G3C | AAA | `7485B51C0ED192878FA1D2F948FB529AE1842CC5086C4B67F7BE5B2039DE9489` |
| EM EV TLS CA - G3C | eMudhra | `432EC25F0D28DE9006D97BF752F17BBB2CD41F669933FCB072D9A1148D0261F3` |
| EM EV TLS CA - G3C | AAA | `FD9D5C2DBBD4995AB69B8D50C439D9527B00529199C2FD01B2174EB58F07021F` |
| EM OV CS CA - G3B | eMudhra | `9E39DE2881273ACC225A149C72BA3E0F51424963669AB633EE1DC7DF5DB067B4` |
| EM OV CS CA - G3B | AAA | `A496E23AC0CAB8155FC9B117B97EAE368EFCBB9041AEC8804D5A308D2D01C2D8` |
| EM OV CS CA - G3C | eMudhra | `4B2460A466F95FD40113BCDCCA2CEB29B3B093921DE45474DA7DF48874C630B1` |
| EM OV CS CA - G3C | AAA | `84112972B8E59D14560AE7E7119654474AAD119990CF3722BFC1E3B91615E1FD` |

## Verification

- `bats test/blitz.trust.bats`: 14 passing mocked shell control-flow tests,
  using real dpkg version comparisons. Includes held Node, successful stale
  no-ops, missing/unreviewed CA fixes, supported Node boundaries, executable
  overrides, and execution of scratch-redirected setup and Node installer gates.
  These prove scoped arguments and stop-on-failure behavior, not actual
  Linux package installation or certificate preservation under dpkg.
- ShellCheck passes for blitz.trust.sh and bonus.nodejs.sh. Bash syntax
  checks pass for both and _provision.setup.sh; git diff --check passes.
- Actual Debian update-ca-certificates utility, redirected entirely to scratch
  directories on the development host: two --fresh runs preserved a generated
  custom local CA, the explicit ISRG Root X1 distrust setting, and byte-identical
  configuration. Both runs returned zero and produced identical bundles.
  This is vendor-tool execution, not a Linux package installation test.
- Offline OpenSSL 3 verification against roots extracted from actual Debian
  packages: all 16 real incident chains accepted before, all rejected with
  unknown issuer after. Includes 12 ordinary TLS paths, two no-CT paths,
  and two self-issued key-rollover cases. No system fallback store used.
- `node test/trust_tls_probe.js` using downloaded Node 22.23.4: all 14
  negative controls rejected with CERT_REVOKED and all four positive
  controls returned authorized TLS with HTTP 200.
- curl with the extracted new Debian bundle verified bitcoincore.org,
  api.github.com, registry.npmjs.org, and pypi.org with HTTP 200 and verify 0.
- The Node tarball was checked against its upstream SHASUMS256.txt.
  This audit did not independently validate the checksum file's signature.
- Separate actual Debian node acceptance, supplied and retained in the local
  audit evidence directory `evidence-20261029/node`: the original helper
  successfully installed ca-certificates 20250419~deb12u2 and Node 22.23.4
  through APT. All 16 archived chains accepted against before.pem and
  issuer-rejected against after.pem. Installed Node 22.23.4 rejected all 14
  live incident hosts with CERT_REVOKED and accepted four positive controls
  with HTTP 200. Python ssl, effective inspected requests, curl, and wget
  passed 72/72 live checks across the same controls. This does not certify
  all Python virtual environments or application overrides.
- The old node executable 22.23.1 was extracted from the cached rollback
  .deb without installing or downgrading: seven incident endpoints were
  authorized, seven AAA endpoints already issuer-rejected, and four positives
  passed. Do not conflate this with the downloaded 22.23.2 baseline above.
- On the actual node there were no custom local anchors or explicit local
  distrust selections. Vendor ca-certificates.conf selections changed as
  expected (15 removed, 21 added), not byte-identically. The scratch fixture
  preservation test above is the custom-anchor/distrust evidence, not proof
  of preservation under actual dpkg maintainer scripts. Rollback is cached.
- This repair was tested locally only, not installed on that node. No full
  image build, repair deployment, or post-reboot consumer acceptance was run.
- GitHub searches for eMudhra, emSign, ca-certificates, and CA distrust found
  no matching existing PR. Broader certificate-trust issues were unrelated.
  No Core/LND version changes are included.

The CI workflow runs the mocked tests and ShellCheck. Real incident tests
are opt-in, require downloaded fixtures, and are not silently substituted
with synthetic chains. Download chains.zip from the source below, inspect
its contents, and extract into a scratch directory. Create before.pem and
after.pem by concatenating the Mozilla .crt files from the before and fixed
Debian packages, respectively. Then run with OpenSSL 3:

```sh
python3 test/trust_store_regression.py --before before.pem --after after.pem --chains chains
node test/trust_tls_probe.js
```

Test hosts can expire or change. A network failure is not an accepted
negative result. Recheck current fixtures and policy for later releases.
Preserve custom local anchors in before/after deployment checks, and
exercise both default Python SSL and effective requests/certifi trust.

## Sources

- [Google incident policy](https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/).
- [Mozilla incident 2083449, identities and cross-signs](https://bugzilla.mozilla.org/show_bug.cgi?id=2083449).
- [Debian Bookworm DLA-4845-1](https://www.debian.org/lts/security/2026/dla-4845).
- [Debian Trixie DSA-6572-1](https://www.debian.org/security/2026/dsa-6572).
- [Debian source-package security status](https://security-tracker.debian.org/tracker/source-package/ca-certificates).
- [Official Node October 2026 security advisory, supported lines and fixed versions](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases).
- [Node 22.23.4 upstream changelog](https://github.com/nodejs/node/blob/v22.23.4/doc/changelogs/CHANGELOG_V22.md).
- [Incident test service and remediation inventory](https://emudhra.we-have-a-problem.com/), [root inventory](https://emudhra.we-have-a-problem.com/roots.json), [intermediate inventory](https://emudhra.we-have-a-problem.com/impacted-intermediates.json), and [real chain fixtures](https://emudhra.we-have-a-problem.com/chains.zip).
- [Go x509 SystemCertPool and Verify documentation](https://pkg.go.dev/crypto/x509).
