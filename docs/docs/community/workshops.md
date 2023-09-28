---
sidebar_position: 2
---
# Workshop Tutorial

One goal of the RaspiBlitz project is to provide an open DIY platform for workshops - to setup your own lightning node and learn to manage it. This tutorial is collecting best practices on how to organize a RaspiBlitz workshop.

# Time Planning

First thing on planning a RaspiBlitz workshop is to calculate the time needed correctly. For example, the setup from scratch with no further support is still a weekend project - mostly because downloading and syncing the blockchain takes a lot of time.


So the time required for the workshop all depends on the preparation you as a workshop organizer are interested to provide ahead of the workshop. This document outlines three starting configurations... going from most preparation required to least.

Note that the time estimates below are about getting a node to a "clean setup". They do not include the funding & setting up channels process - which is adding an additional 30 min to 1 hour to the calculation.

Also, if your group is lager then 5 participants, calculate some extra time for individual support. You can compensate for that if you let two participants work together on one RaspiBlitz setup; this way you limit individual support and let them help each other.


## Workshop Scenario A) Provide a Ready-2-Go RaspiBlitz

_Estimated Duration: 2 Hours_

Sure, one part of the fun for participants is to assemble the hardware themselves. But if you aim for the shortest workshop possible, then this is the way to go (around 2 hours length). If you have the RaspiBlitz already assembled to be operational at the workshop you should already set them up with a basic setup, maybe even transfer a small amount of coins onto them. This way you can give the workshop participants the A.B.C.D passwords on a sheet of paper and let them jump right into learning how to manage a node. While waiting for confirmations on the first channel opening you can use the time to explain how to build a RaspiBlitz from scratch and some Lightning basics.

These are the following steps you need to prepare (follow links for details):

