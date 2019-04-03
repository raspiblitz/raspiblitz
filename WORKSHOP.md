# RaspiBlitz Workshop Tutorial

One goal of the RaspiBlitz project is to provide a open DIY platform for workshops - to setup your own lightning node and learn to manage it. This tutorial is collecting best practices on how to organise a RaspiBlitz workshop.

# Time Planning

First thing on planning a RaspiBlitz workshop is to calculate the time needed correctly. Because the setup from scratch with no further support is still a weekend project - mostly because downloading and syncing the blockchain takes a lot of time.

So it all depends on what you as a workshop organizer provide on prepartion for the workshop participants. Basically you can choose one of the following starting configurations ... going from most prepared to least prepared. 

Also the time estimates below are about getting a node to a "clean setup". That is not containing the funding & setting up channels process - which is adding an additional 30 min to 1 hour to the calculation. 

Also if your group is lager then 5 participants, calculate some extra time for individual support. You can compensate for that if you let two participants together work on one RaspiBlitz setup - this way you limit individual support and let them help each other.

## A) Provide a Ready-2-Go RaspiBlitz

Estimated Duration: 2 hours

Sure one part of the fun for participents is to assemble the hardware themselves. But if you aim for the shortest workshop possible, by keeping it at around 2 hours lenght, then this is your way to go. Because if you have the RaspiBlitz already assembled to be operational at the workshop, you can utilize one big time saver feature: "The Pre-Sync" - before the workshop starts you can already plug a assembled RaspiBlitz into power+network and when there is a preloaded bitcoin blockchain on the HDD it will already start catching up. So your participants start with a on-the-spot synced blockchain and will just have to deal with waiting times during the lightning node setup. But keep in mind that you need budget to buy all the hardware and lots of time in preparation for this - order the parts two weeks before and start peparing at least 3 days before the workshop.

These are the following steps you need to prepare (follow links for details):

