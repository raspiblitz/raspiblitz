---
name: TunnelSats Integration (Final with Core Script)
overview: Finalize Python integration by using environment variables for Cloudflare, fixing BlitzError, and leveraging the now-verified `tunnelsats.sh` for installation.
todos:
  - id: load-env
    content: Load env vars from .tunnelsats.env for Cloudflare auth.
    status: completed
  - id: fix-blitzerror
    content: Fix BlitzError usage (pass dict instead of str) in tunnelsats.py.
    status: completed
  - id: refactor-dialog
    content: Refactor create_ssh_dialog to include Management Menu (Status, Renew, Cancel).
    status: completed
    dependencies:
      - fix-blitzerror
  - id: implement-renew
    content: Implement renew_subscription logic using local pubkey.
    status: completed
    dependencies:
      - refactor-dialog
  - id: harden-polling
    content: Harden API polling with timeouts and retry logic.
    status: completed
  - id: improve-backup
    content: Improve Backup UI with user acknowledgement.
    status: completed
  - id: update-hub
    content: Update blitz.subscriptions.py detail view text.
    status: completed
---

# TunnelSats Integration & Bugfix Plan

## Objective

Finalize the Python-based subscription handler (`blitz.subscriptions.tunnelsats.py`) for RaspiBlitz, incorporating fixes for `BlitzError`, environment variable loading for dev API access, and robust handoff to the core `tunnelsats.sh` script.

## Key Changes

### 1. Handler Improvements (`blitz.subscriptions.tunnelsats.py`)

-   **Bug Fix**: Correct `BlitzError` usage (pass dict, not str).
-   **Env Loading**: Load `.tunnelsats.env` for `cfClientId` and `cfClientSecret` to allow testing against `dev2.tunnelsats.com`.
-   **Refactor `create_ssh_dialog`**:
    -   Detect existing subscription -> Show **Management Menu**.
    -   Management Menu Options: `Status`, `Renew`, `Cancel`, `Reinstall Config`.
-   **Implement Renewal**:
    -   Flow: `Select Duration` -> `API Call (Renew)` -> `Pay Invoice` -> `Wait for Confirmation`.
    -   **Target Server**: Verify logic using `fi1` (test server).
-   **Harden Polling**:
    -   Add `timeout=10` to `requests` calls.
    -   Robust loop handling for network glitches.
-   **Backup UI**:
    -   Force user acknowledgement via `yesno` dialog: "I have saved the config / QR code".

### 2. Core Handoff (`tunnelsats.sh`)

-   We have confirmed `tunnelsats.sh` supports `install --config <file>`.
-   The Python script will call: `sudo bash /home/admin/tunnelsats/scripts/tunnelsats.sh install --config <path>` (preferring the user's workspace path if valid, falling back to standard install locations).

### 3. Hub Integration (`blitz.subscriptions.py`)

-   Update `tunnelsats-v1` detail text to direct users to the Management Menu for renewals.

## Files to Modify

-   [`home.admin/config.scripts/blitz.subscriptions.tunnelsats.py`](home.admin/config.scripts/blitz.subscriptions.tunnelsats.py)
-   [`home.admin/config.scripts/blitz.subscriptions.py`](home.admin/config.scripts/blitz.subscriptions.py)

## Verification

-   **Env Check**: Verify headers include CF tokens.
-   **Flow**: Test "New Subscription" with `fi1`, then "Renew", then "Cancel".
-   **Install**: Ensure `tunnelsats.sh` is triggered correctly.