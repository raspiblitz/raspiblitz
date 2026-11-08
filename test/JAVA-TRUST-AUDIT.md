# Debian Java trust propagation, October 29, 2026

## Finding and ownership

Read-only inspection of the RaspiBlitz node found `ca-certificates-java`
`20230710~deb12u1`, OpenJDK `17.0.19+10-1~deb12u2`, and 163 public trusted
entries in `/etc/ssl/certs/java/cacerts`. Both incident root fingerprints in
`blitz.trust.java.py` remained. The selected Java executable resolves to
`/usr/lib/jvm/java-17-openjdk-arm64/bin/java`; its `lib/security/cacerts`
resolves to that Debian Java store. No adjacent `jssecacerts`, Java process,
or active `fints.service` was found. This does not rule out application
trust-manager overrides, dormant apps, other installations, or containers.

The source-supported Java application is LN-FinTS: `bonus.fints.sh` installs
`default-jdk` and Maven, builds the JAR, and runs `java -jar` in its unit.
Maven itself is another Java TLS consumer. A repository search found no
other direct JRE/JDK/JAR installation or execution in the checked source.
This is not a transitive dependency audit of downloaded applications.

The gap belongs to Debian, not the RaspiBlitz application:

* `ca-certificates.postinst` initially runs `update-ca-certificates` without
  hooks, then schedules a second run. The second run can receive no delta.
* Installed `update-ca-certificates --fresh` deletes old symlinks without
  recording their removals, re-adds current roots, and invokes hooks with
  **no `--fresh` argument**.
* `jks-keystore` only requests `update-ca-certificates-java-fresh` when it
  receives `--fresh`/`-f`; otherwise it records ordinary additions/removals.
  The Java package's reconciliation path therefore does not run here.
* The dedicated Java fresh trigger does reconcile stale `debian:` aliases.
  It preserves non-`debian:` imports and directory-backed local anchors,
  but removes any absent `debian:` alias, including direct custom imports.
  It does not check whether a removed alias is a private-key entry.

