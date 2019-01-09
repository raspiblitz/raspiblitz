# FAQ - Frequently Asked Questions

## How to backup my Lightning Node?

CAUTION:  Restoring a backup can lead to LOSS OF ALL CHANNEL FUNDS if its not the latest channel state. There is no perfect backup solution for lightning nodes yet - this topic is in development by the community.

But there is one safe way to start: Store your LND wallet seed (list of words you got on wallet creation) in a safe place. Its the key to recover access to your on-chain funds - your coins that are not bound in an active channel.

Recovering the coins that you have in a active channel is a bit more complicated. Because you have to be sure that you really have an up to date backup of your channel state data. The problem is: If you post an old state of your channel this looks to the network like you want to cheat and your channel partner is allowed claim all the funds in the channel.

To really have a good backup to rely on such feature needs to be part of the LND software. Almost every other solution would not be perfect. Thats why RaspiBlitz is not trying to provide a backup feature at the moment.

But you can try to backup at your own risk. All your Lightning Node data is within the `/mnt/hdd/lnd` directory. Just run a backup of that data when the lnd service is stopped.