---
sidebar_position: 3
---

# Final Steps
Time to finish up the setup.

Finally you have to set 3 passwords called A, B & C.
For each password please choose unique, single strings, without spaces and special characters, that are at least 8 chars long.

![SSH2](../../../static/img/ssh2-passwords.png)

You can use this [RaspiBlitz Recovery Sheet (PDF)](https://github.com/rootzoll/raspiblitz/raw/v1.7/home.admin/assets/RaspiBlitzRecoverySheet.pdf) to write those passwords down for safe storage and also use it later on for your Seed Words.

___TODO: Not sure about the info boxes. They feel like they are too prominent and detract from the actual content___

:::info 
The password A,B,C idea is based on the [RaspiBolt Guide Preparations](https://raspibolt.org/guide/raspberry-pi/preparations.html#write-down-your-passwords) - check out for more background.
:::

First, password A is requested - this is the password which will be used for SSH login and it's also set for the existing users: admin, root, bitcoin & pi.

:::info 
The bitcoin and lightning services will later run in the background (as daemon) and use the separate user “bitcoin” for security reasons.
This user does not have admin rights and cannot change the system configuration.
:::

Then enter password B - this is internally used for the bitcoin RPC interface.
It is also used as login for additional apps like the RTL-WebGUI or the Blockexplorer.

And finally enter password C - this is used to encrypt/lock the lightning wallet on the hard drive/SSD and is used by LND.
Every time a lightning node is started/rebooted LND needs load the wallet into memory to work with and ask you for password C to "unlock" the wallet.

:::info
In the early RaspiBlitz versions there was also an additional password D, that is no longer in use.
:::

After this the setup process will need some time to set everything up - just wait until it's finished.
This can take from 10 to 30 minutes:

![SSH4](../../../static/img/ssh4-scripts.png)

### Final Setup

Once the basic setup has completed your lightning node will be setup & your lightning wallet will be created for you.
As part of this process you will be presented with your lightning node "seed words" which you _MUST_ write down on paper (or engrave into steel) and store in a secure location.
You will need to confirm that you wrote the seed words down before you can continue.

![SSH4](../../../static/img/ssh4-seed.png)

WRITE YOUR SEED WORDS DOWN before you continue - you will need them to recover funds in case of failing hardware etc.
If you just want to try/experiment with the RaspiBlitz, at least take a photo of the seed words with your smartphone, so you have something just in case.
If you plan to keep your RaspiBlitz running store this word list offline or in a password safe.

You can use this [RaspiBlitz Recovery Sheet (PDF)](https://github.com/rootzoll/raspiblitz/raw/v1.7/home.admin/assets/RaspiBlitzRecoverySheet.pdf) to write down your seed words for safe storage.

If you don't have a full copy of the blockchain pre-synced/validated on your hard drive/SSD then you will now be asked how you want to get your copy of the blockchain.
There are two basic options :

![SSH4](../../../static/img/ssh4-blockchain.png)

#### 1. SYNC - Self validate all Blocks

For the new RaspberryPi 4 (with SSD & min 2GB RAM) this is the best way to go.
It will take around 3-6 days to sync & validate directly with the bitcoin network.
With this option, you have done it the original `don't trust, verify` way.

:::info
For the old RaspberryPi 3 this is not recommended.
A RaspberryPi 3 has a very low power CPU and syncing+validating the blockchain directly with the peer2peer network can take multiple weeks - that's why for a RP3 you should choose the COPY option ._
:::

#### 2. COPY - Copy from Laptop or another RaspiBlitz over Local Network

If you have a friend that is already running a synced RaspiBlitz or you have a laptop with enough free space on the hard drive that can download & validate the Blockchain much faster you can also choose the `COPY` option.
You can then delete existing blockchain your RaspiBlitz already started syncing for you

![SSH4](../../../static/img/ssh4-copy.png)

To copy from another RaspiBlitz choose `BLITZ` and follow the instructions.
Know that the other Blitz will be offline to the lightning network during the copy that will take multiple hours.

To copy from your laptop/computer (`WINDOWS`, `MACOS` & `LINUX` options) you first need to download & validate the blockchain on your own computer/laptop.
To do so, install latest bitcoin-core (0.18.1 or higher) from [bitcoin.org](https://bitcoin.org/en/download) and keep it running until the blockchain is synced (will need around 400 GB).
Then under the `COPY` option choose the Operating System.
The copy will be done over the local network by SCP (SSH file transfer) - follow the instructions given in the dialogues.
It's advised to keep a backup of Bitcoin Core & the blockchain data directory on your laptop/computer in case you need to re-setup the RaspiBlitz.

More details: [I have the full blockchain on another computer. How do I copy it to the RaspiBlitz?](../../faq/faq.md#i-have-the-full-blockchain-on-another-storage-how-do-i-copy-it-to-the-raspiblitz)

If you don't have the Bitcoin blockchain already on another laptop or RaspiBlitz simply choose `SELFSYNC`.

And hooray :D Your RaspiBlitz is ready to go! Welcome new node operator.

![SSH4](../../../static/img/ssh4-done.png)

If you hit OK, the RaspiBlitz will go into a final reboot.

![SSH5](../../../static/img/ssh5-reboot.png)

Just wait a bit and then the SSH command to login again.
Logging in via SSH requires password A that you setup earlier.

![SSH5](../../../static/img/ssh5-unlock.png)

If you run LND you will be asked to unlock your wallet - this requires password C.
There is an option to activate auto-unlock of LND if you prefer, this can be found under `SETTINGS` in the main menu.

![SSH5](../../../static/img/ssh5-blocksync.png)

Your RaspiBlitz might need quite some time to sync and validate the blockchain -- this can be multiple days.
In the beginning you might see fast progress but this gets slower later on as historical blocks start to get fuller.
Your RaspberryPi CPU will likely get quite hot during initial sync.
However this is OK as the RaspberryPi has its own protection against overheating and will ensure the CPU doesn't critically overheat.

