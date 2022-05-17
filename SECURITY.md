# Security Policy

*NOTE: This document is just a first draft and still under construction.*

Only use this software with funds you could afford to lose. Especially a lightning wallet that is a hot wallet, which has constant connection to the internet and can be target of exploitation.

Just because the software is OpenSource does not mean its free of errors. Especially if you run additional apps, the RaspiBlitz team cannot review all the code of those external projects.

The software is provided "AS IS", without warranty of any kind. In no event shall the
authors or copyright holders be liable for any claim, damages or other
liability. [details on legal license](LICENSE.md)

## Supported Versions

Updates are made only for the latest version.

Security patches can be done with `MAINMENU > UPDATE > PATCH` for the current branch in the case of a high risk issue before next release.

The latest version always have the `latest` tag. To make sure you are using the latest version, run:
```
curl -s https://api.github.com/repos/rootzoll/raspiblitz/releases/latest|grep tag_name|head -1|cut -d '"' -f4
```

## Reporting a Vulnerability

To report security issues send an email to christian@rotzoll.de (not for support).

The following keys may be used to communicate sensitive information to developers:

| Name | Fingerprint | 64-bit |
|------|-------------|--------|
|Rootzoll|92A7 46AE 33A3 C186 D014 BF5C 1C73 060C 7C17 6461|1C73 060C 7C17 6461|
|Openoms|13C6 88DB 5B9C 745D E4D2 E454 5BFB 7760 9B08 1B65|5BFB 7760 9B08 1B65|

You can import a key by running the following command with that individual’s fingerprint:
```
curl https://keybase.io/rootzoll/pgp_keys.asc | gpg --import
curl https://keybase.io/oms/pgp_keys.asc | gpg --import
```
Ensure that you put quotes around fingerprints containing spaces if importing with other methods.

# Privacy Protection

When you call `debug` on the command line you get basic system & services logs that can be used if you need to report details for support by other users. There is already a basic redaction of private data (nodeids, IPv4s, .onion-adresses, balances) for that debug report BUT always check the data you post in DMs or public before sending. If you find further private data that needs redaction, please report as an issue on the github repo.  

# Network Security

* Limit attack surface: Wi-fi and Bluetooth is disabled by default in the build script.
* Firewall: UFW is active and only specific ports are open, closing ports and removing hidden services when services are uninstalled.
* Password brute forcing protection: Fail-2-Ban is protecting the SSH login against brute-force-attacks.

# Software security

* The `admin` (and the `joinmarket` [optional]) users have passwordless sudo access to be able to perform installations and read password without much user interaction.

* Downloaded binaries and source code is verified with the authors' PGP keys by either:
    * signed shasum files and checking the hash of each downloaded binary
    * verfying the signature on the source code changes utilising the `git verify-commit` or `git verify-tag` commands

# Physical Security

* The lightning wallet and user interfaces are password protected by default so this has more privacy implications (in the case of physical theft) than security.
* Basic hardening measures are applied to all non-root systemd services
* Optional log in through SSH using a hardware wallet.
* LUKS encryption would be welcome in the future.

# On-chain Funds

Please keep in mind that there can be two different on-chain wallets on the RaspiBlitz:

## Lightning Wallet (default)

The default is the on-chain lightning wallet - that's the wallet where you normally send your funds before opening a channel & where your funds return to when you close a channel. With the initial word seed you get during RaspiBlitz setup, you can get access again to this on-chain wallet. Keep the seed words secure in a off-line location.

## Bitcoin Core Wallet (deactivated by default)

Beside lightning you have a Bitcoin core installed. Normally, Bitcoin core acts just as a blockchain informational service to the lightning wallet and its internal separate on-chain wallet is deactivated. 

Some apps (like Fully Noded or JoinMarket) activate the Bitcoin core wallet and use it for their own needs. This on-chain balance will not be reflected in the rest of the RaspiBlitz software and is NOT backed up by the seed words from the RaspiBlitz setup. If you make use of the Bitcoin core wallet please take care of these funds. 

# Off-chain Funds (Lightning Channels)

Please note that there is no perfect backup concept for the funds in your lightning channels yet. We strongly recommend using the `Static Channel Backup` provided by LND and consider off-line location backup of that file to have the best chances to recover Lightning funds in a case of recovering from a disaster.

The C-ligthning lightning.sqlite3 is replicated on the SDcard from the disk in real time. See more details in the [C-lightning FAQ](FAQ.cl.md#backups)


For more practical information on this topic see: [Backup Channel Funds](README.md#backup-for-on-chain---channel-funds)
