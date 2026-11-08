# Automated trust regression fixtures

`java-trust-anchors.pem` is the original, unchanged frozen public-only fixture
introduced by `f8a87e0b707b3cca64e30a9a81b134ef846927a5`. It contains real signed
X.509 certificates, **not generated replacements or a copied private keystore**:

| Certificate | DER SHA-256 |
| --- | --- |
| emSign ECC Root CA - G3 | `86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b` |
| AAA Certificate Services | `d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4` |
| ISRG Root X1 | `96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6` |

The unchanged PEM file SHA-256 is
`d622a0e5ba04e89a4a75eac94a2faac752473f325294be037ec3cdb6d09909ec`.
See [the original transaction audit](../JAVA-TRUST-TRANSACTION.md) for its public
inventory purpose. None of the original audit/provenance records are replaced.

`incident-chains.zip` is fetched into the disposable test image at build time,
not redistributed in this repository: explicit archive redistribution terms
have not been established. It is the unmodified public archive downloaded on October 29,
2026 from <https://emudhra.we-have-a-problem.com/chains.zip>, retained from the
original audit's `host-regression/chains.zip`. Its SHA-256 is
`afb9d69e8e5fc9eb0c08d5fe4baafc67edbcced2d63af2f9deb62edb6431d4a9`.
It contains the 14 regular and two rollover public certificate chains. The runner
checks archive integrity before extraction; both regression programs independently
require the exact 16 filenames. OpenSSL and Java validate their real certificate
signatures against the archived anchors before requiring rejection after removal.
The archive has no publisher detached signature; the digest is a frozen integrity
pin, **not a claim of independent archive-signature authentication**.

The surrounding positive-control CA inventory comes from the disposable image's
APT-authenticated Debian `ca-certificates` package, never a host mount. The before
bundle augments it with the three archived anchors. The after bundle is exported
from a JKS actually remediated by the production helper. This qualifies the scoped
removal policy, not historical Debian package installation/reconciliation.
The historical Temurin 17.0.19 JDK and fixed Node 22.23.4 image are pinned by OCI
manifest digest in `test/trust.Dockerfile`; newer Java blocklists would invalidate
the accepted-before experiment. Do not delete/disable Java blocklists or relax
verification to make a newer baseline pass.

The private organization CA and encrypted key used in preservation tests are
fresh disposable synthetic fixtures, clearly separate from these public incident
fixtures. They are never substituted for incident chains or live probes.
