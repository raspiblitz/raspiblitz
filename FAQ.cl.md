<!-- omit in toc -->
# C-lightning FAQ

- [C-lightning official documentation](#c-lightning-official-documentation)
- [Commands and aliases](#commands-and-aliases)
- [Directories](#directories)
- [Config file](#config-file)
- [Plug-ins](#plug-ins)
  - [General info](#general-info)
  - [Directories](#directories-1)
  - [Implemented plugins](#implemented-plugins)
  - [Add a custom plugin](#add-a-custom-plugin)
  - [CLBOSS](#clboss)
  - [Dual funded channels](#dual-funded-channels)
    - [Reading](#reading)
    - [Setting up](#setting-up)
    - [Opening a dual funded channel](#opening-a-dual-funded-channel)
  - [Offers](#offers)
  - [About the feature bits](#about-the-feature-bits)
- [Testnets](#testnets)
- [Backups](#backups)
  - [Seed](#seed)
  - [Channel database](#channel-database)
- [Script file help list](#script-file-help-list)

## C-lightning official documentation
* https://lightning.readthedocs.io/

## Commands and aliases

* Check if the C-lightning daemon is running:
    ```
    sudo systemctl status lightningd
    ```
* Follow it's system output for debugging:
    ```
    sudo journalctl -fu lightningd
    ```
* The logs can be accessed in the menu `SYSTEM` - `CLLOG`
or with the alias: `cllog`
* The frequently used commands are shortened with alisases. Check them with the command `alias`:
    ```
    alias cl='sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/config'
    alias clconf='sudo nano /home/bitcoin/.lightning/config'
    alias cllog='sudo tail -n 30 -f /home/bitcoin/.lightning/bitcoin/cl.log'
    ```
## Directories
* All data is stored on the disk in:  
`/mnt/hdd/app-data/.lightningd`  
* and symlinked to:  
`/home/bitcoin/.lightningd`

## Config file
* edit in the menu `SYSTEM` - `CLNCONF` or use the alias `clconf`
* Default values for mainnet:
    ```
    network=bitcoin
    announce-addr=127.0.0.1:9736
    log-file=cl.log
    log-level=info
    plugin-dir=/home/bitcoin/cln-plugins-enabled

    # Tor settings
    proxy=127.0.0.1:9050
    bind-addr=127.0.0.1:9736
    addr=statictor:127.0.0.1:9051/torport=9736
    always-use-proxy=true
    ```


## Plug-ins

### General info
* https://lightning.readthedocs.io/PLUGINS.html#a-day-in-the-life-of-a-plugin
* https://github.com/lightningd/plugins/

### Directories
* The plugins are installed to:  
`/home/bitcoin/cl-plugins-available`
* and symlinked to:  
`/home/bitcoin/cl-plugins-enabled`
* All plugins in the `/home/bitcoin/cl-plugins-enabled` directory are loaded automatically as set in the config file: `/home/bitcoin/.lightningd/config`

### Implemented plugins
* summary
* sparko
* clboss

### Add a custom plugin

* The easiest way is to palce the plugin in the  
`/home/bitcoin/cl-plugins-enabled`
directory and start with
    ```
    lightnign-cli plugin start /home/bitcoin/cl-plugins-enabled/PLUGIN_NAME
    ```
    or restart C-ligthning with:
    ```
    sudo systemctl restart lightningd
    ```
    to have it loaded automatically.

### CLBOSS
A plugin for automatic LN node management.
CLBOSS only requires to have funds deposited  to the onchain wallet of C-lightning.
The recommended amount to start is ~ 10 million satoshis (0.1 BTC).

It does automatically:

* generate outbound capacity - opens channels
* generate inbound capacity - submarine swaps through the boltz.exchange API
* aware of onchain fees and mempool through c-lightning and makes transactions when fees are low
* manages rebalancing - performs probing
* closes bad channels (inactive or low traffic) - this function needs to activated manually

Overall it is a tool which makes users able to send and receive lightning payments with minimal interaction, basically setting up a routing node by itself.

The transactions made by CLBOSS does cost money and running it requires a fair amount of trust in the (fully open-source - MIT) code.
Neither the CLBOSS nor the RaspiBlitz developers can take resposibility for lost sats, use at your own discretion!

* Discussion: https://github.com/rootzoll/raspiblitz/issues/2490
* Advanced usage
https://github.com/ZmnSCPxj/clboss#clboss-status  
* Stopping CLBOSS will leave the node in the last state. No channels will be closed or funds removed when CLBOSS is uninstalled.

### Dual funded channels
#### Reading
* https://medium.com/blockstream/c-lightning-opens-first-dual-funded-mainnet-lightning-channel-ada6b32a527c  
* https://medium.com/blockstream/setting-up-liquidity-ads-in-c-lightning-54e4c59c091d  
* https://twitter.com/niftynei/status/1389328732377255938  
* lightning-rfc PR: https://github.com/lightningnetwork/lightning-rfc/pull/851/files
* represented by the feature bits 28/29

#### Setting up
* activate the feature on your node:  
Type: `clconf` or use the menu `SYSTEM` - `CLCONF`.  
Add the line:
    ```
    experimental-dual-fund    
    ```
    Save and restart C-lightning.

* set up a liquidity ad:
    ```
    lightning-cli funderupdate -k policy=match policy_mod=100
    ```
    or set in the config for example - see the meaning of each line in https://medium.com/blockstream/setting-up-liquidity-ads-in-c-lightning-54e4c59c091d :

    ```
    experimental-dual-fund
    funder-policy=match
    funder-policy-mod=100
    lease-fee-base-msat=500sat
    lease-fee-basis=50
    channel-fee-max-base-msat=100sat
    channel-fee-max-proportional-thousandths=2
    ```
* check the settings used currently on your node:
    ```
    lightning-cli funderupdate
    ```
* check your advertised settings (needs some minutes to appear):
    ```
    lightning-cli listnodes $(lightning-cli getinfo | jq .id)
    ```

#### Opening a dual funded channel
* check if a node has onchain liquidity on offer:
    ```
    lightning-cli listnodes nodeid
    ```

    Example:
    ``` 
    lightning-cli listnodes 02cca6c5c966fcf61d121e3a70e03a1cd9eeeea024b26ea666ce974d43b242e636
    ```
* list all nodes known in the graph with active offers:
    ```
    lightning-cli listnodes | grep option_will_fund -B20 -A7
    ```
* note the node `id` and `compact_lease`

* connect to the node
    ```
    lightning-cli connect nodeID@IP_or.onion
    ```
* open the channel (amount is the own funds in the wallet contributed)
    ```
    lightning-cli fundchannel -k id=NODEID amount=0.01btc request_amt=0.01btc compact_lease=COMPACT_LEASE
    ```  
    It can fail if the offer changed or there are not enough funds available on either side.

### Offers
* Details at bolt12.org
* create an offer to receive payments:  
https://lightning.readthedocs.io/lightning-offer.7.html
    ```
    lightning-cli offer amount description [vendor] [label] [quantity_min] [quantity_max] [absolute_expiry] [recurrence] [recurrence_base] [recurrence_paywindow] [recurrence_limit] [single_use]
    ```
* Create an offer to send payments:  
https://lightning.readthedocs.io/lightning-offerout.7.html  
    ```
    lightning-cli offerout amount description [vendor] [label] [absolute_expiry] [refund_for]
    ```
* Fetch an invoice to pay an offer:  
https://lightning.readthedocs.io/lightning-fetchinvoice.7.html  
Will need at least one peer which supports onion the messages. For example:
    ```
    lightning-cli connect 024b9a1fa8e006f1e3937f65f66c408e6da8e1ca728ea43222a7381df1cc449605@128.199.202.168:9735
    ```
* Then use the command to fetch the BOLT12 invoice:  
    ```
    lightning-cli fetchinvoice offer [msatoshi] [quantity] [recurrence_counter] [recurrence_start] [recurrence_label] [timeout] [payer_note]
    ```
* decode a BOLT12 invoice:  
    ```
    lightning-cli decode bolt12_invoice
    ```
* pay a a BOLT12 invoice:
Will need to pay through a peer which supports the onion messages which means you need at least one channel with such a node.
    ```
    lightning-cli pay bolt12_invoice
    ```

### About the feature bits
* https://bitcoin.stackexchange.com/questions/107484/how-can-i-decode-the-feature-string-of-a-lightning-node-with-bolt-9
* Convert the hex number from `lightning-cli listpeers` to binary: https://www.binaryhexconverter.com/hex-to-binary-converter and count the position of the bits from the right.


## Testnets

* for testnet and signet there are prefixes `t` and `s` used for the aliases, daemons and their own plugin directory names.
* Testnet
    ```
    # alias: 
    tcl | tclconf | tcllog

    # daemon service name: 
    tlightningd
    
    # config file:
    /home/bitcoin/.lightningd/testnet/config
    
    # plugin directory:
    /home/bitcoin/tcl-plugins-enabled
    ```
* Signet
    ```
    # aliases:
    scl | sclconf | scllog

    # daemon service name: 
    slightningd

    # config file:
    /home/bitcoin/.lightningd/signet/config

    # plugin directory:
    /home/bitcoin/scl-plugins-enabled
    ```



## Backups
### Seed
-
### Channel database
*

## Script file help list

```
# generate a list of help texts on a RaspiBlitz:
cd /home/admin/config.scripts/
ls cl*.sh > clScriptList.txt
sed -i "s#cl#./cl#g" clScriptList.txt
sed -i "s#.sh#.sh -h#g" clScriptList.txt
bash -x clScriptList.txt
rm clScriptList.txt
```

```
+ ./cl.backup.sh -h

---------------------------------------------------
CL RESCUE FILE (tar.gz of complete cl directory)
---------------------------------------------------
cl.backup.sh cl-export
cl.backup.sh cl-export-gui
cl.backup.sh cl-import [file]
cl.backup.sh cl-import-gui [setup|production] [?resultfile]
---------------------------------------------------
SEED WORDS
---------------------------------------------------
cl.backup.sh seed-export-gui [lndseeddata]
cl.backup.sh seed-import-gui [resultfile]

+ ./cl.hsmtool.sh -h

Create new wallet or import seed
Unlock/lock, encrypt, decrypt, set autounlock or change password for the hsm_secret

Usage:
Create new wallet:
cl.hsmtool.sh [new] [mainnet|testnet|signet] [?seedPassword]
cl.hsmtool.sh [new-force] [mainnet|testnet|signet] [?seedPassword]
There will be no seedPassword(passphrase) used by default
new-force will delete any old wallet and will work without dialog

cl.hsmtool.sh [seed] [mainnet|testnet|signet] ["space-separated-seed-words"] [?seedPassword]
cl.hsmtool.sh [seed-force] [mainnet|testnet|signet] ["space-separated-seed-words"] [?seedPassword]
The new hsm_secret will be not encrypted if no NewPassword is given
seed-force will delete any old wallet and will work without dialog

cl.hsmtool.sh [unlock|lock] <mainnet|testnet|signet>
cl.hsmtool.sh [encrypt|decrypt] <mainnet|testnet|signet>
cl.hsmtool.sh [autounlock-on|autounlock-off] <mainnet|testnet|signet>

cl.hsmtool.sh [change-password] <mainnet|testnet|signet> <NewPassword>

+ ./cl.install-service.sh -h

Script to set up or update the C-lightning systemd service
Usage:
/home/admin/config.scripts/cl.install-service.sh <mainnet|testnet|signet>

+ ./cl.install.sh -h

C-lightning install script
The default version is: v0.10.1
Setting up on mainnet unless otherwise specified
mainnet / testnet / signet instances can run parallel

Usage:
cl.install.sh on <mainnet|testnet|signet>
cl.install.sh off <mainnet|testnet|signet> <purge>
cl.install.sh [update <version>|testPR <PRnumber>]
cl.install.sh display-seed <mainnet|testnet|signet>

+ ./cl-plugin.backup.sh -h

Install the backup plugin for C-lightning
Replicates the lightningd.sqlite3 database on the SDcard

Usage:
cl-plugin.backup.sh [on|off] [testnet|mainnet|signet]
cl-plugin.backup.sh [restore] [testnet|mainnet|signet] [force]
cl-plugin.backup.sh [backup-compact] [testnet|mainnet|signet]

https://github.com/lightningd/plugins/tree/master/backup

+ ./cl-plugin.clboss.sh -h

Install or remove the CLBOSS C-lightning plugin
version: v0.10
Usage:
cl-plugin.clboss.sh [on|off] [testnet|mainnet|signet]

+ ./cl-plugin.sparko.sh -h

Install, remove, connect or get info about the Sparko plugin for C-lightning
version: v2.7
Usage:
cl-plugin.sparko.sh [on|off|menu|connect] [testnet|mainnet|signet]

+ ./cl-plugin.standard-python.sh -h

Install and show the output of the chosen plugin for C-lightning
Usage:
cl-plugin.standard-python.sh on [plugin-name] [testnet|mainnet|signet] [runonce]

tested plugins:
summary | helpme | feeadjuster

find more at:
https://github.com/lightningd/plugins

+ ./cl-plugin.summary.sh -h

Install and show the output if the summary plugin for C-lightning
Usage:
cl-plugin.summary.sh [testnet|mainnet|signet] [runonce]

+ ./cl.rest.sh -h

C-lightning-REST install script
The default version is: v0.5.1
mainnet | testnet | signet instances can run parallel
The same macaroon and certs will be used for the parallel networks

Usage:
cl.rest.sh [on|off|connect] <mainnet|testnet|signet>

+ ./cl.setname.sh -h

Config script to set the alias of the C-lightning node
cl.setname.sh [mainnet|testnet|signet] [?newName]
```