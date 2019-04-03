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

* Buy all the Hardware
* Assemble all the Hardware
* Prepare HDDs with Blockchain Data
* Prepare SD cards with latest RaspiBlitz image
* Setup Workshop Environment
* Pre-Sync RaspiBlitzes at Workshop Location

## B) Provide a RaspiBlitz Hardware-Kit

Estimated Duration: 3 hours

In this workshop scenario you buy all the hardware but let participants assemble the RaspiBlitz themselves - thats half the fun and people get a feel for the gear. But to keep the blockchain sync time short and being able to keep in a 3 hour timeframe you need to prepare the HDDs with Blockchain Data not much older than one day. So start ordering the parts minimum one week before the workshop (budget needed) and plan the day before completly for copy blockchain data to all those HDDs.

These are the following steps you need to prepare (follow links for details):

* Buy all the Hardware
* Prepare HDDs with Blockchain Data
* Prepare SD cards with latest RaspiBlitz image
* Setup Workshop Environment

Variation: If you dont have a big bugdet to prefinance the part shoppings or people have already hardware they want to bring to can just buy the HHDs and SD cards and prepare them to run this scenario.

## B) Bring your own Hardware

Estimated Duration: 4 hours

This scenario is just adviced for small groups or you need to bring multiple blockchain copy stations - see details on "Prepare HDDs with Blockchain Data". Otherwise it needs the least prepartion time and prefinance and can be announced about participants 5 days before, so that they have time to order all the parts online. 

* Instruct Participants to bring Hardware
* Prepare Blockchain Copy Station
* Setup Workshop Environment

Make sure that as early as the participants arrive at the workhop location to check their hardware list and even before official starting time take their HDDs and start the blockchain copy process.

# Checklist for running a Workshop

Make sure you have the following Hardware and Infrastructure ready for the workshop:

* Lots of 'multiple power outlets/extensions' (min. 2 per participants - RaspiBlitz +Laptop)
* Network-Switch with enough ports (min 1 per RaspiBlitz)
* Enough LAN network cables (short ones to connect the RaspiBlitzes)
* Good internet connection at location with LAN port (or a WLAN to LAN adapter)
* Extra WLAN Router (if you are not sure if LAN & WLAN is not on the same network at location)
* One or two USB SD card adapters
* One or two USB-C to USB-A adapters
* Some Tape, Marker & Pens come always handy (also for participants to wirte down seed & passwords)

# Organisation Tasks

Which of the follwoing organisation tasks are relevant for you depends on which starting scenario you choose (see above). Here is the complete possible list with details:

## Buy all the Hardware

See the shopping list on the RaspiBlitz Github README - you need to buy all of those and also dont forget that every participant needs a short (about 1m) network cable.

From experience start ordering two weeks before the workshop (if you need to assembly) and minimum one week if you handing out hardware kits - even if you have Amazon Prime. There is always a shipment comming late - its a lot of packages.

## Assemble all the Hardware

Basically you follow the assemble instructions on the RaspiBlitz GuitHUb README. Think of a safe way to transport the assambled devices to the workshop location - HHDs like it soft.

# Prepare HDDs with Blockchain Data

This is the most time consuming part. Try it once to get a feel for how much time you need to prepare one HDD.

A prepared HDD is formatted in Ext4, named "BLOCKCHAIN" and contains at least the following

