---
sidebar_position: 1
---

# Intro

**The RaspiBlitz is a do-it-yourself Lightning Node (LND and/or Core Lightning) running together with a Bitcoin-Fullnode on a RaspberryPi (1TB SSD) and a nice display for easy setup & monitoring.**

RaspiBlitz is mainly targeted for learning how to run your own node decentralized from home - because: Not your Node, Not your Rules.
Discover & develop the growing ecosystem of the Lightning Network by becoming a full part of it.
Build it as part of a [workshop](community/workshops.md) or as a weekend project yourself.

![RaspiBlitz](../static/img/raspiblitz.jpg)

## Feature Overview

Additional Services that can be installed thru WebUI (beginners):

- **Ride the Lightning (RTL)** (LND & CoreLightning Node Manager WebUI) [details](https://github.com/Ride-The-Lightning/RTL)
- **ThunderHub** (LND Node Manager WebUI) [details](https://www.thunderhub.io/)
- **BTC-RPC-Explorer** (Bitcoin Blockchain Explorer) [details](https://github.com/janoside/btc-rpc-explorer)
- **BTCPay Server** (Bitcoin Payment Processor) [details](https://btcpayserver.org)
- **LNbits** (Lightning wallet/accounts System) [details](https://twitter.com/lnbits/status/1253700293440741377?s=20)
- **Mempool Explorer** [details](https://github.com/mempool/mempool)
- **JAM** (JoinMarket Web UI) [details](https://github.com/joinmarket-webui/joinmarket-webui)

Further Services that are just available thru SSH menu (advanced users):

- **ElectRS** (Electrum Server in Rust) [details](https://github.com/romanz/electrs)
- **SpecterDesktop** (Multisig Trezor, Ledger, COLDCARD wallet & Specter-DIY) [details](https://github.com/cryptoadvance/specter-desktop) [app connection guide](https://d11n.net/connect-specter-desktor-with-raspiblitz.html)
- **Lightning Terminal (Loop, Pool & Faraday)** (Manage Channel Liquidity) [details](https://github.com/lightninglabs/lightning-terminal#lightning-terminal-lit)
- **JoinMarket** (CoinJoin Service) [details](https://github.com/JoinMarket-Org/joinmarket-clientserver)
- **JoinMarket Web UI** (Browser-based interface for JoinMarket) [details](https://github.com/joinmarket-webui/joinmarket-webui)
- **Balance Of Satoshis** (Commands for working with LND balances) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/README.md)
- **Kindle Display** (Bitcoin Status Display made with a jailbroken Kindle) [details](https://github.com/dennisreimann/kindle-display)
- **Stacking Sats Kraken** (Auto-DCA script) [details](https://github.com/dennisreimann/stacking-sats-kraken)
- **Circuit Breaker** (Lightning Channel Firewall) [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- **PyBlock** (Python Util & Fun Scripts) [details](https://github.com/curly60e/pyblock/blob/master/README.md)
- **Sphinx Chat Relay Server** [details](https://github.com/stakwork/sphinx-relay/blob/master/README.md)
- **Telegraf metrics** [details](https://github.com/rootzoll/raspiblitz/issues/1369)
- **Chantools** (Fund Rescue) [details](https://github.com/guggero/chantools/blob/master/README.md)
- **Suez** (Channel Visualization for LND & CL) [details](https://github.com/prusnak/suez#suez)
- **Helipad** (Podcasting 2.0 Boostagram reader) [details](https://github.com/Podcastindex-org/helipad)
- **Homer** (Web Dashboard) [details](https://github.com/bastienwirtz/homer#readme)
- **Squeaknode** [details](https://github.com/yzernik/squeaknode)
- **CL Spark Wallet** (WalletUI with BOLT12 offers) [details](https://github.com/shesek/spark-wallet#progressive-web-app)
- **CL plugin: Sparko** (WalletUI & HTTP-RPC bridge) [details](https://github.com/fiatjaf/sparko#the-sparko-plugin)
- **CL plugin: CLBOSS** (Automated Node Manager) [details](https://github.com/ZmnSCPxj/clboss#clboss-the-c-lightning-node-manager)
- **CL plugin: The Eye of Satoshi** (Watchtower) [details](https://github.com/talaia-labs/rust-teos/tree/master/watchtower-plugin)
- **Tallycoin Connect** (Use Tallycoin with your own node) [details](https://github.com/djbooth007/tallycoin_connect)
- **ItchySats** (Non-custodial peer-to-peer CFD trading) [details](https://github.com/itchysats/itchysats)
- **LNDg** (WebUI analyze/manage lnd with automation) [details](https://github.com/cryptosharks131/lndg)

You can connect the following Wallet-Apps to your RaspiBlitz (thru SSH menu):

- **Zeus** (Android & iOS) [details](https://zeusln.app)
- **Zap** (Android & iOS) [details](https://www.zaphq.io)
- **Fully Noded** (iOS) [details](https://apps.apple.com/us/app/fully-noded/id1436425586)
- **Sphinx Chat App** (Android & iOS) [details](https://sphinx.chat)
- **Alby** (Desktop) [details](https://getalby.com)

Also many more features like Touchscreen, Channels Autopilot, Backup, DynDNS, SSH-Tunneling, UPS Support, ...
