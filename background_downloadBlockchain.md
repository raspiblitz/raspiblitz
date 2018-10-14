# Background: Blockchain Download

## Why do we need to download the blockchain and not syncing it?

The RaspiBlitz is powered by the RaspberryPi. The processing power of this SingleBoardComputer is too low to make a fast sync of the blockchain from the bitcoin peer to peer network during setup process (validation). To sync and index the complete blockchain could take weeks or even longer. Thats why the RaspiBlitz needs to download a prepared blockchain from another source.

## Is downloading the blockchain secure?

The downloaded Blockchain is pre-indexed and pre-validated. That is secure enough because if the user gets a "manipulated" blockchain it would not work after setup. The beginning of the downloaded blockchain needs to fit the genesis block (in bitcoind software) and the end of the downloaded blockchain needs not match with the rest of the bitcoin network state - hashes of new block distrubuted within the peer-2-peer network need to match the downloaded blockchain head. If beginning and end of the chain From a user perspektive a manipulated blockchain would simply just dont work. 

There might be theoretical scenarios why it would be bad for the whole network if anybody is downloading a prepared blockchain and not syncing and self-validating every block, but with a lot of self-validating full nodes already out there, just putting some RaspiBlitz with a downloaded blockchain into the mix and runnig as a self-valifating full node from that point on, is practically just strengthening the the overall network.

If you have any link to a more detailed discussion of this topic, please add it here for people to do their own research.

## Blockchain Data

The RaspiBlitz needs the following files from a bitcoind (>=0.17.0) that is fully sync and has indexing switched on (txindex=1) - all files from the directories:
```
/blocks
/chainstate
/indexes
```

Make sure not to add other files like wallet data or lock files to a prepared download.

You might want to include the testnet data also - then add the testnet3 folder that just contains the same three folders from the testnet blockchain.

On download all those files need to be placed finally in the /mnt/hdd/bitcoin folder of the RaspiBlitz.

## Download Process

At the moment the RaspiBlitz offers two technical ways to download the blockchain: 

### FTP Download (fallback)

The easiest way is to put the blockchain data on a FTP server and let people download it. FTP is able to download complete directories - HTTP can just handle single file. FTP clients and server hosting is widly available.

The downside that this is a central point solution and is hard to scale up (without spending a lot of money). But it is available as a backup, if other solutions do not work.

### Torrent Download (default)

The preferred way is to to download the blockchain data thru the peer2peer torrent network. This way the community can help to seed the torrents (at least while downloading). Supporters of the project can setup constant seeding. There is no single point of failure within the download structure.

In the beginning we used just on torrent file - containing all the directories and data like mentioned above. But this had the downside, that everytime when we update the torrent the seeding is bad in the beginning and downloads are slow. Good seeding needs time to build up. 

Thats why there are two torrent files now:

#### Base Torrent File

Inspired by the website getbitcoinblockchain.com we use one of their base torrent files to have a basic set of blocks - that will not change for the future. This torrent contains most of the data (the big file) and we dont need to change the torrent for a long time. This way the torrent can get establish a wide spread seeding and the torrent network can take the heavy load.

At the moment this is just the blk and rev files up to the number:
- /blocks : 01385
- /testnet3/blocks: 00152

#### Update Torrent File (Description)

All the rest of the files get packaged into a second torrent file. This file will be updated much more often. The seeding is expected to be not that good and download may be slower, but thats OK because its a much smaller file.

This way a good balance between good seeding and up-to-date blockchain can be reached.

#### Update Torrent File (Creation)

To create the Update Torrent file, follow the following step ...

Have a almost 100% synced bitcoind MAINNET with txindex=1 on a RaspiBlitz

Stop bitcoind with: 
```
sudo systemctl stop bitcoind
```

Delete base torrent blk-files with:
```
sudo rm /mnt/hdd/bitcoin/blocks/blk00*.dat
sudo rm /mnt/hdd/bitcoin/blocks/blk0{1000..1390}.dat
```

Delete base torrent rev-files with:
```
sudo rm /mnt/hdd/bitcoin/blocks/rev00*.dat
sudo rm /mnt/hdd/bitcoin/blocks/rev0{1000..1390}.dat
```

Now change to your computer where you package the torrent files and transfere the three directories into your torrent base directory (should be your current working directory):
```
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/blocks ./blocks
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/chainstate ./chainstate
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/indexes ./indexes
```

Also have a almost 100% synced bitcoind TESTNET with txindex=1 on a RaspiBlitz

Stop bitcoind with:
```
sudo systemctl stop bitcoind
```

Delete base torrent blk-files with:
```
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/blk000*.dat
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/blk00{100..152}.dat
```

Delete base torrent rev-files with:
```
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/rev000*.dat
sudo rm /mnt/hdd/bitcoin/testnet3/blocks/rev00{100..152}.dat
```

Now change again to your computer where you package the torrent files and transfere the three directories into your torrent base directory (should be your current working directory):
```
mkdir testnet3
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/testnet3/blocks ./testnet3/blocks
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/testnet3/chainstate ./testnet3/chainstate
scp -r bitcoin@[RaspiBlitzIP]:/mnt/hdd/bitcoin/testnet3/indexes ./testnet3/indexes
```

(Re-)name the "torrent base directory" to the same name as the torrent UPDATE file itself later (without the .torrent ending). For the correct naming see the chapter "Torrent Files Naming Schema" below.

Now open your torrent client (e.g. qTorrent for OSX) and create a new torrent-file with the freshly renamed "torrent base directory" as source directory.

Add this list of trackers to your torrent and start seeding (keep a free/empty line between the three single trackers):
```
udp://tracker.justseed.it:1337

udp://tracker.coppersurfer.tk:6969/announce

udp://open.demonii.si:1337/announce

udp://denis.stalker.upeer.me:6969/announce
```

Name the new torrent file 

To create the torrent file can take some time. Finally add the generated torrent file to the /home.admin/assets/ of the github and change the name of the updateTorrent varibale file in the script 50torrentHDD.bitcoin.sh

#### Torrent Files Naming Schema

The base torrent file should always have the following naming scheme:

`raspiblitz-[CHAINNETWORK][BASEITERATIONNUMBER]-[YEAR]-[MONTH]-[DAY]-base.torrent`

So for example the second version of the base torrent for litecoin created on 2018-10-31 would have this name: raspiblitz-litecoin2-2018-10-31-base.torrent

The update torrentfile should always have the following naming schema:

`raspiblitz-[CHAINNETWORK][BASEITERATIONNUMBER]-[YEAR]-[MONTH]-[DAY]-update.torrent`

So for exmaple an update torrent created on 2018-12-24 for litecoin that is an update to the second base torrent version would have this name: raspiblitz-litecoin2-2018-12-24-update.torrent


TODO: Adapt files sizes