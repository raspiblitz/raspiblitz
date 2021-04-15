#!/bin/bash
# see issue: https://github.com/rootzoll/raspiblitz/issues/646
# and issue: https://github.com/rootzoll/raspiblitz/issues/809
# to work it needs to be based on Raspbian Desktop base image
# to check debug logs: sudo cat /home/pi/.cache/lxsession/LXDE-pi/run.log

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "STILL EXPERIMENTAL - NOT FINISHED"
 echo "the Blitz-Touch-User-Interface (BlitzTUI) feature"
 echo "blitz.touchscreen.sh [on|off|calibrate|update]"
 exit 1
fi

###################
# SWITCH ON
###################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "# Turn ON: Touchscreen"

  # check that display class is `lcd`
  if [ "${displayClass}" != "lcd" ]; then
    echo "# displayClass(${displayClass}) is not supported for touchscreen"
    echo "error='not supported'"
    exit 1
  fi

  echo "# make sure hdmi_force_hotplug is deactivated"
  sudo sed -i '/^hdmi_force_hotplug=/d' /boot/config.txt 2>/dev/null

  # update install sources
  echo "making sure system dependencies are installed"
  sudo apt-get update >/dev/null
  sudo apt-get install -y unclutter xterm python3-pyqt5 >/dev/null
  sudo apt-get install -y xfonts-terminus >/dev/null
  sudo apt-get install -y xinput-calibrator 

  # check if python3 env exists - if not install it
  if [ ! -d /home/admin/python3-env-lnd ]; then
    echo "installing Python3 virtual env"
    python3 -m venv --system-site-packages /home/admin/python3-env-lnd
    /home/admin/python3-env-lnd/bin/python3 -m pip install grpcio grpcio-tools googleapis-common-protos pathlib2
  fi

  echo "installing BlitzTUI (including python dependencies)"
  /home/admin/python3-env-lnd/bin/pip install /home/admin/raspiblitz/home.admin/BlitzTUI/ 

  # make sure lndlibs are patched for compatibility for both Python2 and Python3
  if ! grep -Fxq "from __future__ import absolute_import" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
    sed -i -E '1 a from __future__ import absolute_import' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
  fi

  if ! grep -Eq "^from . import.*" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
    sed -i -E 's/^(import.*_pb2)/from . \1/' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
  fi

  # switch to desktop login
  sudo raspi-config nonint do_boot_behaviour B4 >/dev/null 2>&1

  # set user pi user for autostart
  sudo sed -i 's/^autologin-user=.*/autologin-user=pi/g' /etc/lightdm/lightdm.conf
  
  # disable display-setup script
  if grep -Eq "^display-setup-script=" /etc/lightdm/lightdm.conf; then
    sed -i -E 's/^(display-setup-script=.*)/#\1/' /etc/lightdm/lightdm.conf
  fi
  
  sudo sed -i 's/--autologin root/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf
  sudo sed -i 's/--autologin admin/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf

  # remove welcome wizard
  sudo rm -rf /etc/xdg/autostart/piwiz.desktop

  if [ -f /etc/xdg/lxsession/LXDE-pi/autostart ]; then
    sudo mv /etc/xdg/lxsession/LXDE-pi/autostart /etc/xdg/lxsession/LXDE-pi/autostart.bak
  fi
  # write new LXDE autostart config
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
/home/admin/python3-env-lnd/bin/blitz-tui --debug
EOF
  sudo chmod a+x /home/pi/autostart.sh
  sudo chown pi:pi /home/pi/autostart.sh

  # Remove 00infoLCD.sh from .bashrc of pi user
  sudo sed -i 's/^exec $SCRIPT/#exec $SCRIPT/' /home/pi/.bashrc

  # adapt design by changing openbox settings
  sudo sed -i -E 's/<weight>Normal</<weight>Bold</g' /etc/xdg/openbox/lxde-pi-rc.xml
  sudo sed -i -E 's/<name>PibotoLt</<name>Arial</g' /etc/xdg/openbox/lxde-pi-rc.xml
  sudo sed -i -E 's/window.active.title.bg.color: #87919B/window.active.title.bg.color: #000046/' /usr/share/themes/PiXflat/openbox-3/themerc
  sudo sed -i -E 's/window.inactive.title.bg.color: #EEEFEE/window.inactive.title.bg.color: #000046/' /usr/share/themes/PiXflat/openbox-3/themerc

  # remove minimize, maximize, close from titlebar
  sudo sed -i -E 's/titleLayout>LIMC/titleLayout>L/g' /etc/xdg/openbox/lxde-pi-rc.xml

  echo "make sure pi is member of lndreadonly and lndinvoice"
  sudo /usr/sbin/usermod --append --groups lndinvoice pi
  sudo /usr/sbin/usermod --append --groups lndreadonly pi

  echo "make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/pi/.lnd" ]]; then
    sudo rm -rf "/home/pi/.lnd"                          # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/pi/.lnd"  # and create symlink
  fi

  # rotate touchscreen based on if LCD is rotated
  if [ "${lcdrotate}" = "0" ]; then
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
  else
    echo "LCD is rotated into default - no touchscreen rotate"
  fi

  # mark touchscreen as switched ON in config
  if [ ${#touchscreen} -eq 0 ]; then
    echo "touchscreen=0" >> /mnt/hdd/raspiblitz.conf
  fi
  sudo sed -i 's/^touchscreen=.*/touchscreen=1/g' /mnt/hdd/raspiblitz.conf

  echo "OK - a restart is needed: sudo shutdown -r now"
  exit 0

fi

###################
# UPDATE CODE
###################

if [ "$1" = "update" ]; then
  echo "updating BlitzTUI (including python dependencies) ..."
  sudo /home/admin/python3-env-lnd/bin/pip install /home/admin/raspiblitz/home.admin/BlitzTUI/
  exit 0
fi

###################
# CALIBRATE
###################

if [ "$1" = "calibrate" ]; then
  
  # check that touchscreen is on
  if [ "${touchscreen}" == "1" ]; then
    echo "# calibrating touchscreen ..."
  else
    echo "error='not installed'"
    exit 1
  fi

  # run calibrate screen
  sudo rm /tmp/99-calibration.conf 2>/dev/null
  sudo -u pi DISPLAY=:0.0 xinput_calibrator --output-filename /tmp/99-calibration.conf
  
  # check if calibration was done of user
  calibrationDone=$(sudo ls /tmp/99-calibration.conf 2>/dev/null | grep -c "99-calibration.conf")
  if [ ${calibrationDone} -eq 0 ]; then
    echo "error='aborted'"
    exit 1
  fi

  # copy the results over as configuration
  sudo mv /tmp/99-calibration.conf /etc/X11/xorg.conf.d/99-calibration.conf

  # restart touchscreen with new calibration
  if [ "$2" == "norestart" ]; then
    echo "# skipping touchscreen restart"
  else
    echo "# restarting touchscreen"
    sudo init 3
    sleep 3
    sudo init 5
  fi

  echo "# OK done"
  exit 0
fi

###################
# SWITCH OFF
###################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turn OFF: Touchscreen"

  # switch back to console login
  echo "switching back to console mode on boot"
  sudo raspi-config nonint do_boot_behaviour B2 >/dev/null 2>&1

  # make sure hdmi_force_hotplug=1 is added again to config.txt
  sudo sed -i '/^hdmi_force_hotplug=/d' /boot/config.txt 2>/dev/null
  echo "hdmi_force_hotplug=1" >> /boot/config.txt

  # set user pi user for autostart
  # TODO(frennkie/rootzoll) what should happen here? This does the same as "on".
  sudo sed -i 's/--autologin root/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf
  sudo sed -i 's/--autologin admin/--autologin pi/' /etc/systemd/system/getty@tty1.service.d/autologin.conf

  # move back old LXDE autostart config
  sudo rm -f /etc/xdg/lxsession/LXDE-pi/autostart
  if [ -f /etc/xdg/lxsession/LXDE-pi/autostart.bak ]; then
    sudo mv -f /etc/xdg/lxsession/LXDE-pi/autostart.bak /etc/xdg/lxsession/LXDE-pi/autostart
  fi

  # add again 00infoLCD.sh to .bashrc of pi user
  sudo sed -i s'/^#exec $SCRIPT/exec $SCRIPT/' /home/pi/.bashrc

  # remove old pi autostart
  sudo rm -f /home/pi/autostart.sh

  # delete possible touchscreen rotate
  sudo rm -f /etc/X11/xorg.conf.d/40-libinput.conf >/dev/null

  # mark touchscreen as switched OFF in config
  sudo sed -i 's/^touchscreen=.*/touchscreen=0/g' /mnt/hdd/raspiblitz.conf

  echo "OK - a restart is needed: sudo shutdown -r now"
  exit 0

fi