[Debian #1069251](https://bugs.debian.org/1069251) already tracks propagation;
[#767272](https://bugs.debian.org/767272) and [#922981](https://bugs.debian.org/922981)
explain the intended fresh behavior. [OpenJDK's current advisory](https://openjdk.org/emudhra)
explicitly confirms the Debian bug and links [#1142266](https://bugs.debian.org/1142266).
Its remove-and-recreate workaround loses Java-only imports and is not used
here. No duplicate public Debian issue or PR was created. RaspiBlitz Java
PR/issue searches found no matching fix; existing PR #5326 handles OS/Node
trust but did not cover Java. This patch is a local follow-up to its inspected
head `fe3148debf854ddce908c52af28f3525cd64d16c`.

## Focused policy and preservation

The helper deliberately follows **Debian's two-anchor incident policy**:
emSign ECC G3 and AAA Certificate Services, identified by DER SHA-256, not
subjects or aliases. It deletes every trusted entry with either exact
identity, including renamed duplicates, but no other entry. It never adds
anchors, so existing absent/distrusted certificates stay absent. Locally
trusted instances of these two identities are intentionally distrusted too.
Legitimate chains using them can stop working, as with Debian's policy.

The helper uses `keytool -list -rfc` public output with English JVM output.
All keytool operations, including inventory reads, operate on a protected staged
JKS, never the live store. Entry counts, types, exact DER hashes, surviving
public inventories, and the raw encrypted JKS private-entry records are checked.
JKS aliases containing controls or multiline text are rejected from the binary
container as well as the text listing. Incident certificates in a private-key
entry require manual review. No `getKey`, private-key decryption, or key export
operation is used. A disposable synthetic key with a distinct key password
proves unchanged encrypted private-entry bytes; user keys are never tested.

Only JKS is supported. Custom passwords and other container formats fail closed
and require separate administrator review. `changeit` is the public default,
not a discovered secret. Whole-store snapshot/staging is **opaque encrypted
container preservation**, not private-key export. Production runs require sudo:
root-owned mode-0700 same-filesystem work directories contain mode-0600 originals.
See [transaction and lifecycle contract](JAVA-TRUST-TRANSACTION.md) for commit,
rollback, interrupted cleanup, and the external-writer quiescence requirement.

`blitz.trust.sh` upgrades installed `ca-certificates-java` without installing
Java on minimal nodes, then performs this scoped update/check. The normal OS
refresh remains vendor-managed. Other stale Java roots are deliberately not
removed. The fresh Debian algorithm is not used automatically because it
cannot unconditionally preserve direct custom `debian:` imports.

**Coverage limit:** OpenJDK's standalone-runtime workaround additionally
removes emSign G1 and G2. Its CheckCerts program labels these as other eMudhra
roots, not related to the compromised intermediates. This patch does not
silently broaden Debian's policy to those roots or claim to satisfy that
four-root checker. JSSE overrides, custom trust managers, directly trusted
compromised intermediates, and independent runtime stores need separate review.

APT currently offers node OpenJDK `17.0.21+9-1~deb12u1`, but upgrading a Java
package is not evidence of synchronized `cacerts` or the later upstream
JDK-8395690/CVE-2026-114820 root-removal fix. Do not rely on intermediate
certificate blocklisting alone, especially for key-rollover paths.

## Verification actually performed

* Exported only the node's `keytool -list -rfc` public certificate output.
  Built isolated JKS stores from its 163 public certificates, not a copy of
  the live keystore. Scoped remediation removed 2 and preserved 161 entries.
* Temurin JRE `17.0.19+10`, downloaded from Adoptium and verified against API
  SHA-256 `cef790b404cf168fd1a8a7abc5054fbb442c7d4bfe390cceccfe3f64b9b776a9`:
  **68/68** real controls passed. All 16 archived incident chains accepted
  before and PKIX-rejected after, including both rollover fixtures. All 14
  served incident hosts returned verified HTTP 200 before and certificate
  validation errors after. Four positive HTTPS hosts returned verified HTTP
  200 with both stores. No fallback/default root store or verification bypass.
* That initial phase used a macOS Temurin runtime with the node's public
  anchors, not Debian TLS execution. Subsequent native Debian transaction,
  POSIX ACL/xattr, and JSSE acceptance is recorded in
  `JAVA-TRUST-TRANSACTION.md`.
* A first run using Homebrew `17.0.21.0.3` could not establish accepted-before
  baselines because it already rejects compromised intermediates. Retained
  failed-baseline results separately; did not mislabel them as removal proof.
  The node's static `blocked.certs` had none of the 12 intermediate identities
  present in the TLS fixture chains; the newer Homebrew file had all 12.
* **8/8** Python tests passed, including real keytool custom aliases,
  directory-independent `debian:` import, lookalike alias with safe identity,
  wrong password, idempotence, unchanged surviving inventories, and mocked
  malformed/private-entry/concurrent-write guards.
* **15/15** Bats control-flow tests passed, including Java update/check failure
  propagation. ShellCheck, bash syntax, Java compilation, and diff whitespace
  checks passed. Live network probes are opt-in, not boot-time checks.
* Executed the actual Debian Java fresh maintainer script and Java updater in
  an isolated scratch sandbox. Redirected paths, explicit `-cacerts` access,
  and the Linux `/proc` preflight only. Confirmed removal of a stale incident,
  preservation of directory-backed custom anchors/non-Debian imports, and
  **deletion of a direct custom `debian:` import**. This is not dpkg installation
  or live-node mutation. The vendor source retained its license in scratch.
* No node writes, service restarts, private-key reads/exports, public pushes,
  issues, or PR creation were performed in this task.

Reproduce the opt-in checks with `JAVA_TRUST_PUBLIC_LISTING=public-list.txt`
and a real JRE `keytool` on PATH:

```sh
python3 -m unittest discover -s test -p test_java_trust.py -v
javac -d "$SCRATCH/classes" test/JavaTrustProbe.java
java -cp "$SCRATCH/classes" JavaTrustProbe build public-anchors.pem "$SCRATCH/before.jks"
cp "$SCRATCH/before.jks" "$SCRATCH/after.jks"
python3 home.admin/config.scripts/blitz.trust.java.py update --keystore "$SCRATCH/after.jks"
python3 test/java_trust_regression.py --java "$REVIEWED_JRE/bin/java" \
  --classes "$SCRATCH/classes" --before "$SCRATCH/before.jks" \
  --after "$SCRATCH/after.jks" --chains "$CHAINS" --output "$SCRATCH/results.json"
```

## Reference node remediation procedure

First install the reviewed helper in `/home/admin/config.scripts` through the
normal reviewed code deployment. Confirm the exact effective Java path and
public inventory again, no active Java services, no custom store password,
and no concurrent maintenance. Do not copy the whole live store: it could
contain private keys. For this inspected node's two exact aliases, preserve
only public certificates for rollback in a root-only directory:

```sh
sudo install -d -m 700 /root/java-ca-public-rollback-20261029
sudo keytool -exportcert -rfc -keystore /etc/ssl/certs/java/cacerts \
  -storepass changeit -alias 'debian:emsign_ecc_root_ca_-_g3.pem' \
  | sudo tee /root/java-ca-public-rollback-20261029/ecc-g3.pem >/dev/null
sudo keytool -exportcert -rfc -keystore /etc/ssl/certs/java/cacerts \
  -storepass changeit -alias 'debian:comodo_aaa_services_root.pem' \
  | sudo tee /root/java-ca-public-rollback-20261029/aaa.pem >/dev/null
```

Run the exports from a shell with `set -o pipefail`, verify both DER SHA-256
values against `blitz.trust.java.py`, and stop on any mismatch/error. Then:

```sh
sudo python3 /home/admin/config.scripts/blitz.trust.java.py update
sudo python3 /home/admin/config.scripts/blitz.trust.java.py check
```

Read back the exact public inventory and compare all surviving aliases and
fingerprints. Run Java's actual TLS controls on-device, using a reviewed
compiled harness, then restart only identified consumers. No Java process
was running at inspection, but recheck rather than assuming it stays so.

If an explicitly approved functional rollback is unavoidable, re-import
only the two exported public certificates under their original aliases.
This **re-enables compromised trust paths**, so never do it automatically:

```sh
sudo keytool -importcert -noprompt -keystore /etc/ssl/certs/java/cacerts \
  -storepass changeit -alias 'debian:emsign_ecc_root_ca_-_g3.pem' \
  -file /root/java-ca-public-rollback-20261029/ecc-g3.pem
sudo keytool -importcert -noprompt -keystore /etc/ssl/certs/java/cacerts \
  -storepass changeit -alias 'debian:comodo_aaa_services_root.pem' \
  -file /root/java-ca-public-rollback-20261029/aaa.pem
```

Alternative vendor-only reconciliation, **only after approving every stale
`debian:` alias for removal and ruling out private-key entries**, is:

```sh
sudo dpkg-trigger --no-await update-ca-certificates-java-fresh
sudo dpkg --triggers-only --pending ca-certificates-java
```

This is safer than deleting the complete keystore but still can delete
Java-only custom `debian:` entries. It may honor locally disabled Java
updates and do nothing. Always read back the exact store; success status
alone is insufficient. This alternative was sandbox-tested, not run on-node.
