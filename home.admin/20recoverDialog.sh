#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# show password info dialog
resetAlsoPasswordB=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf 2>/dev/null | grep -c "rpcpassword=passwordB")
resetAlsoPasswordC=$(sudo ls /mnt/hdd/passwordc.flag 2>/dev/null | grep -c ".flag")

if [ ${resetAlsoPasswordC} -gt 0 ]; then

  # password A + B + C
  dialog --backtitle "RaspiBlitz - Migration Setup" --msgbox "Your migration to RaspiBlitz is almost done.

You need to set a new Password A, B & C:
A) Main User Password (SSH, WebUI, ..)
B) RPC & APP Password (Additional Apps, ..)
C) Lightning Wallet Unlock Password

Follow Password Rules: Minimal of 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 17 52

  # call set password a script
  sudo /home/admin/config.scripts/blitz.setpassword.sh a
  dialog --backtitle "RaspiBlitz" --msgbox "OK - password A was set\nfor all users pi, admin, root & bitcoin" 6 52

  sudo /home/admin/config.scripts/blitz.setpassword.sh b
  dialog --backtitle "RaspiBlitz" --msgbox "OK - password B was set\nit will be used by additional apps you install." 6 52

  oldPasswordC=$(sudo cat /mnt/hdd/passwordc.flag)
  sudo /home/admin/config.scripts/blitz.setpassword.sh c $oldPasswordC
  if [ "$?" != "0" ]; then
    dialog --backtitle "RaspiBlitz - Setup" --msgbox "Please write down your Password C:\n${oldPasswordC}" 10 52
  else
    dialog --backtitle "RaspiBlitz" --msgbox "OK - password C was set\nuse it to unlock your Lightning Wallet after restarts." 8 52
  fi

elif [ ${resetAlsoPasswordB} -gt 0 ]; then

  # password A + B
  dialog --backtitle "RaspiBlitz - Migration Setup" --msgbox "Your migration to RaspiBlitz is almost done.

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
  dialog --backtitle "RaspiBlitz" --msgbox "OK - password A was set\nfor all users pi, admin, root & bitcoin" 6 52

  sudo /home/admin/config.scripts/blitz.setpassword.sh b
  dialog --backtitle "RaspiBlitz" --msgbox "OK - password B was set\nit will be used by additional apps you install." 6 52

else

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

# success info dialog
dialog --backtitle "RaspiBlitz" --msgbox "OK - password A was set\nfor all users pi, admin, root & bitcoin" 6 52

fi

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
sudo rm /home/admin/recover.flag

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