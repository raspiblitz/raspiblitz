# Java transaction and lifecycle repair contract

This local repair supersedes the unsafe live-keytool mutation in `b8753cb`.
It does not retroactively qualify that implementation or deploy anything.
Policy remains exactly Debian's two DER identities, not OpenJDK's four roots.

## Transaction and concurrency boundary

* Require an owner-controlled parent directory and a regular, non-hardlinked
  final file. Canonicalize the parent but reject a final-component symlink.
  The default JRE's cacerts symlink is inspected and its canonical Debian
  target selected, not replaced. The helper never changes Java alternatives.
* Hold a persistent mode-0600 sibling `.<store>.trust.lock` with `flock` for
  the entire transaction, including check mode. Never unlink the lock, which
  would permit two helper writers to lock different inodes. Normal production
  check and update both run through sudo.
* Snapshot the original inode, content, uid, gid, mode, size, mtime, and ctime.
  Use a same-filesystem mode-0700 transaction directory. Preserve an original
  mode-0600 snapshot and a separate staged encrypted container. No keytool
  command, including an inventory read, is directed at the live store.
* Validate exact expected surviving public entries and byte-identical opaque
  encrypted private JKS records. Custom CA aliases, including direct `debian:`
  imports and safe certificates with incident-like names, survive. Incident
  identities in private entries, unsupported formats/types, malformed or
  control/multiline aliases, and custom passwords fail closed.
* Restore owner/mode and available metadata to the validated candidate. On
  Linux, verify copied xattrs, including POSIX ACL xattrs, match exactly or
  fail before commit. Local macOS Python lacks xattr APIs, so local execution
  establishes mode/owner behavior, not Linux ACL integration acceptance.
* Fsync the candidate, protected original, transaction directory, and parent.
  Re-read and compare original inode/metadata/content immediately before
  atomic same-filesystem `os.replace`, then fsync the live parent. Read back
  committed inode/content before reporting success. No truncate/write syscall
  is issued against the live file by keytool or the helper.
* A detected changed live file is not overwritten. In particular, the actual
  reproduced race that substitutes a safe certificate under a bad alias at
  the last-listing/delete boundary now mutates only the stage, detects the
  changed live bytes, aborts, and leaves the external safe replacement intact.
* **This is not compare-and-swap against privileged noncooperating writers.**
  POSIX provides no atomic content/inode-conditional rename here. Administrators
  must quiesce APT, vendor hooks, arbitrary keytool processes, and other root
  writers during helper maintenance. `flock` serializes this helper's writers
  only. A privileged write in the final check/rename gap remains outside the
  contract; neither a lock nor repeated inventories can remove that boundary.
  The same limitation applies to a guarded rollback.

## Failure, rollback, and cleanup

Precommit failures, interrupted keytool writes, SIGTERM, and Python interruption
leave live bytes unchanged and clean the transaction directory. SIGKILL or
power loss before commit leaves the original live file and may leave a
mode-0700 transaction directory with a mode-0600 original. No temporary-file
scheme can run cleanup after SIGKILL. Never automatically sweep those directories
without confirming no transaction is active and reviewing their recovery value.

Atomic commit presents either the whole old store or the whole validated new
store, subject to filesystem fsync/rename guarantees, not a truncated keytool
file. Power-loss behavior is based on those filesystem primitives; process
fault injection is not a hardware power-cut test.

If post-rename directory fsync fails, restore through another atomic replacement
only if the committed inode and bytes are still ours. Restore owner/mode and
metadata, fsync, fail the operation, and retain the protected original directory
for administrator review. If live content changed, do not overwrite it; retain
the original and report the recovery directory. If rollback itself fails, the
protected original remains available. Review the original against current live
state before any administrator restore; do not blindly overwrite later changes.

Opaque snapshot/staging of an encrypted JKS is container preservation, **not
private-key export**. No private password is read, no key is decrypted, and no
key material is printed. Tests generate one disposable fixture key with a
separate synthetic key password, keep its container mode 0600, and delete the
fixture directory after each case. No user keys are used.

## Lifecycle and effective Java trust

Normal invocation verifies PATH's Java resolves to `/usr/bin/java`, keytool
belongs to the same selected home, there is no `lib/security/jssecacerts`
override (including a dangling symlink), and cacerts resolves exactly to
`/etc/ssl/certs/java/cacerts`. Explicit Java/Maven environment overrides fail
with separate-review instructions before sudo can discard them. Explicit
`--keystore` is for isolated fixtures or separately reviewed stores and bypasses
the selected-JRE gate; it does not certify the default JSSE store.

FinTS fails on Java/Maven package-install errors and invokes trust remediation
immediately after those installations, before its first Maven download. It
checks again immediately before Maven, rejects custom Maven startup/project JVM
configuration actionably, skips rc evaluation, and binds Maven's JAVA_HOME to
the checked alternatives-selected `/usr/bin/java` home. Independent Java trust
managers, app-defined stores, later custom configuration, changed alternatives,
and external Java services still need their own review/restart. This is not a
universal certificate-store certification or a full FinTS installation test.

## Local evidence

Run the original eight tests plus fault/lifecycle tests with a real keytool:

```sh
JAVA_TRUST_PUBLIC_LISTING=public-list.txt python3 -m unittest discover -s test -p 'test_java_trust*.py' -v
bats test/blitz.trust.bats
```

Final local results: **24/24 Python tests** (the original 8 plus 16 safety and
lifecycle tests), **17/17 Bats tests** (the original 15 plus 2 Java gates).

Local Temurin 17.0.19 execution built fresh public-only stores from the 163-entry
public inventory: update removed exactly 2 and preserved exactly 161. A freshly
compiled `JavaTrustProbe` then passed **68/68** PKIX and live HTTPS before/after
controls, including all 16 offline incident chains, 14 served incident hosts,
and four positive TLS controls per state. These are local runtime controls,
not Debian node execution or deployment. The parent owns separate node evidence.

Evidence is under `$HERMES_SCRATCH/java-repair-evidence/` in this review session
(`unittest.log`, `bats.log`, `jsse.json`, public-only before/after stores).
Initial test-harness mistakes (a recursive mock and a mutable-argv marker path)
were fixed before passing reruns; those first failures were not helper success.

## Subsequent Debian/Raspberry Pi acceptance

The same transaction and lifecycle suites were then run on the node's Debian
OpenJDK 17.0.19 against disposable stores. All 25 tests passed without skips,
including an added real Linux POSIX access-ACL and user-xattr preservation case.
That case uses the Linux UAPI ACL encoding and needs no ACL utility package.
Owner, group, mode, ACL bytes, and unrelated xattrs survived remediation.
CI now builds an isolated store from three frozen public CA certificates: the
two incident identities and ISRG Root X1. It runs the complete safety suite
without depending on the runner still trusting the incident roots. The exact
workflow test step also passed all 25 tests on Debian without skips.
An initial test-source package omitted the FinTS script and failed one lifecycle
test; including the reviewed script produced the passing full rerun.

Separately, a supervised atomic replacement had already corrected the live
public-only store, removing two incident entries and preserving 161. Actual
Debian JSSE passed 68 before/after controls and 18 default-context live controls.
That manual operation is not evidence for the old unsafe implementation. The
repaired helper's Linux fault/preservation qualification used disposable stores,
not user private keys. Full FinTS installation, full image/reboot acceptance,
and hardware power-cut behavior remain untested.
