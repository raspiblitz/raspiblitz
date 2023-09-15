## What's new in Version 1.10.0 of RaspiBlitz?

- Update: RaspiOS base image from 2023-05-03
- Update: Bitcoin Core v25.0.0 [details](https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-25.0.md)
- Update: LND v0.16.4-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.16.4-beta)
- Update: Core Lightning v23.08.1 [details](https://github.com/ElementsProject/lightning/releases/tag/v23.08.1)
- Update: Suez - Channel Visualization for LND & CLN [details](https://github.com/prusnak/suez)
- Update: Electrum Server in Rust (electrs) v0.10.0 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#0100-jul-22-2023)
- Update: C-lightningREST v0.10.5 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.10.5)
- Update: RTL v0.14.0 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.14.0)
- Update: Lightning Terminal v0.10.1-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.10.1-alpha)
- Update: Channel Tools (chantools) v0.11.3 [details](https://github.com/guggero/chantools/releases/tag/v0.11.3)
- Update: LNDg v1.7.0 [details](https://github.com/cryptosharks131/lndg)
- Update: Thunderhub v0.13.19 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.19)
- Update: LNbits 0.10.9 [details](https://github.com/lnbits/lnbits/releases/tag/0.10.9)
- Update: BTCPayServer 1.10.3 (postgres by default with sqlite migration) [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.10.3)
- Update: Specter Desktop 1.13.1 [details](https://github.com/cryptoadvance/specter-desktop/releases/tag/v1.13.1)
- Update: Kindle-Display 0.5.1 [details](https://github.com/dennisreimann/kindle-display/)
- Update: JoinMarket v0.9.10 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.10)
- Update: JoininBox v0.8.1 [details](https://github.com/openoms/joininbox/releases/tag/v0.8.1)
- Update: Balance of Satoshis 15.11.0 (bos) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#15110)
- Fix: Homebanking Interface FinTS/HBCI (experimental) [details](https://github.com/rootzoll/raspiblitz/issues/1186)
- Remove: Spark Wallet and Sparko CLN plugin (not maintained anymore)
- Remove: Faraday, Loop, Pool single installs - used in the LiT package instead
- Remove: deactivate LNproxy in the menu and in provision
- Info: the users not intended to be logged in will not be available to change into (manage them from admin with sudo)

## What's new in Version 1.9.0 of RaspiBlitz?

- New: Automated disk image build for amd64 (VM, laptop, desktop, server) and arm64-rpi (Raspberry Pi) [details](https://github.com/rootzoll/raspiblitz/tree/dev/ci/README.md)
- New: Fatpack & Minimal sd card builds [details](SECURITY.md#minimal-sd-card-build)
- New: I2P support for Bitcoin Core (i2pacceptincoming=1) [details](https://github.com/rootzoll/raspiblitz/issues/2413)
- New: CLN Watchtower (The Eye of Satoshi) [details](https://github.com/talaia-labs/rust-teos/tree/master/watchtower-plugin)
- New: LNDg v1.6.0 [details](https://github.com/cryptosharks131/lndg)
- New: Support of X708 UPS HAT [details](https://github.com/rootzoll/raspiblitz/pull/3087)
- New: BOS Telegram Bot Support (see OPTIONS on LND Balance of Satoshis menu entry)
- New: LightningTipBot v0.5 [details](https://github.com/LightningTipBot/LightningTipBot)
- New: ↬lnproxy cli shortcut and server [details](https://github.com/lnproxy)
- New: Homebanking Interface FinTS/HBCI (experimental) [details](https://github.com/rootzoll/raspiblitz/issues/1186)
- New on WebUI: Jam (JoinMarket Web UI) v0.1.5 [details](https://github.com/joinmarket-webui/joinmarket-webui/releases/tag/v0.1.5)
- New on WebUI: Generate/Download Debug Report from Settings
- Update: Bitcoin Core v24.0.1 [details](https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-24.0.1.md)
- Update: LND v0.16.2-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.16.2-beta)
- Update: Core Lightning v23.02.2 [details](https://github.com/ElementsProject/lightning/releases/tag/v23.02.2)
- Update: C-lightningREST v0.10.2 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.10.2)
- Update: Electrum Server in Rust (electrs) v0.9.11 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#0911-jan-5-2023)
- Update: Lightning Terminal v0.9.2-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.9.2-alpha)
- Update: RTL v0.13.6 with update option [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.13.6)
- Update: Thunderhub v0.13.16 with balance sharing disabled [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.16)
- Update: LNbits 0.10.6 [details](https://github.com/lnbits/lnbits/releases/tag/0.10.6)
- Update: BTCPayServer 1.9.3 (postgres by default with sqlite migration) [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.9.3)
- Update: ItchySats 0.7.0 [details](https://github.com/itchysats/itchysats/releases/tag/0.7.0)
- Update: Channel Tools (chantools) v0.10.5 [details](https://github.com/guggero/chantools/releases/tag/v0.10.5)
- Update: JoinMarket v0.9.9 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.9)
- Update: JoininBox v0.7.7 [details](https://github.com/openoms/joininbox/releases/tag/v0.7.7)
- Update: Balance of Satoshis 13.15.0 (bos) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#13150)
- Update: lndmanage 0.15.0 [details](https://github.com/bitromortac/lndmanage)
- Update: Circuitbreaker with webUI [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- Update: Suez - Channel Visualization for LND & CL [details](https://github.com/prusnak/suez)
- Update: Tallycoin Connect v1.8.0 [details](https://github.com/djbooth007/tallycoin_connect/releases/tag/v1.8.0)
- Update: Fulcrum install script (CLI only) v1.9.1 [details](https://github.com/cculianu/Fulcrum/releases/tag/v1.9.1)
- Fixed: SCB/Emergency-Backup to USB drive (now also with CLN emergency.recover file)
- Info: Run RaspiBlitz on Proxmox [details](https://github.com/rootzoll/raspiblitz/tree/dev/alternative.platforms/Proxmox)
- Info: IP2Tor fix fulmo shop & added new ip2tor.com shop
- Info: 32GB sdcard is now enforced (after being recommended since v1.5)
- Info: 'Reindex Blockchain' is now part of 'repair' menu

## What's new in Version 1.8.0c of RaspiBlitz?

- Update: LND v0.15.4 (emergency hotfix release) [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.15.4-beta)
- Update: Electrum Server in Rust (electrs) v0.9.9 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#099-jul-12-2022)

## What's new in Version 1.8.0b of RaspiBlitz?

- Update: LND v0.15.2 (emergency hotfix release) [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.15.2-beta)

## What's new in Version 1.8.0 of RaspiBlitz?

- New: Multilanguage WebUI [details](https://github.com/cstenglein/raspiblitz-web)
- New: BackendAPI [details](https://github.com/fusion44/blitz_api)
- New: ZRAM - compressed swap in memory [details](https://github.com/rootzoll/raspiblitz/issues/2905)
- New: Core Lightning GRPC plugin [details](https://github.com/rootzoll/raspiblitz/pull/3109)
- New: Core Lightning connection to BTCPayServer (CONNECT menu) [details](https://github.com/rootzoll/raspiblitz/issues/3155)
- New: Alby (Connection Menu) [details](https://getalby.com/)
- New: Homer Dashboard 22.06.1 [details](https://github.com/bastienwirtz/homer#readme)
- New: ItchySats 0.5.0 [details](https://github.com/itchysats/itchysats/)
- New: ckbunker CLI install script (experimental) [details](https://github.com/rootzoll/raspiblitz/issues/1062)
- Update: Bitcoin Core v23.0 [details](https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-23.0.md)
- Update: Core Lightning (CLN - formerly C-lightning) v0.11.2 [details](https://github.com/ElementsProject/lightning/releases/tag/v0.11.2)
- Update: LND v0.15.0 [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.15.0-beta)
- Update: RTL v0.12.3 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.12.3)
- Update: LNbits 0.9.1 [details](https://github.com/lnbits/lnbits-legend/releases/tag/0.9.1)
- Update: C-lightningREST v0.7.2 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.7.2)
- Update: CLBOSS 0.13A [details](https://github.com/ZmnSCPxj/clboss/releases/tag/0.13A)
- Update: Channel Tools (chantools) v0.10.4 [details](https://github.com/guggero/chantools/blob/master/README.md)
- Update: Lightning Terminal v0.9.2-alpha with Lightning Node Connect over Tor [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.9.2-alpha)
- Update: JoinMarket v0.9.6 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.6)
- Update: JoininBox v0.6.8 [details](https://github.com/openoms/joininbox/releases/tag/v0.6.8)
- Update: JoinMarket Web UI (Jam) v0.0.9 (CLI install script) [details](https://github.com/joinmarket-webui/joinmarket-webui/releases/tag/v0.0.9)
- Update: Electrum Server in Rust (electrs) v0.9.7 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#097-apr-30-2022)
- Update: Fulcrum Electrum server v1.7.0 (CLI install script) [issue](https://github.com/rootzoll/raspiblitz/issues/2924)
- Update: BTCPayServer 1.6.1 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.6.1)
- Update: Mempool 2.4.0 [details](hhttps://github.com/mempool/mempool/releases/tag/v2.4.0)
- Update: Helipad (Podcasting 2.0 Boostagram reader) v0.1.10 [details](https://github.com/Podcastindex-org/helipad/releases/tag/v0.1.10)
- Update: Adapted Umbrel Migration for new 0.5.0 version with Core Lightning
- Info: Run RaspiBlitz on amd64 bare metal and virtual machines [details](https://github.com/rootzoll/raspiblitz/tree/dev/alternative.platforms)

## What's new in Version 1.7.2 of RaspiBlitz?

- Refactor: Cache & Backgroundscan of Systeminfo
- New: Compact the LND channel.db monthly on restart, on-demand from menu and before backups [issue](https://github.com/rootzoll/raspiblitz/issues/2752)
- New: Run C-lightning backup-compact regularly [issue](https://github.com/rootzoll/raspiblitz/issues/2869)
- New: Switch LNbits between lnd & c-lightning [issue](https://github.com/rootzoll/raspiblitz/issues/2556)
- New: Tallycoin Connect [details](https://github.com/djbooth007/tallycoin_connect#readme)
- New: Helipad (Podcasting 2.0 Boostagram reader) [details](https://github.com/Podcastindex-org/helipad)
- New: Migration from Citadel to RaspiBlitz [details](https://github.com/rootzoll/raspiblitz/issues/2642)
- New: Bitcoinminds.org local on RaspiBlitz [details](https://github.com/raulcano/bitcoinminds)
- New: JoinMarket Web UI v0.0.3 (CLI install of the first public alpha release) [details](https://github.com/joinmarket-webui/joinmarket-webui/releases/tag/v0.0.3)
- New: Fulcrum Electrum server v1.6.0 (CLI install script) [issue](https://github.com/rootzoll/raspiblitz/issues/2924)
- Update: LND v0.14.2-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.14.2-beta)
- Update: C-lightning v0.10.2 [details](https://github.com/ElementsProject/lightning/releases/tag/v0.10.2)
- Update: LNbits 0.7.0 [details](https://github.com/lnbits/lnbits-legend/releases/tag/0.7.0)
- Update: RTL v0.12.1 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.12.1)
- Update: C-lightningREST v0.6.1 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.6.1)
- Update: CL Spark Wallet v0.3.1 [details](https://github.com/shesek/spark-wallet/releases/tag/v0.3.1)
- Update: CL Sparko plugin v0.2.8 [details](https://github.com/fiatjaf/sparko/releases/tag/v2.8)
- Update: Lightning Terminal v0.6.3-alpha with Lightning Node Connect over Tor [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.6.3-alpha)
- Update: Channel Tools (chantools) v0.10.1 [details](https://github.com/guggero/chantools/releases/tag/v0.10.1)
- Update: BTCPayServer v1.4.4 with UPDATE option [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.4.4)
- Update: Electrum Server in Rust (electrs) v0.9.5 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#095-feb-4-2022)
- Update: JoinMarket v0.9.5 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.5)
- Update: JoininBox v0.6.7 [details](https://github.com/openoms/joininbox/releases/tag/v0.6.7)
- Update: Thunderhub v0.13.6 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.6)
- Update: BTC-RPC-Explorer v3.3.0 [details](https://github.com/janoside/btc-rpc-explorer/blob/master/CHANGELOG.md#v330)
- Update: Specter Desktop 1.8.1 [details](https://github.com/cryptoadvance/specter-desktop/releases/tag/v1.8.1)
- Update: Mempool 2.3.1 [details](https://github.com/mempool/mempool/releases/tag/v2.3.1)
- Update: PyBlock to 1.1.8.5 (adapt to new install mechanism)
- Update: Balance of Satoshis 11.50.0 (BOS) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#11500)
- Update: Re-Add connecting node with Zap mobile wallet iOS & Android
- Update: additional redaction of private data in debug logs
- Security: Verify git commits and tags everywhere possible [issue](https://github.com/rootzoll/raspiblitz/issues/2686)
- Fixed: LND repair options, SEED+SCB and rescue-file restore, RESET options [issue](https://github.com/rootzoll/raspiblitz/issues/2832)
- Info: All existing IP2Tor subscriptions need to be canceled & renewed to be functional again.
- Info: 32GB sd card is now required (was already long time recommended on shopping list)
- Info: The touchscreen graphical mode is back to experimental for now and missing some UI fixes. This might take until v1.8.1 where the touchscreen will get a refactor/rewrite.

## What's new in Version 1.7.1 of RaspiBlitz?

There was a small patch-update with raspiblitz-v1.7.1-2021-10-28.img.gz to fix a restart-loop after blockchain was self-synced.

- New: C-lightning v0.10.1 [details](https://github.com/ElementsProject/lightning/releases/tag/v0.10.1)
- New: C-lightningREST v0.5.1 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.5.1)
- New: CL Spark Wallet v0.3.0rc with BOLT12 offers [details](https://github.com/shesek/spark-wallet/releases)
- New: CL plugin: Sparko [details](https://github.com/fiatjaf/sparko)
- New: CL plugin: CLBOSS The Core Lightning Node Manager [details](https://github.com/ZmnSCPxj/clboss#clboss-the-c-lightning-node-manager)
- New: Refactored Setup-Process [details](https://github.com/rootzoll/raspiblitz/issues/1126#issuecomment-829757665)
- New: Suez - channel visualization for LND and CL [info](https://github.com/rootzoll/raspiblitz/issues/2366#issuecomment-939521302)[details](https://github.com/prusnak/suez)
- New: LND Static Channel Backup to Nextcloud
- New: Allow SphinxApp to connect over Tor
- New: Parallel TESTNET & SIGNET services
- Update: Bitcoin Core v22.0 [details](https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-22.0.md)
- Update: LND v0.13.3 [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.13.3-beta)
- Update: Specter Desktop 1.6.0 [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- Update: JoinMarket v0.9.2 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.2)
- Update: JoininBox v0.6.1 [details](https://github.com/openoms/joininbox/releases/tag/v0.6.1)
- Update: Electrum Server in Rust (electrs) v0.9.0 [details](https://github.com/romanz/electrs/blob/v0.9.0/RELEASE-NOTES.md)
- Update: Mempool 2.2.2 [details](https://github.com/mempool/mempool)
- Update: BTC-RPC-Explorer v3.2.0 [details](https://github.com/janoside/btc-rpc-explorer/blob/master/CHANGELOG.md#v320)
- Update: stacking-sats-kraken 0.4.4 [details](https://github.com/dennisreimann/stacking-sats-kraken/blob/master/README.md)
- Update: BTCPayServer 1.2.3 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.2.3)
- Update: Lightning Terminal v0.5.1-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.5.1-alpha)
- Update: RTL 0.11.2 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.11.2)
- Update: Lightning Terminal v0.5.0-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.5.0-alpha)
- Update: Thunderhub v0.12.30 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.12.30)
- Update: Pool CLI v0.5.1-alpha [details](https://github.com/lightninglabs/pool/releases/tag/v0.5.1-alpha)
- Update: Balance of Satoshis 10.7.8 (BOS) + keep data on reinstall [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#version-8010)
- Update: Channel Tools (chantools) v0.9.3 [details](https://github.com/guggero/chantools/blob/master/README.md)
- Update: Circuitbreaker v0.3.0 [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- Remove: DropBox Backup (its recommended to change to Nextcloud Backup)
- Remove: Litecoin (fork recommended) [details](https://github.com/rootzoll/raspiblitz/issues/2542)

## What's new in Version 1.7.0 of RaspiBlitz?

- New: Raspberry Pi OS Base Image 64-bit (April 2021)
- New: Build SD card Image with parameters & FatPack [details](https://github.com/rootzoll/raspiblitz/pull/2044)
- New: Improve LND uptime and reliability over Tor [details](https://github.com/rootzoll/raspiblitz/pull/2148)
- New: Lightning Terminal v0.4.1-alpha (Loop, Pool & Faraday UI Bundle) [details](https://github.com/lightninglabs/lightning-terminal#lightning-terminal-lit)
- New: Channel Tools (chantools) v0.8.2 [details](https://github.com/guggero/chantools/blob/master/README.md)
- New: Circuitbreaker LND firewall (settings menu) [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- New: Telegraf metrics (experimental) [details](https://github.com/rootzoll/raspiblitz/issues/1369)
- New: Download whitepaper from blockchain [details](https://github.com/rootzoll/raspiblitz/pull/2017)
- New: Extended CONNECT and SYSTEM options in the ssh menu [details](https://github.com/rootzoll/raspiblitz/pull/2119)
- Update: bitcoin-core version 0.21.0-beta with UPDATE option [details](https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-0.21.0.md)
- Update: LND version 0.12.1-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.12.1-beta)
- Update: RTL 0.10.1 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.10.1)
- Update: Sphinx-Relay 2.0.11 (always latest release tag & improved connection dialog)
- Update: Thunderhub 0.12.13 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.12.12)
- Update: Electrs 0.8.9 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#088-22-feb-2021)
- Update: BTCPayServer 1.0.7.2 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.7.2)
- Update: Specter Desktop 1.3.0 [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- Update: Balance of Satoshis 8.0.5 (BOS) with CLI autocompletion [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#version-802)
- Update: Faraday v0.2.3-alpha [details](https://github.com/lightninglabs/faraday/releases/tag/v0.2.3-alpha)
- Update: JoinMarket 0.8.2 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.8.2)
- Update: JoininBox 0.3.4 [details](https://github.com/openoms/joininbox/releases/tag/v0.3.2)
- Update: mempool v2.1.2 [detail](https://github.com/mempool/mempool/releases/tag/v2.1.2)
- Update: BTC-RPC-Explorer v3.0.0 [details](https://github.com/janoside/btc-rpc-explorer/blob/master/CHANGELOG.md#v300)
- Update: stacking-sats-kraken 0.4.2 [details](https://github.com/dennisreimann/stacking-sats-kraken/blob/master/README.md)

## What's new in Version 1.6.3 of RaspiBlitz?

- Update: mempool space 2.0.1 [details](https://github.com/mempool/mempool)
- Update: specter 1.0.0
- Update: RTL 0.10.0 [details](https://twitter.com/RTL_App/status/1340815355959267329?s=20)
- Update: btcpay v1.0.6.3
- Update: NodeJS v14.15.4
- Update: pool v0.3.4
- Update: joininbox v0.1.16
- Update: Sphinx Relay Server (installs always latest master)
- Fix: circuitbreaker install on recovery
- Fix: Specter Persistence
- Experimental: MENU > LNDCRED > EXPORT > BTCPAY Server connection string with baked macaroon

## What's new in Version 1.6.2 of RaspiBlitz?

- New: Pool (Inbound Liquidity Marketplace) [details](https://github.com/lightninglabs/pool/blob/master/README.md)
- New: Sphinx Relay Server [details](https://github.com/stakwork/sphinx-relay/blob/master/README.md)
- Update: LNbits (Lightning Vouchers)
- Update: Joinmarket 0.8.0 (bech32 orderbook)
- Update: JoinInBox 0.1.15
- Update: LN Balance Script
- Update: Thunderhub 0.10.4
- Update: RTL 0.9.3
- Update: EletcRS 0.8.6
- Update: Specter 0.10.0
- Update: BTCPay Server 1.0.5.9 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.5.9)
- Update: Loop 0.11.1
- Update: stacking-sats-kraken 0.3.0
- Update: Experimental BTRFS support
- Fix: DropBox API

## What's new in Version 1.6.1 of RaspiBlitz?

- EMERGENCY-Update: LND version 0.11.1-beta [details](https://lists.linuxfoundation.org/pipermail/lightning-dev/2020-October/002819.html)
- Update: IP2Tor+LetsEncrypt Functional Test [details](https://github.com/rootzoll/raspiblitz/issues/1412)
- Update: JoininBox 0.1.12 (terminal based GUI for JoinMarket) [details](https://github.com/openoms/joininbox)
- Update: BTCPayServer v1.0.5.8 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.5.8)
- Update: RTL 0.9.1
- Update: lndmanage 0.11.0
- Update: Specter 0.8.1 (with running the numbers)
- Update: Balance of Satoshi 6.1.0
- Update: Thunderhub 0.9.14
- Update: Loop 0.8.1
- Update: Faraday 0.2.1
- Update: Improved IPv6 support
- Update: LNbits new Quart-Framework install
- New: Circuit Breaker (config-script) [details](https://github.com/rootzoll/raspiblitz/issues/1581)
- New: PyBlock (Python Util & Fun Scripts) [details](https://github.com/curly60e/pyblock/blob/master/README.md)
- New: Mempool Explorer [details](https://github.com/mempool/mempool)
- New: dynu.com as alternative option for LetsEncrypt FreeDNS provider
- New: Experimental running RaspiBlitz as VM (vagrant & docker)

For ALL small bug fixes & improvements see: https://github.com/rootzoll/raspiblitz/milestone/11

## What's new in Version 1.6 of RaspiBlitz?

- Update: Raspberry Pi OS Base Image (May 2020)
- Update: bitcoin-core version 0.20.0-beta [details](https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/)
- Update: litecoin version 0.18.1-beta [details](https://blog.litecoin.org/litecoin-core-v0-18-1-release-233cabc26440)
- Update: LND version 0.10.4-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.10.4-beta)
- Update: Specter Desktop 0.5.5 [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- Update: Loop 0.6.5 [details](https://lightning.engineering/posts/2020-05-13-loop-mpp/)
- Update: BTCPayServer v1.0.5.2 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.5.2)
- Update: RTL 0.8.1 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.7.1)
- Update: ElectRS 0.8.5 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#085-1-july-2020)
- Update: JoinMarket v0.6.3.1 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.6.3.1)
- New: Nginx Web Server
- New: Subscriptions Management
- New: IP2Tor Bridge (optional subscription service)
- New: Balance of Satoshis v5.41.0 (with update option) [details](https://github.com/alexbosworth/balanceofsatoshis)
- New: Faraday [details](https://github.com/lightninglabs/faraday)
- New: Let's Encrypt client [details](FAQ.md#how-to-use-the-lets-encrypt-client)
- New: ThunderHub v0.8.12 (with update option) [details](https://www.thunderhub.io)
- New: JoininBox (terminal based GUI for JoinMarket) [details](https://github.com/openoms/joininbox)
- New: ZeroTier [details](https://zerotier.com/manual/)
- New: Kindle Display (on a jailbroken Kindle) [details](https://github.com/dennisreimann/kindle-display)
- New: Static Channel Backup on USB Thumbdrive [details](https://github.com/rootzoll/raspiblitz/tree/v1.6#c-local-backup-target-usb-thumbdrive)
- New: Keep WIFI config over wpa_supplicant.conf for next update
- Fix: DropBox StaticChannelBackup
- Removed: Shango from the list of Mobile Wallets
- Removed: Torrent Download of Blockchain (Copy over LAN now default for RP3)
- Shoppinglist: 4GB RaspberryPi 4 is now default for Standard Package (will still run with less)

## What's new in Version 1.5.1 of RaspiBlitz?

- Bugfix: DropBox Backup of Static-Channel-Backup
- Bugfix: Torrentfiles with active tracker

## What.s new in Version 1.5 of RaspiBlitz?

Beside many small improvements and changes, these are most important changes:

- Update: LND version 0.9.2-beta (optional update to 0.10.0-beta)
- Update: bitcoin-core version 0.19.1-beta [details](https://github.com/bitcoin/bitcoin/blob/master/doc/release-notes/release-notes-0.19.1.md)
- Update: Loop 0.5.1 or 0.6.0 (based on LND version) [details](https://github.com/lightninglabs/loop/releases)
- Update: RTL 0.7.0 (Loop In and Out integration) [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.7.0)
- Update: BTCPayServer v1.0.4.2 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.4.2)
- Update: LNbits v0.1 [details](https://twitter.com/lnbits/status/1253700293440741377?s=20)
- Update: BTC-RPC-Explorer v2.0.0 [details](https://github.com/janoside/btc-rpc-explorer/blob/master/CHANGELOG.md#v200)
- Update: lndmanage 0.10.0 [details](https://github.com/bitromortac/lndmanage/releases/tag/v0.10.0)
- Shoppinglist: Replace Shimfan with passive RP4-Heatcase
- Shoppinglist: 1TB SSD is now default [details about migration to bigger SSD](README.md#import-a-migration-file)
- Fix: (Control-D) Give root password for maintenance [details](https://github.com/rootzoll/raspiblitz/issues/1053)
- Fix: Screen Rotate on update from v1.3
- New: Specter Desktop (connect DIY Specter-Wallet or ColdCard) [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- New: JoinMarket [details](https://github.com/JoinMarket-Org/joinmarket-clientserver)
- New: Activate 'Keysend' on LND by Service Menu [details](https://github.com/rootzoll/raspiblitz/issues/1000)
- New: SendMany App (wallet & chat over keysend) [details](https://github.com/fusion44/sendmany/blob/master/README.md)
- New: Reset SSH cert if SSH login not working [details](FAQ.md#how-can-i-repair-my-ssh-login)
- New: Make it easier to Copy The Blockchain over Network from running Blitz
- New: Forwarding Fee Report on Main Menu
- New: Easy Setup of Auto-Backup of SCB to Dropbox
- New: LND Interims Updates (verified & reckless) [details](https://github.com/rootzoll/raspiblitz/issues/1116#issuecomment-619467148)
- New: Sync RaspiBlitz with your forked GitHub repo thru menu [details](FAQ.md#how-can-i-sync-a-branch-of-my-forked-github-with-my-local-raspiblitz)
- Removed: Clone Blockchain from second HDD (use CopyStation script)

DOWNLOAD the new RaspiBlitz v1.5 image [here](README.md#installing-the-software).

## What's new in Version 1.4 of RaspiBlitz?

Beside many small improvements and changes, these are most important changes:

- Update: LND version 0.9.0-beta
- Update: bitcoin-core version 19.0.1-beta
- Update: litecoin version 0.17.1-beta
- Update: RTL (Ride the Lightning) Web UI version 0.6.7-beta (redesign)
- Update: Touchscreen UI (Node Info & Donate)
- Update: Fee Report on LCD
- Update: TORv2 -> TORv3
- Update: New Torrent files
- New: ElectRS (Electrum Server in Rust) [details](https://github.com/romanz/electrs)
- New: BTCPayServer (Cryptocurrency Payment Processor) [details](https://btcpayserver.org)
- New: LNDmanage (Advanced Channel Management CLI) [details](https://github.com/bitromortac/lndmanage)
- New: BTC-RPC-Explorer (Bitcoin Blockchain Explorer) [details](https://github.com/janoside/btc-rpc-explorer)
- New: Loop (Submarine Swaps Service) [details](https://github.com/lightninglabs/loop)
- New: LNbits (Lightning wallet/accounts System) [details](https://github.com/arcbtc/lnbits)
- New: Fully Noded (iOS) [details](https://apps.apple.com/us/app/fully-noded/id1436425586)
- New: Tor Support to connect mobile Apps
- New: Migration Export/Import (e.g. HDD -> SSD) [details](README.md#import-a-migration-file)
- New: Start without LCD (switch to HDMI) [details](FAQ.md#can-i-run-the-raspiblitz-without-a-displaylcd)
- New: Recovery Sheet (PDF) [details](https://github.com/rootzoll/raspiblitz/raw/v1.4/home.admin/assets/RaspiBlitzRecoverySheet.pdf)
- Experimental: BTRFS [details](FAQ.md#why-use-btrfs-on-raspiblitz)

For full details see issue list of [Release 1.4 Milestone](https://github.com/rootzoll/raspiblitz/milestone/7?closed=1).

Find the full Tutorial how to build a RaspiBlitz in the [README](README.md) or follow the [instructions to update to the latest version](README.md#updating-raspiblitz-to-new-version).

## What's new in Version 1.3 of RaspiBlitz?

Version 1.3 is using the new Raspbian Buster that is ready to use with the RaspberryPi 4 (also still works with RaspberryPi 3).

- update: New Shopping Lists with RaspberryPi 4
- Update: LND version 0.7.1-beta (fix for CVE-2019-12999)
- Update: bitcoin-core version 0.18.1-beta
- Update: RTL (Ride the Lightning) Web UI version 0.4.2 -beta
- Update: Blockchain Index not needed anymore
- Update: New Torrent files
- New: Logo (see folder raspiblitz/logos)
- New: Sync/Validate Blockchain as default for RP4
- New: Switch on Tor during setup
- New: Support Zap Mobile for Android
- New: Repair Options in main menu
- New: UPNP (AutoNAT) support in services menu
- New: LCD rotate 180 degrees in services menu
- Fix: Tor switch on/off
- Fix: Zap iOS Mobile Wallet connect
- Fix: Shango Mobile Wallet connect
- Experimental: LCD Touchscreen Support
- Experimental: UPS support (APC) [details](FAQ.md#how-to-connect-a-ups-to-the-raspiblitz)

For full details see issue list of [Release 1.3 Milestone](https://github.com/rootzoll/raspiblitz/milestone/6?closed=1).

## What's new in Version 1.2 of RaspiBlitz?

Version 1.2 packs some more fixes and enhancements to make the RaspiBlitz more stable, protect HDD data better and support you better in case of data corruption of the blockchain data.

- Update: LND version 0.6-beta
- Update: RTL (Ride the Lightning) Web UI version 0.2.16-beta
- Update: Shopping Lists (new Heatsink Case lowers 10°)
- Update: New Torrent Update file (reducing blockchain sync time)
- Fix: LND scanning stuck on ? (better error handling)
- Fix: Cash out all funds
- Fix: Keep TLS certs stable on update
- New: Support Zeus Mobile Wallet
- New: Show QR codes on LCD
- New: Support LND Static Channel Backup
- New: Remote-Backup of channel.backup file (SCP & Dropbox)
- New: Recover Node from LND rescue backup file
- New: Run Hardware Test on setup and main menu
- New: Run Software Test (DebugLogs) from main menu
- New: SSH-Forward Tunneling (commandline)
- New: Set fixed IP/domain for RaspiBlitz (commandline)
- New: Set DNS server (commandline)
- New: Run LND on different port (commandline)
- New: Ask before formatting HDD
- New: Better Update support (from main menu)
- New: Temp in Fahrenheit on the LCD
- Experimental: Backup Torrent Seeding (Service)

For full details see issue list of [Release 1.2 Milestone](https://github.com/rootzoll/raspiblitz/milestone/5?closed=1).

## What's new in Version 1.1 of RaspiBlitz?

Version 1.1 packs some first fixes and enhancements to make the RaspiBlitz more stable, protect HDD data better and support you better in case of data corruption of the blockchain data.

- Update: RTL (Ride the Lightning) Web UI version 0.2.15-beta
- Fix: Preventing logs from filling up the sd card
- Fix: Pairing for latest Zap iOS Mobile Wallet
- Fix: Pairing for latest Shango Mobile Wallet
- Fix: Open LND port check when custom port
- New: Undervoltage Reports on LCD
- New: fsk (file system consistency check) of HDD on every boot
- New: Repair Help Menu in case if blockchain data corruption
- New: /config.scripts/lnd.setport.sh (set custom LND port)
- New: /config.scripts/lnd.rescue.sh (backup/replay LND data)
- New: Bootscreen with logo
- Removed: FTP download option for blockchain

For full details see issue list of [Release 1.1 Milestone](https://github.com/rootzoll/raspiblitz/milestone/3?closed=1).

