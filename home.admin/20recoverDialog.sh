#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# show password info dialog
resetAlsoPasswordB=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c "rpcpassword=passwordB")
if [ ${resetAlsoPasswordB} -eq 0 ]; then
  # just password A
  dialog --backtitle "RaspiBlitz - Recover Setup" --msgbox "Your previous RaspiBlitz config was recovered.

You need to set a new Password A:
A) Master User Password

Passwords B & C stay as before.

Follow Password Rules: Minimal of 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 14 52

  # call set password a script
  sudo /home/admin/config.scripts/blitz.setpassword.sh a

else
  # password A + B
  dialog --backtitle "RaspiBlitz - Recover Setup" --msgbox "Your previous RaspiBlitz config was recovered.

You need to set a new Password A & B:
A) Main User Password (SSH, WebUI, ..)
B) RPC & APP Password (Additional Apps, ..)

Passwords C (for your Lightning wallet) stays to the password you set before.

Follow Password Rules: Minimal of 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 17 52

  # call set password a script
  sudo /home/admin/config.scripts/blitz.setpassword.sh a
  sudo /home/admin/config.scripts/blitz.setpassword.sh b

fi

# sucess info dialog
dialog --backtitle "RaspiBlitz" --msgbox "OK - password A was set\nfor all users pi, admin, root & bitcoin" 6 52

# activate lnd & bitcoin service
echo "Enabling Services"
sudo systemctl daemon-reload
sudo systemctl enable lnd.service
sudo systemctl enable ${network}d.service
if [ "${rtlWebinterface}" = "on" ]; then
  sudo systemctl enable RTL
fi
if [ "${loop}" = "on" ]; then
  sudo systemctl enable loopd
fi
if [ "${BTCRPCexplorer}" = "on" ]; then
  sudo systemctl enable btc-rpc-explorer
fi
if [ "${ElectRS}" = "on" ]; then
  sudo systemctl enable electrs
fi

# remove flag that freshly recovered
sudo rm /home/admin/raspiblitz.recover.info

# when auto-unlock is activated then Password C is needed to be restored on SD card
if [ "${autoUnlock}" = "on" ]; then

  # reset auto-unlock feature
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "You had the Auto-Unlock feature enabled.

In the next dialog you need to re-enter your
ACTUAL/OLD Password C to re-activate the
Auto-Unlock feature. Enter a empty password
to deactivate the Auto-Unlock feature.
" 10 52
  echo "Activating Auto-Unlock (please wait) .."
  sudo /home/admin/config.scripts/lnd.autounlock.sh on
  dialog --backtitle "RaspiBlitz" --pause "  FINAL REBOOT IS NEEDED." 8 52 5

else
  dialog --backtitle "RaspiBlitz" --pause "  OK - Passwords set.\n  FINAL REBOOT IS NEEDED." 9 52 5
fi

sudo /home/admin/XXshutdown.sh reboot