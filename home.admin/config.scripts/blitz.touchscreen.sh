#!/bin/bash
# much thx to frennkie working the prototype on this
# based on https://gist.github.com/frennkie/4d99cb35a3c62033a535564220c11150
# see issue: https://github.com/rootzoll/raspiblitz/issues/646
# to work it needs to be based on Raspbian Desktop base image

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "STILL EXPERIMENTAL - NOT FINISHED"
 echo "the touch screen feature"
 echo "blitz.touchscreen.sh [on|off]"
 exit 1
fi


###################
# SWITCH ON
###################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turn ON: Touchscreen"

  # update install sources
  echo "make sure dependencies are installed ..."
  sudo apt-get update
  sudo apt-get install -y unclutter xterm
  # TODO(frennkie) should this be removed when running "off"?
  sudo apt-get install -y python3-pyqt5
  echo ""

  echo "installing BlitzTUI (including dependencies)"
  /home/admin/python3-env-lnd/bin/pip install BlitzTUI
  echo ""

  # patch lndlibs for Python3
  if ! grep -Fxq "from __future__ import absolute_import" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
    sed -i -E '1 a from __future__ import absolute_import' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
  fi

  if ! grep -Eq "^from . import.*" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
    sed -i -E 's/^(import.*_pb2)/from . \1/' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
  fi

  # switch to desktop login
  sudo raspi-config nonint do_boot_behaviour B4

  # set user pi user for autostart
  sudo sed -i 's/^autologin-user=.*/autologin-user=pi/g' /etc/lightdm/lightdm.conf
  sudo sed -i 's/--autologin root/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf
  sudo sed -i 's/--autologin admin/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf

  # remove welcome wizard
  sudo rm -rf /etc/xdg/autostart/piwiz.desktop

  # write new LXDE autostart config
  sudo mv /etc/xdg/lxsession/LXDE-pi/autostart /etc/xdg/lxsession/LXDE-pi/autostart.bak
  cat << EOF | sudo tee /etc/xdg/lxsession/LXDE-pi/autostart >/dev/null
@unclutter -idle 0
@xset s noblank
@xset s off
@xset -dpms
@sh /home/pi/autostart.sh
EOF

  # editing autostart.sh
  cat << EOF | sudo tee /home/pi/autostart.sh >/dev/null
#!/bin/sh

unset QT_QPA_PLATFORMTHEME
/home/admin/python3-env-lnd/bin/blitz-tui
EOF
  sudo chmod a+x /home/pi/autostart.sh
  sudo chown pi:pi /home/pi/autostart.sh

  # Remove 00infoLCD.sh from .bashrc of pi user
  sudo sed -i s'/exec $SCRIPT/#exec $SCRIPT/' /home/pi/.bashrc

  # adapt design by changing openbox settings
  sudo sed -i -E 's/<weight>Normal</<weight>Bold</g' /etc/xdg/openbox/lxde-pi-rc.xml
  sudo sed -i -E 's/<name>PibotoLt</<name>Arial</g' /etc/xdg/openbox/lxde-pi-rc.xml
  sudo sed -i -E 's/window.active.title.bg.color: #87919B/window.active.title.bg.color: #000046/' /usr/share/themes/PiXflat/openbox-3/themerc
  sudo sed -i -E 's/window.inactive.title.bg.color: #EEEFEE/window.inactive.title.bg.color: #000046/' /usr/share/themes/PiXflat/openbox-3/themerc

  # remove minimize, maximize, close from titlebar
  sudo sed -i -E 's/titleLayout>LIMC/titleLayout>L/g' /etc/xdg/openbox/lxde-pi-rc.xml

  # Copy over the macaroons
  sudo mkdir -p /home/pi/.lnd/data/chain/bitcoin/mainnet/
  sudo chmod 700 /home/pi/.lnd/
  sudo ln -s /home/admin/.lnd/tls.cert /home/pi/.lnd/
  sudo cp /home/admin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon /home/pi/.lnd/data/chain/bitcoin/mainnet/
  sudo cp /home/admin/.lnd/data/chain/bitcoin/mainnet/invoice.macaroon /home/pi/.lnd/data/chain/bitcoin/mainnet/
  sudo chmod 600 /home/pi/.lnd/data/chain/bitcoin/mainnet/*.macaroon
  sudo chown -R pi:pi /home/pi/.lnd/

  # rotate touchscreen based on if LCD is rotated
  if [ "${lcdrotate}" = "1" ]; then
    echo "LCD is rotated into default - no touchscreen rotate"
  else
    echo "Activate Touchscreen Rotate"
    cat << EOF | sudo tee /etc/X11/xorg.conf.d/40-libinput.conf >/dev/null
Section "InputClass"
        Identifier "libinput touchscreen catchall"
        MatchIsTouchscreen "on"
        Option "CalibrationMatrix" "0 1 0 -1 0 1 0 0 1"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
EndSection
EOF
  fi

  # mark touchscreen as switched ON in config
  if [ ${#touchscreen} -eq 0 ]; then
    echo "touchscreen=0" >> /mnt/hdd/raspiblitz.conf
  fi
  sudo sed -i "s/^touchscreen=.*/touchscreen=1/g" /mnt/hdd/raspiblitz.conf

  echo "OK - a restart is needed: sudo shutdown -r now"

fi

###################
# SWITCH OFF
###################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turn OFF: Touchscreen"

  # switch back to console login
  sudo raspi-config nonint do_boot_behaviour B2

  # set user pi user for autostart
  sudo sed -i s'/--autologin root/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf
  sudo sed -i s'/--autologin admin/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf

  # move back old LXDE autostart config
  sudo rm /etc/xdg/lxsession/LXDE-pi/autostart
  sudo mv /etc/xdg/lxsession/LXDE-pi/autostart.bak /etc/xdg/lxsession/LXDE-pi/autostart

  # add again 00infoLCD.sh to .bashrc of pi user
  sudo sed -i s'/#exec $SCRIPT/exec $SCRIPT/' /home/pi/.bashrc

  # remove old pi autostart
  sudo rm /home/pi/autostart.sh

  # delete possible touchscreen rotate
  sudo rm /etc/X11/xorg.conf.d/40-libinput.conf >/dev/null

  # mark touchscreen as switched OFF in config
  sudo sed -i "s/^touchscreen=.*/touchscreen=0/g" /mnt/hdd/raspiblitz.conf

  echo "OK - a restart is needed: sudo shutdown -r now"

fi
