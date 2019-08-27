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

# update install sources
echo "make sure dependencies are installed ..."
sudo apt-get install -y unclutter xterm
echo ""

###################
# SWITCH ON
###################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turn ON: Touchscreen"

  # switch to desktop login
  sudo raspi-config nonint do_boot_behaviour B4

  # set user pi user for autostart
  sudo sed -i "s/^autologin-user=.*/autologin-user=pi/g" /etc/lightdm/lightdm.conf
  sudo sed -i s'/--autologin root/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf
  sudo sed -i s'/--autologin admin/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf

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
sleep 1
/usr/bin/python3 /home/admin/00infoLCDTK.py
EOF
  sudo chmod a+x /home/pi/autostart.sh
  sudo chown pi:pi /home/pi/autostart.sh

  # Remove 00infoLCD.sh from .bashrc of pi user
  sudo sed -i s'/exec $SCRIPT/#exec $SCRIPT/' /home/pi/.bashrc

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
  sudp rm /etc/xdg/lxsession/LXDE-pi/autostart
  sudo mv /etc/xdg/lxsession/LXDE-pi/autostart.bak /etc/xdg/lxsession/LXDE-pi/autostart

  # add again 00infoLCD.sh to .bashrc of pi user
  sudo sed -i s'/#exec $SCRIPT/exec $SCRIPT/' /home/pi/.bashrc

  # remove old pi autostart
  sudo rm /home/pi/autostart.sh

  # mark touchscreen as switched OFF in config
  sudo sed -i "s/^touchscreen=.*/touchscreen=0/g" /mnt/hdd/raspiblitz.conf

  echo "OK - a restart is needed: sudo shutdown -r now"

fi
