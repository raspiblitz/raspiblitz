#!/bin/bash
# much thx to frennkie working the prototype on this
# based on https://gist.github.com/frennkie/4d99cb35a3c62033a535564220c11150
# see issue: https://github.com/rootzoll/raspiblitz/issues/646
# to work it needs to be based on Raspbian Desktop base image

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "STILL EXPERIMENTAL - NOT FINISHED"
 echo "the touch screen feature"
 echo "blitz.touchscreen.sh [on|off]"
 exit 1
fi

# update install sources
echo "make sure dependencies are installed ..."
sudo apt-get install -y unclutter xterm
echo ""

###################
# SWITCH ON
###################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turn ON: Touchscreen"
  sudo raspi-config nonint do_boot_behaviour B4

  sudo sed -i s'/autologin-user=root/autologin-user=pi/' /etc/lightdm/lightdm.conf
  sudo sed -i s'/--autologin root/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf

  mv /etc/xdg/lxsession/LXDE-pi/autostart /etc/xdg/lxsession/LXDE-pi/autostart.bak
  cat << EOF | sudo tee /etc/xdg/lxsession/LXDE-pi/autostart >/dev/null
@xscreensaver -no-splash
@unclutter -idle 0
@sh /home/pi/autostart.sh
EOF

  # editing autostart.sh
  cat << EOF | sudo tee /home/pi/autostart.sh >/dev/null
#!/bin/sh
sleep 1
/usr/bin/python3 /home/admin/00infoLCDTK.py
EOF
  sudo chmod a+x /home/pi/autostart.sh
  sudo chown pi:pi /home/pi/autostart.sh

  # Remove 00infoLCD.sh from .bashrc of pi user
  sudo sed -i s'/exec $SCRIPT/#exec $SCRIPT/' /home/pi/.bashrc

  echo "OK - a restart is needed: sudo shutdown -r now"

fi

###################
# SWITCH OFF
###################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turn OFF: Touchscreen"
  sudo raspi-config nonint do_boot_behaviour B2

  # add again 00infoLCD.sh to .bashrc of pi user
  sudo sed -i s'/#exec $SCRIPT/exec $SCRIPT/' /home/pi/.bashrc

fi