* [Buy all the Hardware](WORKSHOP.md#buy-all-the-hardware)
* [Assemble all the Hardware](WORKSHOP.md#assemble-all-the-hardware)
* [Prepare HDDs with Blockchain Data](WORKSHOP.md#prepare-hdds-with-blockchain-data)
* [Prepare SD cards with latest RaspiBlitz image](WORKSHOP.md#prepare-sd-cards-with-latest-raspiblitz-image)
* [Setup Workshop Environment](WORKSHOP.md#setup-workshop-environment)
* [Pre-Sync RaspiBlitzes at Workshop Location]()

## B) Provide a RaspiBlitz Hardware-Kit

Estimated Duration: 3 hours

In this workshop scenario you buy all the hardware but let participants assemble the RaspiBlitz themselves - thats half the fun and people get a feel for the gear. But to keep the blockchain sync time short and being able to keep in a 3 hour timeframe you need to prepare the HDDs with Blockchain Data not much older than one day. So start ordering the parts minimum one week before the workshop (budget needed) and plan the day before completly for copy blockchain data to all those HDDs.

These are the following steps you need to prepare (follow links for details):

* [Buy all the Hardware](WORKSHOP.md#buy-all-the-hardware)
* [Prepare HDDs with Blockchain Data](WORKSHOP.md#prepare-hdds-with-blockchain-data)
* [Prepare SD cards with latest RaspiBlitz image](WORKSHOP.md#prepare-sd-cards-with-latest-raspiblitz-image)
* [Setup Workshop Environment](WORKSHOP.md#setup-workshop-environment)

Variation: If you dont have a big bugdet to prefinance the part shoppings or people have already hardware they want to bring to can just buy the HHDs and SD cards and prepare them to run this scenario.

## C) Bring your own Hardware

Estimated Duration: 4-6 hours

This scenario is just adviced for small groups or you need to bring multiple blockchain copy stations - see details on "Prepare HDDs with Blockchain Data". Otherwise it needs the least prepartion time and prefinance and can be announced about participants 5 days before, so that they have time to order all the parts online. 

* [Instruct Participants to bring Hardware](WORKSHOP.md#instruct-participants-to-bring-hardware)
* [Prepare Blockchain Copy Station](WORKSHOP.md#prepare-blockchain-copy-station)
* [Setup Workshop Environment](WORKSHOP.md#setup-workshop-environment)

Make sure that as early as the participants arrive at the workhop location to check their hardware list and even before official starting time take their HDDs and start the blockchain copy process.

# Checklist for running a Workshop

Make sure you have the following Hardware and Infrastructure ready for the workshop:

- Lots of 'multiple power outlets/extensions' (min. 2 per participants - RaspiBlitz +Laptop)
- Network-Switch with enough ports (min 1 per RaspiBlitz)
- Enough LAN network cables (short ones to connect the RaspiBlitzes)
- Good internet connection at location with LAN port (or a WLAN to LAN adapter)
- Extra WLAN Router (if you are not sure if LAN & WLAN is not on the same network at location)
- One or two USB SD card adapters
- One or two USB-C to USB-A adapters
- Some Tape, Marker & Pens come always handy (also for participants to wirte down seed & passwords)
- And eventually some Bitcoin funds (if people dont have their own to start small funding channels)

Participants need at least to bring their laptops.

# Running of the Workshop

*The basic structure of the workshop is set by the RaspiBlitz setup process. Simply you just follow that. The following parts should share some experiences and suggestions how you can optimize the time and the mentoring during this process. Feel free to share your experience here.*

## Welcome and Intro

In the beginning it would be great to give a small introduction into Lightning and show the RaspiBlitz GitHub page to let everybody know where to find the basic infos. But try to keeo it in the area of 10min to not waste time.

Also even before the intro take care about the blockchain preparation. If people bring clean HDDs hook them up to your blockchain copy station as soon as possible. If you have to copy on location, plan to bringe the time for some deeper educational intro while the HDDs getting prepared.

## Assembling

If you hand out hardware kits or people bring their own hardware its time to put it together. If you are in a ready-2-go scenario of course skip this and just hand them out.

## Basic Setup

Connect everybodies Laptop to the same local network the RaspiBlitzes are connected to. Prepare to explain how to open a terminal - especially windows users need some help here (see README on this).

Then everybody is SSHing into the RaspiBlitz and is following the setup dialog. Hand out paper and pens for people to write down their passwords and the word seed.

## Waiting Time

After the lightning wallet setup you have the longest waiting time during the workshop - around 30min when you have a presynced ready-2-go or up to 1 hour in the other scenarios.  Its he time when the node is syncing up the blockchain and LND is scanning. If you see somebodies blockchain progress under 97% something is wrong - possibly the HDD was not correctly preparred or blockchain is way to old to finish during workshop time. 

Use this time for a more in-depth educational segment on lightning in general. Also this time can be used to demo with one RaspiBlitz that is already on clean-setup (you prepared before the workshop) how the funding, setting up channels and the other features of the RaspiBlitz work. That way people see what are the next steps once their node is ready and even if your workshop time is over by then they can know the next steps to do at home.

Also this time is good for trouble shooting in individal sessions. If someone is not able to finish the sync on location in time shutdown the Raspiblitz from SSH terminal with CTRL+C and then `shutdown now`. If the device gets connected back up at home it should pickup the sync/scan process (let people know about the wallet unlock).

## Finalizing Setup

Once the RaspiBlitz is ready (LCD shows status screen) and people can SSH into the main menu, let them go into the `SERVICES` section and activate the `RTL WebUI`. Its the best interface to then continue with the peering, funding and channel opening.

## Funding, Channels, API

Check how much time is left to go thru the next steps of connecting to peers, funding and opening channels. While you wait on funding or channel opening confirmations, its a good moment to try to connect users mobile wallets with the device. But just so that on the local network for demo - dynamicDNS is something people then can try at home with port forwarding on theior routers.

Its also nice to add casual social open-end segment to the end of the workshop. So people can already go into personal conversations, music and beverages while some last nodes sync up, confirmations come in and people sending their first satoshis on some lightning chess or from node to node.

# Organisation Tasks

*Which of the follwoing organisation tasks are relevant for you depends on which starting scenario you choose (see above). Here is the complete possible list with details:*

## Buy all the Hardware

See the shopping list on the RaspiBlitz Github README - you need to buy all of those and also dont forget that every participant needs a short (about 1m) network cable.

From experience start ordering two weeks before the workshop (if you need to assembly) and minimum one week if you handing out hardware kits - even if you have Amazon Prime. There is always a shipment comming late - its a lot of packages.

## Instruct Participants to bring Hardware

If you run the scenario of people bringing their own hardware. Make sure to let them know at least a week before the event so that there is enough time for online ordering. Also make sure that especially the power supply needs to provide 3A and a stable current (big fat with a thick cable is good) - because thats the most often error source if people just reuse some old weak power supply.

In all scenarios make sure people bring their laptops.

## Assemble all the Hardware

Basically you follow the assemble instructions on the RaspiBlitz GuitHUb README. Think of a safe way to transport the assambled devices to the workshop location - HHDs like it soft.

## Prepare HDDs with Blockchain Data

This is the most time consuming part of the preparation. Try it once to get a feel for how much time you need to prepare one HDD.

A prepared HDD is formatted in EXT4 and named "BLOCKCHAIN". In folder called `bitcoin` it contains a copy of the following data folders from a running Bitcoin core client (same version on RaspiBlitz).

```
/bitcoin/blocks
/bitcoin/chainstate
/bitcoin/indexes
```

optionaly you can add also the testnet data:

```
/bitcoin/testnet3/blocks
/bitcoin/testnet3/chainstate
/bitcoin/testnet3/indexes
```

The bitcoin core client the folders are from needs to have `txindex=1` in the bitcoin.conf and needs to be stopped while the data is copied to the HDD.

The easiest way to get a "template" of such HDD is to setup a fresh RaspiBlitz (without channel and fundings) and then run the script `/home/admin/XXcleanHDD.sh` and manually delete all rest data from the HDD and just leave those folders. 

Once you have that "template" you can make a image from that and write that image to the other HDDs. This works for HDDs that all habe

## Prepare Blockchain Copy Station

At the moment the "Blockchain Copy Station" is just a computer (laptop - not a RaspberryPi) having a image of a "template" HDD (see above) and you can attach (with a USB3.0 Hub) multiple fresh HHDs to it and start writing in the template image to that.

To update the "template" HDD for the next workshop use it for a fresh clean RaspiBllitz setup just days before, sync the blockchain to 100% and repeat the process above.

*This version is not tested, but seems like the easiest to setup so far. Images can have the problem of being too large when some 1TB HDDs are just some bytes smaller. So for the template HDD it would be best to find the smallest 1TB HDD possible or just writing the image to HDDs of the same brand & model.*

Copying the blockchain between RaspberryPis during the workshop is not an option, because the network and its USB2 is too slow and will take 3 to 4 hours.

For former workshops i had a Laptop just with the data and had a script that was formatting and rsyning that data over to a fresh HDD. That took around 1,5 hours per HDD.

*If someone has a better idea for a 'Blockchain Copy Station' - please feel free to contribute.*

## Prepare SD cards with latest RaspiBlitz image

Download the latest RasopiBlitz SD card image from the README page. `Balena Etcher` is the best image writing softare forn thsi usecase because if you have multiple sd card adapters, you can write multiple crads at once - that is cutting down your preperation time.

## Setup Workshop Environment

See hardware checklist what to bring to the workshop in the earlier chapter.

Setup power outlets for everybody. Its always good to be way early at the workshop location for setup, especially if you run the "pre-sync" of the ready-2-go scenario.

Most important is the network setup. Every RaspiBlitz needs a LAN port in the switch and that switch needs to be on the same local network as the WLAN so that participants laptop can SSH into the RaspiBlitz. If that is not the case or you cannot confirm that before the event its best to bring an additional WLAN router. Then you give the WLAN router internet uplink thru the available LAN cable and you put the network switch for the Raspiblitzes behind that router and open an additional WLAN on that WLAN router for everybody to connect to. Its OK to be behind a NAT - its just important for everybody to be behind the same NAT.

## Pre-Sync RaspiBlitzes at Workshop Location

In the ready-2-go scenario you have the RaspiBlitzes already assembled and a recent blockchain copy on the HDD. So one ot two hours before the workshop you setup your environment and already plug all RaspiBlitzes with power & network. You will see on the LCD at the top a pre-sync info and progress .. if its something '99.99..' its good to go. Just leave it running until the workshop starts. You dont need to stop it - just let participents SSH in and they can to the setup.

Its also best practice that you pre-sync all devices before you move them over to the workshop location. You dont need to SSH to shut them down before packing up - just unplug the network cable first, wait until the HDD is stopping to flash and then remove the power.