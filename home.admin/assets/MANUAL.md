% RASPIBLITZ(1) raspiblitz 1.7.1
% The Raspiblitz Developers
% October 2021


# NAME

Raspiblitz - control your bitcoin node


# SYNOPSIS

**COMMAND** [*OPTION*]


# DESCRIPTION

**raspiblitz** is one of the command that can be used on the fully featured bitcoin and lightning node written in shellscript and python. It is a node manager to faciliate and speed up usage and interaction with the bitcoin blockchain and peering with other lightning nodes. This manual describe commom functions that can be called when using the Raspiblitz software.


# OPTIONS

## MENUS

**blitz**, **raspiblitz**, **menu**, **bash**
: Display the main menu.

**repair**
: Display the repair menu.

## CHECK

**version**
: Displays the software version.

**status**
: Display the info screen.

**sourcemode**
: Copy blockchain source modus.

**check**
: Check if Blitz configuration files are correct.

**debug** <*-l*>
: Print debug logs, optionally create a shareable link with the *-l* option.

**patch**
: Sync scripts with latest set github and branch.

**github**
: Jumping directly into the options to change branch/repo/pr.

## POWER

**restart**
: Restart the node safely.

**off**
Shutodwn the node safely.

## DISPLAY

**hdmi**
: Switch video output to HDMI and restart the node.

**lcd**
: switch video output to LCD and restart the node.

**headless**
: Switch video output to HEADLESS and restart the node.

## BTC TX

**torthistx** [TXID]
: Broadcast transaction through Tor to Blockstreams API and into the network.

**gettx** [TXID]
: Retrieve transaction from mempool or blockchain and print as JSON.

**watchtx** [TXID] <*WAIT_N_CONFS*> <*SLEEP_TIME*>
: retrieve transaction from mempool or blockchain until certain confirmation target.

## LND

**balance**
: Your satoshi balance.

**channels**
: Your lightning channels.

**fwdreport**
: Show forwarding report.

## USERS

**bos**
: Switch to the Balance of Satoshis user.

**chantools**
: Switch to the Chantools user.

**lit**
: Switch to the Lightning Terminal user.

**jm**
: Switch to the Joinmarket user.

**pyblock**
: Switch to the PyBlock user.

## EXTRAS

**release**
: Prepare for a blitz release

**whitepaper**
: Download the whitepaper from the blockchain to admin home folder.

**notifyme** <*success|fail*>
: Wrapper for blitz.notify.sh that will send a notification using the configured method and settings.

**qr** [STRING]
: QR encodes the string and send to stout.


# EXIT VALUE
**0**
: Success

**1**
: Fail


# BUGS

Possible.

First take a look at the reported issues on https://github.com/raspiblitz/issues and use keywords on the search bar. If you can't find a solution, open a new issue.


# SEE ALSO

bash(1), regex(7), sed(1), awk(1), read(2), find(1)


# COPYRIGHT

Copyright (c) 2021 The RaspiBlitz developers