- [Buy all the Hardware](workshops#buy-all-the-hardware)
- [Assemble all the Hardware]((workshops#assemble-all-the-hardware)
- [Prepare HDDs with Blockchain Data](workshops#prepare-hdds-with-blockchain-data)
- [Prepare SD cards with latest RaspiBlitz image](workshops#prepare-sd-cards-with-latest-raspiblitz-image)
- Run Basic Node Setup
- [Setup Workshop Environment](workshops#setup-workshop-environment)

_NOTE: Make sure that the blockchain of the RaspiBlitzes are synced before the workshop begins._

## Workshop Scenario B) Provide a RaspiBlitz Hardware-Kit

_Estimated Duration: 3 Hours_


In this workshop scenario you buy all the hardware but let participants assemble the RaspiBlitz themselves - that's half the fun and people get a feel for the gear. But to keep the blockchain sync time short and be able to keep in a 3 hour time frame you need to prepare the HDDs with blockchain data not much older than one day. Start ordering the parts at least one week before the workshop (budget as needed) and plan the day before completely for copying blockchain data to all those HDDs.


These are the following steps you need to prepare (follow links for details):

- [Buy all the Hardware](workshops#buy-all-the-hardware)
- [Prepare HDDs with Blockchain Data](workshops#prepare-hdds-with-blockchain-data)
- [Prepare SD cards with latest RaspiBlitz image](workshops#prepare-sd-cards-with-latest-raspiblitz-image)
- [Setup Workshop Environment](workshops#setup-workshop-environment)

Variation: If you don't have a big budget to pre-finance the parts or people have already hardware they want to bring you can just buy the HDDs and SD cards and prepare them to run this scenario.


## Workshop Scenario C) Bring your own Hardware


_Estimated Duration: 4–6 Hours_

This scenario is advised only for small groups, or you'll need to bring multiple blockchain copy stations - see details on "Prepare HDDs with Blockchain Data". Otherwise it needs the least preparation time and prefinance and can be announced to participants about 5 days beforehand, so that they have time to order all the parts online.


- [Instruct Participants to bring Hardware](workshops#instruct-participants-to-bring-hardware)
- [Prepare Blockchain Copy Station](workshops#prepare-blockchain-copy-station)
- [Setup Workshop Environment](workshops#setup-workshop-environment)


As soon as the participants arrive at the workhop, make sure to check their hardware list. We also suggest taking their HDDs and starting the blockchain copy process before official starting time.


<br/>


# Checklist for Running a Workshop

Make sure you have the following hardware and infrastructure ready for the workshop:

- Lots of 'multiple power outlets/extensions' (min. 2 per participants - RaspiBlitz + Laptop)
- Network-Switch with enough ports (min. 1 per RaspiBlitz)
- Enough LAN network cables (short ones to connect the RaspiBlitzes)
- Good internet connection at location with LAN port (or a WLAN to LAN adapter)
- Extra WLAN Router (if you are not sure if LAN & WLAN is not on the same network at location)
- One or two USB SD card adapters
- One or two USB-C to USB-A adapters
- Some Tape, Markers & Pens always come in handy (also for participants to write down seeds & passwords)
- Potentially some bitcoin funds (if people dont have their own to start funding channels)

Participants need to bring at least their laptops.

<br/>

# Running of the Workshop

_The basic structure of the workshop is set by the RaspiBlitz setup process. Simply follow that. The following parts should share some experiences and suggestions on how you can optimize the time and mentoring during this process. Feel free to share your experience here._

## Welcome and Intro

In the beginning, it's great to give a small introduction to the Lightning Network and show the RaspiBlitz GitHub page to let everybody know where to find the basic info. But try to keep it around 10 min, in order to not waste time.


Also, even before the intro, take care of the blockchain preparation. If people bring clean HDDs, hook them up to your blockchain copy station as soon as possible. If you have to copy on location, plan to spend time for some deeper educational intro while the HDDs get prepared.

## Assembling

If you hand out hardware kits or people bring their own hardware, it's time to put it together. If you are in a ready-2-go scenario, of course skip this and just hand them out.

## Basic Setup


Connect everybody's laptop to the same local network the RaspiBlitzes are connected to. Be prepared to explain how to open a terminal - Windows' users especially need some help here (see README on this).


Then everybody is SSHing into the RaspiBlitz and is following the setup dialog. Hand out paper and pens for people to write down their passwords and wallet seeds.

## Waiting Time

After the lightning wallet setup comes the longest waiting time during the workshop - around 30 min. When you have a pre-synced ready-2-go or up to 1 hour for the other scenarios. It's the time when the node is syncing up the blockchain and LND is scanning. If you see someone's blockchain progress under 97%, something is wrong - possibly the HDD was not correctly prepared or the blockchain data is way too old to finish during workshop time if you work with old RaspberryPi3. The new RaspberryPi4 with SSD can catch up much faster.


Use this time for a more in-depth educational segment on lightning in general. This time can also be used to demo with one RaspiBlitz that is already on clean-setup (you prepared before the workshop) how the funding, setting up channels and the other features of the RaspiBlitz work. That way people see what are the next steps once their node is ready and even if your workshop time is over by then they can know the next steps to do at home.

Also this time is good for troubleshooting in individual sessions. If someone is not able to finish the sync on location in time shutdown the Raspiblitz from SSH terminal with CTRL+C and then `shutdown now`. If the device gets connected back up at home it should pickup the sync/scan process (let people know about the wallet unlock).


## Finalizing Setup

Once the RaspiBlitz is ready (LCD shows status screen) and people can SSH into the main menu, let them go into the `SERVICES` section and activate the `RTL WebUI`. It's the best interface to then continue with the peering, funding and channel opening.

## Funding, Channels, API

Check how much time is left to go thru the next steps of connecting to peers, funding and opening channels. While you wait on funding or channel opening confirmations, its a good moment to try to connect users mobile wallets with the device. But just so that on the local network for demo - dynamicDNS is something people then can try at home with port forwarding on their routers.

Its also nice to add casual social open-end segment to the end of the workshop. So people can already go into personal conversations, music and beverages while some last nodes sync up, confirmations come in and people sending their first satoshis on some lightning chess or from node to node.

Here are some videos that show what else is possible with the RaspiBlitz:

- [Lightning Network LND API - Buying Stickers using Commandline](https://youtu.be/tocJFPU8sAc) 24min

<br/>

# Organisation Tasks


*Which of the following organisation tasks are relevant for you depends on which starting scenario you choose (see above). Here is the complete possible list with details:*


## Buy all the Hardware

See the shopping list on the RaspiBlitz Github README. You need to buy all of those, and every participant also needs a short (about 1m) network cable.


From experience start ordering two weeks before the workshop (if you need to assemble) and minimum one week if you're handing out hardware kits - even if you have Amazon Prime. There is always a shipment coming late, and it's a lot of packages.


If you like to support the RaspiBlitz project you can order a ready-2-go RaspiBlitz or a all-you-need-hardwareset for your RaspiBlitz workshop from [raspiblitz.com](https://raspiblitz.com)

## Instruct Participants to Bring Hardware

This is for the scenario where people bring their own hardware. Make sure to let them know at least a week before the event so that there is enough time for online ordering. Also make sure that especially the power supply needs to provide 3A and a stable current (big fat with a thick cable is good) because that's the most often error source if people just reuse some old weak power supply.

In all scenarios make sure people bring their laptops.

## Assemble all the Hardware


Basically you follow the assembly instructions on the RaspiBlitz GitHUb README. Think of a safe way to transport the assembled devices to the workshop location - HDDs like it soft.


## Prepare HDDs with Blockchain Data

This is the most time consuming part of the preparation. Try it once to get a feel for how much time you need to prepare one HDD. If you prepare more than one HDD check out the "Copystation" script below.

A prepared HDD is formatted in EXT4 and named "BLOCKCHAIN". In a folder called `bitcoin` it contains a copy of the following data folders from a running Bitcoin core client (same version on RaspiBlitz).

```
/bitcoin/blocks
/bitcoin/chainstate
```

The bitcoin core client (0.17.1 or higher) needs to be stopped while the data is copied to the HDD.

The easiest way to get a "template" of such HDD is to setup a fresh RaspiBlitz (without channel and fundings) and then run the script `/home/admin/XXcleanHDD.sh` and manually delete all rest data from the HDD and just leave those folders.


Once you have that "template" you can make an image from that and write that image to the other HDDs. 



## Prepare Blockchain Copy Station

In the RaspiBlitz GitHub repo and also on every RaspiBlitz (since v1.3) you can find the script:
`/home/admin/XXcopyStation.sh`

This can be used to prepare and keep multiple HDDs in sync with blockchain data in preparation of a workshop. You can start it directly on a RaspiBlitz and turn it into "Copy Station Mode" by executing on the command line:

`sudo /home/admin/XXcopyStation.sh`

_Beware that it will not run as a Lightning Node during that time (LND is stopped). And to reset it back into normal mode you need to stop the script with `CTLR+c` and the reboot with `sudo shutdown -r now`._


In "Copy Station Mode" the RaspiBlitz will just run the bitcoind (so it needs network connection), copy fresh blockchain data over to a template folder on the HDD called `/mnt/hdd/templateHDD` and from there sync it to further HDDs that get connected to it.

If you run it in a setup like on this photo with an extra powered USB hub, you can connect up to 10 HDDs at once to be synced with an almost up-to-date blockchain.

At the moment the "Blockchain Copy Station" is just a computer (laptop - not a RaspberryPi) having an image of a "template" HDD (see above) and you can attach (with a USB3.0 Hub) multiple fresh HHDs to it and start writing in the template image to that.

To update the "template" HDD for the next workshop use it for a fresh clean RaspiBlitz setup just days before, sync the blockchain to 100% and repeat the process above.

_This version is not tested, but seems like the easiest to setup so far. Images can have the problem of being too large when some 1TB HDDs are just some bytes smaller. So for the template HDD it would be best to find the smallest 1TB HDD possible or just writing the image to HDDs of the same brand & model._

Copying the blockchain between RaspberryPis during the workshop is not an option, because the network and its USB2 is too slow and will take 3 to 4 hours.

For former workshops I had a laptop just with the data and had a script that was formatting and rsyning that data over to a fresh HDD. That took around 1,5 hours per HDD.

_If someone has a better idea for a 'Blockchain Copy Station', please feel free to contribute._

## Prepare SD Cards with Latest RaspiBlitz Image

Download the latest RaspiBlitz SD card image from the README page. `Balena Etcher` is the best image writing software for this use case because if you have multiple sd card adapters, you can write multiple cards at once,cutting down your preparation time.

## Setup Workshop Environment

See hardware checklist for what to bring to the workshop in the earlier chapter.

Setup power outlets for everybody. Its always good to be way early at the workshop location for setup, especially if you run the "pre-sync" of the ready-2-go scenario.

Most important is the network setup. Every RaspiBlitz needs a LAN port in the switch and that switch needs to be on the same local network as the WLAN so that participants laptop can SSH into the RaspiBlitz. If that is not the case or you cannot confirm that before the event its best to bring an additional WLAN router. Then you give the WLAN router internet uplink thru the available LAN cable and you put the network switch for the Raspiblitzes behind that router and open an additional WLAN on that WLAN router for everybody to connect to. It's OK to be behind a NAT; it's just important for everybody to be behind the same NAT.

