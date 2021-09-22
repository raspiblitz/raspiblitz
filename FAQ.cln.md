## C-lightning FAQ

* C-lightning official documentation: https://lightning.readthedocs.io/

## Directories

## Aliases

## Plug-ins

### General info
* https://lightning.readthedocs.io/PLUGINS.html#a-day-in-the-life-of-a-plugin
* https://github.com/lightningd/plugins/

### Implemented plugins
*
*
*
### Add a custom plugin
*
### CLBOSS
* Advanced usage
https://github.com/ZmnSCPxj/clboss#clboss-status

* Stopping CLBOSS will leave the node in the last state. No channels will be closed or funds removed when CLBOSS is stopped.

## Backups
### Seed
-
### Channel database
-

## Script file help list

```
# generate a list of help texts on a RaspiBlitz:
cd /home/admin/config.scripts/
ls cln*.sh > clnScriptList.txt
sed -i "s#cln#./cln#g" clnScriptList.txt
sed -i "s#.sh#.sh -h#g" clnScriptList.txt
bash -x clnScriptList.txt
rm clnScriptList.txt
```

```
+ ./cln.backup.sh -h

---------------------------------------------------
CLN RESCUE FILE (tar.gz of complete cln directory)
---------------------------------------------------
cln.backup.sh cln-export
cln.backup.sh cln-export-gui
cln.backup.sh cln-import [file]
cln.backup.sh cln-import-gui [setup|production] [?resultfile]
---------------------------------------------------
SEED WORDS
---------------------------------------------------
cln.backup.sh seed-export-gui [lndseeddata]
cln.backup.sh seed-import-gui [resultfile]

+ ./cln.hsmtool.sh -h

Create new wallet or import seed
Unlock/lock, encrypt, decrypt, set autounlock or change password for the hsm_secret

Usage:
Create new wallet:
cln.hsmtool.sh [new] [mainnet|testnet|signet] [?seedPassword]
cln.hsmtool.sh [new-force] [mainnet|testnet|signet] [?seedPassword]
There will be no seedPassword(passphrase) used by default
new-force will delete any old wallet and will work without dialog

cln.hsmtool.sh [seed] [mainnet|testnet|signet] ["space-separated-seed-words"] [?seedPassword]
cln.hsmtool.sh [seed-force] [mainnet|testnet|signet] ["space-separated-seed-words"] [?seedPassword]
The new hsm_secret will be not encrypted if no NewPassword is given
seed-force will delete any old wallet and will work without dialog

cln.hsmtool.sh [unlock|lock] <mainnet|testnet|signet>
cln.hsmtool.sh [encrypt|decrypt] <mainnet|testnet|signet>
cln.hsmtool.sh [autounlock-on|autounlock-off] <mainnet|testnet|signet>

cln.hsmtool.sh [change-password] <mainnet|testnet|signet> <NewPassword>

+ ./cln.install-service.sh -h

Script to set up or update the C-lightning systemd service
Usage:
/home/admin/config.scripts/cln.install-service.sh <mainnet|testnet|signet>

+ ./cln.install.sh -h

C-lightning install script
The default version is: v0.10.1
Setting up on mainnet unless otherwise specified
mainnet / testnet / signet instances can run parallel

Usage:
cln.install.sh on <mainnet|testnet|signet>
cln.install.sh off <mainnet|testnet|signet> <purge>
cln.install.sh [update <version>|testPR <PRnumber>]
cln.install.sh display-seed <mainnet|testnet|signet>

+ ./cln-plugin.backup.sh -h

Install the backup plugin for C-lightning
Replicates the lightningd.sqlite3 database on the SDcard

Usage:
cln-plugin.backup.sh [on|off] [testnet|mainnet|signet]
cln-plugin.backup.sh [restore] [testnet|mainnet|signet] [force]
cln-plugin.backup.sh [backup-compact] [testnet|mainnet|signet]

https://github.com/lightningd/plugins/tree/master/backup

+ ./cln-plugin.clboss.sh -h

Install or remove the CLBOSS C-lightning plugin
version: v0.10
Usage:
cln-plugin.clboss.sh [on|off] [testnet|mainnet|signet]

+ ./cln-plugin.sparko.sh -h

Install, remove, connect or get info about the Sparko plugin for C-lightning
version: v2.7
Usage:
cln-plugin.sparko.sh [on|off|menu|connect] [testnet|mainnet|signet]

+ ./cln-plugin.standard-python.sh -h

Install and show the output of the chosen plugin for C-lightning
Usage:
cln-plugin.standard-python.sh on [plugin-name] [testnet|mainnet|signet] [runonce]

tested plugins:
summary | helpme | feeadjuster

find more at:
https://github.com/lightningd/plugins

+ ./cln-plugin.summary.sh -h

Install and show the output if the summary plugin for C-lightning
Usage:
cln-plugin.summary.sh [testnet|mainnet|signet] [runonce]

+ ./cln.rest.sh -h

C-lightning-REST install script
The default version is: v0.5.1
mainnet | testnet | signet instances can run parallel
The same macaroon and certs will be used for the parallel networks

Usage:
cln.rest.sh [on|off|connect] <mainnet|testnet|signet>

+ ./cln.setname.sh -h

Config script to set the alias of the C-lightning node
cln.setname.sh [mainnet|testnet|signet] [?newName]
```