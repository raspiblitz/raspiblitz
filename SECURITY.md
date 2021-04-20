# Security Policy

## Supported Versions

Updates are made only for the latest version.

Security patches can be done with `Menu > Patch` for the current branch in the case of a high risk issue before next release.

The latest version always have the `latest` tag. To make sure you are using the lastest version, run:
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

# Online Security
* Wi-fi and Bluetooth is disabled by default in the build script.
* UFW is active and only specific ports are open, closing ports and removing hidden services when services are uninstalled.
* Admin (and Joinmarket [optional]) users have passwordless sudo access to be able to perform installations and read password without much user interaction.

# Physical Security
* All wallets and user interfaces are password protected so this has more privacy implications (in the case of physical theft) than security.
* Optional log in through SSH using a hardware wallet.
* LUKS encryption would be welcome in the future.
