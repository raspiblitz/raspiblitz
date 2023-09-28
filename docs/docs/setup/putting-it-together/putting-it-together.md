---
sidebar_position: 4
---

# Basic Setup

Every time you start with a fresh SD card image you will be offered different options.
For example this is also the point where you can import a Migration file from an older RaspiBlitz - read about Migration `TODO: further down README.md#import-a-migration-file`.
But because you are setting up a brand new RaspiBlitz you will choose here `FRESHSETUP`.

![SSH0](../../../static/img/ssh0-welcome2.png)

Then you will be asked what to do with the connected hard drive/SSD.

If there is already a blockchain on your hard drive/SSD you will be asked if you want to use this pre-synced/validated data or if its OK to delete it.
If there is no blockchain data this question will be skipped.

![SSH0](../../../static/img/ssh0-askchain.png)

Finally you have to agree that all (other) data on the hard drive/SSD will be deleted, except the blockchain if you selected that previously.
This might take some seconds.

![SSH0](../../../static/img/ssh0-formathdd.png)

First thing to setup is giving your RaspiBlitz a name:

![SSH1](../../../static/img/ssh1-name.png)

The name you choose for your RaspiBlitz will also be used as your public alias of your lightning node so choose wisely.

Then you can choose which Lightning implementation you want to run on top of your Bitcoin Fullnode.
RaspiBlitz started with `LND` from Lightning Labs which is used by most other RaspberryPi lightning nodes and works with most additional apps.
But you can now also choose `CL` for Core Lightning by Blockstream which is a good choice for more experienced node operators & lightning developers that want to use the highly customizable plugin structure that Core Lightning offers.

It's also possible to use both lightning node implementations in parallel on your RaspiBlitz later on - just pick one to start with for now.

Choose `NONE` if you're only interested in running a Bitcoin full node without Lightning.

![SSH1](../../../static/img/ssh1-layer2.png)

:::info 
In the following we show the setup with LND - which is very similar to the steps with Core Lightning.
:::

If you chose to use one of the lightning implementations you will now be asked if you want to start a `NEW` wallet/lightning node or if you have an `OLD` lightning wallet/node that you want to re-create.

![SSH1](../../../static/img/ssh1-oldnew.png)

Normally you just chose `NEW` here, but to recover an old wallet you have the following options if you choose `OLD`:

![SSH1](../../../static/img/ssh2-layer2old.png)
