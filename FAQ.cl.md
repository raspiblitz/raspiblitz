<!-- omit in toc -->
# C-lightning on the RaspiBlitz FAQ

- [Common questions about the different Lightning Network implementations](#common-questions-about-the-different-lightning-network-implementations)
  - [Can LND and C-lightning nodes open channels to each other and route payments?](#can-lnd-and-c-lightning-nodes-open-channels-to-each-other-and-route-payments)
  - [Can I run LND and C-lightning connected to the same node?](#can-i-run-lnd-and-c-lightning-connected-to-the-same-node)
  - [Can I convert an LND node to C-lightning (or the opposite)?](#can-i-convert-an-lnd-node-to-c-lightning-or-the-opposite)
  - [Is there a table to quickly compare LND and C-Lightning?](#is-there-a-table-to-quickly-compare-lnd-and-c-lightning)
- [C-lightning official documentation](#c-lightning-official-documentation)
- [Commands and aliases](#commands-and-aliases)
- [Directories](#directories)
- [Config file](#config-file)
  - [Default values](#default-values)
  - [All possible config settings](#all-possible-config-settings)
- [Plug-ins](#plug-ins)
  - [General info](#general-info)
  - [Directories](#directories-1)
  - [Implemented plugins](#implemented-plugins)
  - [Add a custom plugin](#add-a-custom-plugin)
  - [CLBOSS](#clboss)
  - [Feeadjuster](#feeadjuster)
  - [Dual funded channels](#dual-funded-channels)
    - [Reading](#reading)
    - [Setting up](#setting-up)
    - [Open a dual funded channel](#open-a-dual-funded-channel)
    - [Fundchannel syntax](#fundchannel-syntax)
  - [Offers](#offers)
  - [About the feature bits](#about-the-feature-bits)
- [Testnets](#testnets)
- [Backups](#backups)
  - [Seed](#seed)
  - [How to display the hsm_secret in a human-readable format?](#how-to-display-the-hsm_secret-in-a-human-readable-format)
  - [Channel database](#channel-database)
  - [Recovery](#recovery)
    - [Recover from a cl-rescue file](#recover-from-a-cl-rescue-file)
    - [Recover from a seed](#recover-from-a-seed)
    - [Rescan the chain after restoring a used c-lightning wallet](#rescan-the-chain-after-restoring-a-used-c-lightning-wallet)
- [Update](#update)
  - [Update to a new C-lightning release](#update-to-a-new-c-lightning-release)
  - [Experimental update to the latest master](#experimental-update-to-the-latest-master)
- [sqlite3 queries](#sqlite3-queries)
- [Script file help list](#script-file-help-list)

---
## Common questions about the different Lightning Network implementations

### Can LND and C-lightning nodes open channels to each other and route payments?
* Yes, all [BOLT specification](https://github.com/lightningnetwork/lightning-rfc) compliant implementations can open channels to each other and route payments.

### Can I run LND and C-lightning connected to the same node?
* Yes, both can run parallel on a RaspiBlitz and even have channels witch each other.

### Can I convert an LND node to C-lightning (or the opposite)?
* No, currently there are no tools available to convert between the databases storing the channel states.  
The channels would need to be closed to use the same funds in an other node.

### Is there a table to quickly compare LND and C-Lightning?
* see [github.com/openoms/lightning-node-management/blob/master/node-types/comparison.md](https://github.com/openoms/lightning-node-management/blob/master/node-types/comparison.md)

---

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
* Edit in the menu `SYSTEM` - `CLNCONF` or use the alias `clconf`

### Default values
* on the RaspiBlitz for mainnet
  ```
  network=bitcoin
  log-file=cl.log
  log-level=info
  plugin-dir=/home/bitcoin/cln-plugins-enabled
  # Tor settings
  proxy=127.0.0.1:9050
  bind-addr=127.0.0.1:9736
  addr=statictor:127.0.0.1:9051/torport=9736
  always-use-proxy=true
  ```
### All possible config settings
  *  can be shown by running:   
  `lightningd --help`  
  * To persist the setings place the options in the config file without the `--` and restart lightningd
    ```
    Usage: lightningd 
    A bitcoin lightning daemon (default values shown for network: bitcoin).
    --conf=<file>                                     Specify configuration file
    --lightning-dir=<dir>                             Set base directory: network-specific subdirectory is
                                                    under here (default: "/home/admin/.lightning")
    --network <arg>                                   Select the network parameters (bitcoin, testnet,
                                                    signet, regtest, litecoin or litecoin-testnet)
                                                    (default: bitcoin)
    --mainnet                                         Alias for --network=bitcoin
    --testnet                                         Alias for --network=testnet
    --signet                                          Alias for --network=signet
    --allow-deprecated-apis <arg>                     Enable deprecated options, JSONRPC commands, fields,
                                                    etc. (default: true)
    --rpc-file <arg>                                  Set JSON-RPC socket (or /dev/tty)
                                                    (default: "lightning-rpc")
    --plugin <arg>                                    Add a plugin to be run (can be used multiple times)
    --plugin-dir <arg>                                Add a directory to load plugins from (can be used
                                                    multiple times)
    --clear-plugins                                   Remove all plugins added before this option
    --disable-plugin <arg>                            Disable a particular plugin by filename/name
    --important-plugin <arg>                          Add an important plugin to be run (can be used multiple
                                                    times). Die if the plugin dies.
    --always-use-proxy <arg>                          Use the proxy always (default: false)
    --daemon                                          Run in the background, suppress stdout/stderr
    --wallet <arg>                                    Location of the wallet database.
    --large-channels|--wumbo                          Allow channels larger than 0.16777215 BTC
    --experimental-dual-fund                          experimental: Advertise dual-funding and allow peers to
                                                    establish channels via v2 channel open protocol.
    --experimental-onion-messages                     EXPERIMENTAL: enable send, receive and relay of onion
                                                    messages
    --experimental-offers                             EXPERIMENTAL: enable send and receive of offers (also
                                                    sets experimental-onion-messages)
    --experimental-shutdown-wrong-funding             EXPERIMENTAL: allow shutdown with alternate txids
    --help|-h                                         Print this message.
    --rgb <arg>                                       RRGGBB hex color for node
    --alias <arg>                                     Up to 32-byte alias for node
    --pid-file=<file>                                 Specify pid file
                                                    (default: "/home/admin/.lightning/lightningd-bitcoin.pid")
    --ignore-fee-limits <arg>                         (DANGEROUS) allow peer to set any feerate
                                                    (default: false)
    --watchtime-blocks <arg>                          Blocks before peer can unilaterally spend funds
                                                    (default: 144)
    --max-locktime-blocks <arg>                       Maximum blocks funds may be locked for (default: 2016)
    --funding-confirms <arg>                          Confirmations required for funding transaction
                                                    (default: 3)
    --cltv-delta <arg>                                Number of blocks for cltv_expiry_delta (default: 34)
    --cltv-final <arg>                                Number of blocks for final cltv_expiry (default: 18)
    --commit-time=<millseconds>                       Time after changes before sending out COMMIT
                                                    (default: 10)
    --fee-base <arg>                                  Millisatoshi minimum to charge for HTLC (default: 1000)
    --rescan <arg>                                    Number of blocks to rescan from the current head, or
                                                    absolute blockheight if negative (default: 15)
    --fee-per-satoshi <arg>                           Microsatoshi fee for every satoshi in HTLC
                                                    (default: 10)
    --max-concurrent-htlcs <arg>                      Number of HTLCs one channel can handle concurrently.
                                                    Should be between 1 and 483 (default: 30)
    --min-capacity-sat <arg>                          Minimum capacity in satoshis for accepting channels
                                                    (default: 10000)
    --addr <arg>                                      Set an IP address (v4 or v6) to listen on and announce
                                                    to the network for incoming connections
    --bind-addr <arg>                                 Set an IP address (v4 or v6) to listen on, but not
                                                    announce
    --announce-addr <arg>                             Set an IP address (v4 or v6) or .onion v3 to announce,
                                                    but not listen on
    --offline                                         Start in offline-mode (do not automatically reconnect
                                                    and do not accept incoming connections)
    --autolisten <arg>                                If true, listen on default port and announce if it
                                                    seems to be a public interface (default: true)
    --proxy <arg>                                     Set a socks v5 proxy IP address and port
    --tor-service-password <arg>                      Set a Tor hidden service password
    --experimental-accept-extra-tlv-types <arg>       Comma separated list of extra TLV types to accept.
    --disable-dns                                     Disable DNS lookups of peers
    --encrypted-hsm                                   Set the password to encrypt hsm_secret with. If no
                                                    password is passed through command line, you will be
                                                    prompted to enter it.
    --rpc-file-mode <arg>                             Set the file mode (permissions) for the JSON-RPC socket
                                                    (default: "0600")
    --force-feerates <arg>                            Set testnet/regtest feerates in sats perkw,
                                                    opening/mutual_close/unlateral_close/delayed_to_us/htlc_resolution/penalty:
                                                    if fewer specified, last number applies to remainder
    --subdaemon <arg>                                 Arg specified as SUBDAEMON:PATH. Specifies an alternate
                                                    subdaemon binary. If the supplied path is relative the
                                                    subdaemon binary is found in the working directory.
                                                    This option may be specified multiple times. For
                                                    example, --subdaemon=hsmd:remote_signer would use a
                                                    hypothetical remote signing subdaemon.
    --log-level <arg>                                 log level (io, debug, info, unusual, broken) [:prefix]
                                                    (default: info)
    --log-timestamps <arg>                            prefix log messages with timestamp (default: true)
    --log-prefix <arg>                                log prefix (default: lightningd)
    --log-file=<file>                                 log to file instead of stdout
    --version|-V                                      Print version and exit
    --autocleaninvoice-cycle <arg>                    Perform cleanup of expired invoices every given
                                                    seconds, or do not autoclean if 0
    --autocleaninvoice-expired-by <arg>               If expired invoice autoclean enabled, invoices that
                                                    have expired for at least this given seconds are
                                                    cleaned
    --fetchinvoice-noconnect                          Don't try to connect directly to fetch an invoice.
    --bitcoin-datadir <arg>                           -datadir arg for bitcoin-cli
    --bitcoin-cli <arg>                               bitcoin-cli pathname
    --bitcoin-rpcuser <arg>                           bitcoind RPC username
    --bitcoin-rpcpassword <arg>                       bitcoind RPC password
    --bitcoin-rpcconnect <arg>                        bitcoind RPC host to connect to
    --bitcoin-rpcport <arg>                           bitcoind RPC host's port
    --bitcoin-retry-timeout <arg>                     how long to keep retrying to contact bitcoind before
                                                    fatally exiting
    --commit-fee <arg>                                Percentage of fee to request for their commitment
    --funder-policy <arg>                             Policy to use for dual-funding requests. [match,
                                                    available, fixed]
    --funder-policy-mod <arg>                         Percent to apply policy at (match/available); or amount
                                                    to fund (fixed)
    --funder-min-their-funding <arg>                  Minimum funding peer must open with to activate our
                                                    policy
    --funder-max-their-funding <arg>                  Maximum funding peer may open with to activate our
                                                    policy
    --funder-per-channel-min <arg>                    Minimum funding we'll add to a channel. If we can't
                                                    meet this, we don't fund
    --funder-per-channel-max <arg>                    Maximum funding we'll add to a channel. We cap all
                                                    contributions to this
    --funder-reserve-tank <arg>                       Amount of funds we'll always leave available.
    --funder-fuzz-percent <arg>                       Percent to fuzz the policy contribution by. Defaults to
                                                    5%. Max is 100%
    --funder-fund-probability <arg>                   Percent of requests to consider. Defaults to 100%.
                                                    Setting to 0% will disable dual-funding
    --funder-lease-requests-only <arg>                Only fund lease requests. Defaults to true if channel
                                                    lease rates are being advertised
    --lease-fee-base-msat <arg>                       Channel lease rates, base fee for leased funds, in
                                                    satoshi.
    --lease-fee-basis <arg>                           Channel lease rates, basis charged for leased funds
                                                    (per 10,000 satoshi.)
    --lease-funding-weight <arg>                      Channel lease rates, weight we'll ask opening peer to
                                                    pay for in funding transaction
    --channel-fee-max-base-msat <arg>                 Channel lease rates, maximum channel fee base we'll
                                                    charge for funds routed through a leased channel.
    --channel-fee-max-proportional-thousandths <arg>  Channel lease rates, maximum proportional fee (in
                                                    thousandths, or ppt) we'll charge for funds routed
                                                    through a leased channel. Note: 1ppt = 1,000ppm
    --disable-mpp                                     Disable multi-part payments.
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
* [CLBOSS](#clboss)
* [feeadjuster](#feeadjuster)

### Add a custom plugin
* Place the plugin in the `/home/bitcoin/cl-plugins-enabled` directory 
* Make sure it is owned by the `bitcoin` user and is executable:
    ```
    sudo chown bitcoin:bitcoin /home/bitcoin/cl-plugins-enabled/PLUGIN_NAME
    sudo chmod +x /home/bitcoin/cl-plugins-enabled/PLUGIN_NAME
    ```
* start with
    ```
    lightnign-cli plugin start /home/bitcoin/cl-plugins-enabled/PLUGIN_NAME
    ```
* or to load it automatically on restart:
    ```
    sudo systemctl restart lightningd
    ```
    From the directory `/home/bitcoin/cl-plugins-enabled` it will load auomatically after restarts.
* To just load it run it once store in (and start from):  
    `/home/bitcoin/cl-plugins-available/`

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

* Activate it in the menu - `SETTINGS` - `-CL CLBOSS`
* Discussion: https://github.com/rootzoll/raspiblitz/issues/2490
* Advanced usage
https://github.com/ZmnSCPxj/clboss#clboss-status  
* Stopping CLBOSS will leave the node in the last state. No channels will be closed or funds removed when CLBOSS is uninstalled.

### Feeadjuster

* Install:
`config.scripts/cl-plugin.feeadjuster.sh on`

* to set the default fees add to the C-lightning `config` file:
  ```
  fee-base=BASEFEE_IN_MILLISATS
  fee-per-satoshi=PPM_FEE_IN_SATS
  ```
* more options for the feeadjuster to be set in the c-lightning config can be seen in the [code](https://github.com/lightningd/plugins/blob/c16c564c2c5549b8f7236815490260c49e9e9bf4/feeadjuster/feeadjuster.py#L318): 
    ```
    plugin.add_option(
        "feeadjuster-deactivate-fuzz",
        False,
        "Deactivate update threshold randomization and hysterisis.",
        "flag"
    )
    plugin.add_option(
        "feeadjuster-deactivate-fee-update",
        False,
        "Deactivate automatic fee updates for forward events.",
        "flag"
    )
    plugin.add_option(
        "feeadjuster-threshold",
        "0.05",
        "Relative channel balance delta at which to trigger an update. Default 0.05 means 5%. "
        "Note: it's also fuzzed by 1.5%",
        "string"
    )
    plugin.add_option(
        "feeadjuster-threshold-abs",
        "0.001btc",
        "Absolute channel balance delta at which to always trigger an update. "
        "Note: it's also fuzzed by 1.5%",
        "string"
    )
    plugin.add_option(
        "feeadjuster-enough-liquidity",
        "0msat",
        "Beyond this liquidity do not adjust fees. "
        "This also modifies the fee curve to achieve having this amount of liquidity. "
        "Default: '0msat' (turned off).",
        "string"
    )
    plugin.add_option(
        "feeadjuster-adjustment-method",
        "default",
        "Adjustment method to calculate channel fee"
        "Can be 'default', 'soft' for less difference or 'hard' for higher difference"
        "string"
    )
    plugin.add_option(
        "feeadjuster-imbalance",
        "0.5",
        "Ratio at which channel imbalance the feeadjuster should start acting. "
        "Default: 0.5 (always). Set higher or lower values to limit feeadjuster's "
        "activity to more imbalanced channels. "
        "E.g. 0.3 for '70/30'% or 0.6 for '40/60'%.",
        "string"
    )
    plugin.add_option(
        "feeadjuster-feestrategy",
        "global",
        "Sets the per channel fee selection strategy. "
        "Can be 'global' to use global config or default values, "
        "or 'median' to use the median fees from peers of peer "
        "Default: 'global'.",
        "string"
    ```

* start the feeadjuster
    ```
    cl plugin start /home/bitcoin/cl-plugins-available/plugins/feeadjuster/feeadjuster.py
    ```
* stop (best to run only periodically)
    ```
    cl plugin stop /home/bitcoin/cl-plugins-available/plugins/feeadjuster/feeadjuster.py
    ```
* Can use menu - `CL` - `SUEZ` to visualize the channel balances and fee settings
* check the list of base fees
    ```
    cl listpeers | grep fee_base_msat
    ```
* check the list of proportional fees
    ```
    cl listpeers | grep fee_proportional_millionths
    ```
* set the fees to the defaults
    ```
    cl setchannelfee all
    ```

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

#### Open a dual funded channel
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
#### Fundchannel syntax
*  the amount is the own funds in the wallet contributed  
use equal amounts to have a balanced channel from start  
the amounts can be specified in `sat` or `btc`
    ```
    lightning-cli fundchannel -k id=NODE_ID amount=OWN_AMOUNTsat request_amt=PEER_CONTRIBUTION_AMOUNTsat compact_lease=COMPACT_LEASE
    ```  
    It can fail if the offer changed or there are not enough funds available on either side.

* open a dual funded channel with a chosen utxo and miner feerate  
list the utxo-s with `lightning-cli listfunds`, can list multiple  
the feerate is in `perkb` by default, e.g. use 1000 for 1 sat/byte
    ```
    lightning-cli fundchannel feerate=PERKB_FEERATE utxos='["TRANSACTION_ID:INDDEX_NUMBER"]' -k id=NODE_ID amount=OWN_AMOUNTsat request_amt=PEER_CONTRIBUTION_AMOUNTsat compact_lease=COMPACT_LEASE
    ```

### Offers
* Details at bolt12.org
* Create an offer to receive payments:  
https://lightning.readthedocs.io/lightning-offer.7.html
    ```
    lightning-cli offer amount description [vendor] [label] [quantity_min] [quantity_max] [absolute_expiry] [recurrence] [recurrence_base] [recurrence_paywindow] [recurrence_limit] [single_use]
    ```
* Example:  
Create a reusable offer which can be paid with any amount for LN tips using a fixed string.
    ```
    lightning-cli offer any tip
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
* see if there is a new invoice is paid with:
    ```
    lightning-cli listinvoices
    ```
    The `pay_index` will increase as the offer gets reused.

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
* https://lightning.readthedocs.io/FAQ.html#how-to-backup-my-wallet
* General details: https://lightning.readthedocs.io/BACKUP.html

### Seed
* By default a BIP39 wordlist compatible, 24 words seed is used to generate the `hsm_secret`
* If the wallet was generated or restored from seed on a RaspiBlitz the seed is stored in the disk with the option to encrypt 
* Display the seed from the menu - `CL` - `SEED`
* The file where the seed is stored (until encrypted) is on the disk: `/home/bitcoin/.lightning/bitcoin/seedwords.info`
* Show manually with:  
`sudo cat /home/bitcoin/.lightning/bitcoin/seedwords.info`
* If there is no such file and you have not funded the C-lightning wallet yet can reset the wallet and the next wallet will be created with a seed.
### How to display the hsm_secret in a human-readable format?
* If there is no seed available it is best to save the hsm_secret as a file with `scp`.
To display it as text:
    ```
    sudo cat /home/bitcoin/.lightning/bitcoin/hsm_secret | xxd
    ```

### Channel database
* Stored on the disk and synchronised to the SDcard with the help of the `backup` plugin.

### Recovery
* https://lightning.readthedocs.io/FAQ.html#database-corruption-channel-state-lost
* https://lightning.readthedocs.io/FAQ.html#loss
 
#### Recover from a cl-rescue file
* use the `REPAIR-CL` - `FILERESTORE` option in the menu for instructions to upload

#### Recover from a seed
* use the `REPAIR-CL` - `SEEDRESTORE` option in the menu for instructions to paste the seedwords to restore

#### Rescan the chain after restoring a used c-lightning wallet
* https://lightning.readthedocs.io/FAQ.html#rescanning-the-block-chain-for-lost-utxos
* Stop `lightningd`:
    ```
    sudo systemctl stop lightningd
    ```
    An ungraceful method:
    ```
    sudo killall ligthningd
* Rescan from the block 700000
    ```
    sudo -u bitcoin lightningd --rescan -700000 --log-level debug
    ```
* Rescan the last 1000 blocks:
    ```
    sudo -u bitcoin lightningd --rescan 1000 --log-level debug
    ```
* can monitor in a new window using the shortcut:
    ```
    cllog
    ```

## Update
### Update to a new C-lightning release
* See the tagged releases by the C-lightning team: [github.com/ElementsProject/lightning/releases](https://github.com/ElementsProject/lightning/releases)
* Will be able to update to new releases from the menu - `UPDATE` - `CL`
* Since downgrading the lightning database is not allowed the updated version will persist if the SDcard is reflashed.

### Experimental update to the latest master
* this won't persist in case the SDcard is reflashed so will need to manually update again. 
* the commadn to use the built-in script to update to the lates commit in the default branch is:
    ```
    config.scripts/cl.install.sh update
    ```
* if the database version is not compatible with the default version after a downgrade there will be an error message in `sudo journalctl -u lightningd` similar to:
    ```
    Refusing to migrate down from version 178 to 176
    ```
* in this case update to the next release from the menu or the latest master again with:
    ```
    config.scripts/cl.install.sh update
    ```

## sqlite3 queries
* Query the reasons for force closes
    ```
    sudo -u bitcoin sqlite3 /home/bitcoin/.lightning/bitcoin/lightningd.sqlite3 'select short_channel_id, timestamp, cause, message from channel_state_changes inner join channels on channel_id = id where new_state = 7 order by timestamp'
    ```
* Query the reasons for cooperative channel closes
    ```
    sudo -u bitcoin sqlite3 /home/bitcoin/.lightning/bitcoin/lightningd.sqlite3 'select short_channel_id, timestamp, cause, message from channel_state_changes inner join channels on channel_id = id where new_state = 4 order by timestamp'
    ```

## Script file help list
* generate a list of the help texts on a RaspiBlitz:
    ```
    cd /home/admin/config.scripts/
    ls cl*.sh > clScriptList.txt
    sed -i 's#^#./#g' clScriptList.txt
    sed -i 's#.sh#.sh -h#g' clScriptList.txt
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

+ ./cl.check.sh -h

# script to check CL states
# cl.check.sh basic-setup
# cl.check.sh prestart [mainnet|testnet|signet]

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

+ ./cl-plugin.feeadjuster.sh -h

Install the feeadjuster plugin for C-lightning
Usage:
cl-plugin.feeadjuster.sh [on|off] <testnet|mainnet|signet>

+ ./cl-plugin.http.sh -h

Install, remove, connect the c-lightning-http-plugin
version: 1dbb6537e0ec5fb9b8edde10db6b4cc613ccdb19
Implemented for mainnet only.
Usage:
cl-plugin.http.sh [on|off|connect] <norestart>

+ ./cl-plugin.sparko.sh -h

Install, remove, connect or get info about the Sparko plugin for C-lightning
version: v2.7
Usage:
cl-plugin.sparko.sh [on|off|menu|connect] [testnet|mainnet|signet] [norestart]

+ ./cl-plugin.standard-python.sh -h

Install and show the output of the chosen plugin for C-lightning
Usage:
cl-plugin.standard-python.sh on [plugin-name] <testnet|mainnet|signet> <persist|runonce>

tested plugins:
summary | helpme | feeadjuster | paytest

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

+ ./cl.spark.sh -h

Install, remove or get info about the Spark Wallet for C-lightning
version: v0.3.0rc
Usage:
cl.spark.sh [on|off|menu] <testnet|mainnet|signet> 

+ ./cl.update.sh -h

Interim optional C-lightning updates between RaspiBlitz releases.
cl.update.sh [info|verified|reckless]
info -> get actual state and possible actions
verified -> only do recommended updates by RaspiBlitz team
  binary will be checked by signature and checksum
reckless -> if you just want to update to the latest release
  published on C-lightning GitHub releases (RC or final) without any
  testing or security checks.

```
