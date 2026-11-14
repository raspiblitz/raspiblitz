# Security Policy

## Reporting a vulnerability

Please report security vulnerabilities privately by email to [christian@fulmo.org](mailto:christian@fulmo.org).

Do not disclose potential vulnerabilities publicly or open a public issue before the maintainers have had an opportunity to investigate.

Please include enough information to reproduce the finding, including the affected component, relevant versions or configuration, and any proof of concept that can be shared safely.

## Security audits

We are continuously probing critical points of the codebase with AI-assisted audits, starting with the most sensitive areas like key generation. We cannot scan all bonus apps and their integrations — we are open for community reports and fixes for those. If you find an issue, please report it as described above.

### Wallet seed generation (Core Lightning) — audited 2026-08

The only place RaspiBlitz generates wallet seed entropy itself (outside standard software) is the Core Lightning mainnet path: `blitz.mnemonic.py` (called from `cl.hsmtool.sh`). It produces a 24-word BIP-39 mnemonic with a true 256-bit seed drawn directly from the OS CSPRNG (`os.urandom(32)` → `getrandom()`, verified in the pinned `python-mnemonic==0.19` source). All other wallets (LND, Bitcoin Core, lightningd fallback) are generated inside the daemons' own CSPRNGs.

The only notable findings lie outside the entropy path:

- a fail-closed interface break with pinned CLN ≥ v25.12 (wallet creation aborts — no weak wallet is ever produced)
- an unverified runtime PyPI install of the entropy library
- temporary plaintext seed files

From an entropy and cryptographic standpoint, the seed generation is sound and rated secure ✅ — the identified break is functional (fail-closed), not a weakness in randomness.
