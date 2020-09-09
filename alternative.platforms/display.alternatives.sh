# To run this script on your RaspiBlitz, copy the following line to the ssh terminal (after the #):
# wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/alternative.platforms/display.alternatives.sh && sudo bash display.alternatives.sh

echo "Detect Base Image ..." 
baseImage="?"
isDietPi=$(uname -n | grep -c 'DietPi')
isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
isArmbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Debian')
isUbuntu=$(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu')
if [ ${isRaspbian} -gt 0 ]; then
  baseImage="raspbian"
fi
if [ ${isArmbian} -gt 0 ]; then
  baseImage="armbian"
fi 
if [ ${isUbuntu} -gt 0 ]; then
baseImage="ubuntu"
fi
if [ ${isDietPi} -gt 0 ]; then
  baseImage="dietpi"
fi
if [ "${baseImage}" = "?" ]; then
  cat /etc/os-release 2>/dev/null
  echo "!!! FAIL !!!"
  echo "Base Image cannot be detected or is not supported."
  exit 1
else
  echo "OK running ${baseImage}"
fi


OPTIONS=(GPIO "Install the default display available from Amazon" \
        HDMI "Install the 3.5\" HDMI display from Aliexpress" \
        SWISS "Install the Swiss version from play-zone.ch"
)
CHOICE=$(dialog --backtitle "RaspiBlitz - Display Install" --clear --title "Display Install" --menu "Choose a your diplay:" 10 70 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

if [ "${CHOICE}" = "GPIO" ]; then
  # *** RASPIBLITZ / LCD (at last - because makes a reboot) ***
  # based on https://www.elegoo.com/tutorial/Elegoo%203.5%20inch%20Touch%20Screen%20User%20Manual%20V1.00.2017.10.09.zip
  # revert font change
  # based on https://www.raspberrypi-spy.co.uk/2014/04/how-to-change-the-command-line-font-size/
  sudo sed -i 's/FONTFACE="TerminusBold"/FONTFACE="Fixed"/' /etc/default/console-setup
  sudo sed -i 's/FONTSIZE="12x24"/FONTSIZE="8x16"/' /etc/default/console-setup 
 
  cd /home/admin/
  rm -r LCD-show
  git clone https://github.com/goodtft/LCD-show.git
  sudo chmod -R 755 LCD-show
  sudo chown -R admin:admin LCD-show
  cd LCD-show/
  
  if [ "${baseImage}" != "dietpi" ]; then
    echo "--> LCD DEFAULT"
    sudo apt-mark hold raspberrypi-bootloader
    sudo ./LCD35-show
  else
    sudo rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
    sudo mkdir /etc/X11/xorg.conf.d
    sudo cp ./usr/tft35a-overlay.dtb /boot/overlays/
    sudo cp ./usr/tft35a-overlay.dtb /boot/overlays/tft35a.dtbo
    sudo cp -rf ./usr/99-calibration.conf-35  /etc/X11/xorg.conf.d/99-calibration.conf
    sudo cp -rf ./usr/99-fbturbo.conf  /usr/share/X11/xorg.conf.d/
    sudo cp ./usr/cmdline.txt /DietPi/
    sudo cp ./usr/inittab /etc/
    sudo cp ./boot/config-35.txt /DietPi/config.txt
    echo "***"
    echo "reboot with \`sudo reboot\` to make the LCD work"
    echo "***"
    exit
  fi

elif [ "${CHOICE}" = "HDMI" ]; then
  echo "Installing the 3.5\" HDMI display from Aliexpress"
  
  # based on http://www.lcdwiki.com/3.5inch_HDMI_Display-B
  rm -r LCD-show
  git clone https://github.com/goodtft/LCD-show.git
  sudo chmod -R 755 LCD-show
  cd LCD-show/
  #sudo ./MPI3508-show  
  sudo rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
  
  if [ "${baseImage}" != "dietpi" ]; then
    sudo cp -rf ./boot/config-35-480X320.txt /boot/config.txt  
    sudo cp ./usr/cmdline.txt /boot/
  else 
    sudo cp -rf ./boot/config-35-480X320.txt /DietPi/config.txt 
    sudo cp ./usr/cmdline.txt /DietPi/
  fi
  sudo cp ./usr/inittab /etc/
  sudo cp -rf ./usr/99-fbturbo.conf-HDMI /usr/share/X11/xorg.conf.d/99-fbturbo.conf 
  sudo mkdir -p /etc/X11/xorg.conf.d 
  sudo cp -rf ./usr/99-calibration.conf-3508 /etc/X11/xorg.conf.d/99-calibration.conf
  # based on https://www.raspberrypi-spy.co.uk/2014/04/how-to-change-the-command-line-font-size/
  sudo sed -i 's/FONTFACE="Fixed"/FONTFACE="TerminusBold"/' /etc/default/console-setup
  sudo sed -i 's/FONTSIZE="8x16"/FONTSIZE="12x24"/' /etc/default/console-setup 
  echo "***"
  echo "reboot with \`sudo reboot\` to make the LCD work"
  echo "***"
  exit

elif [ "${CHOICE}" = "SWISS" ]; then
  # Download and install the driver
  # based on http://www.raspberrypiwiki.com/index.php/3.5_inch_TFT_800x480@60fps
  echo "--> LCD ALTERNATIVE"
  if [ "${baseImage}" != "dietpi" ]; then
    cd /boot
  else
    cd /DietPi
  fi
  sudo wget http://www.raspberrypiwiki.com/download/RPI-HD-35-INCH-TFT/dt-blob-For-3B-plus.bin
  sudo mv dt-blob-For-3B-plus.bin dt-blob.bin
  cat <<EOF >> config.txt
dtparam=spi=off
dtparam=i2c_arm=off
# Set screen size and any overscan required
overscan_left=0
overscan_right=0
overscan_top=0
overscan_bottom=0
framebuffer_width=800
framebuffer_height=480
enable_dpi_lcd=1
display_default_lcd=1
dpi_group=2
dpi_mode=87
dpi_output_format=0x6f015
# set up the size to 800x480
hdmi_timings=480 0 16 16 24 800 0 4 2 2 0 0 0 60 0 32000000 6
#rotate screen
display_rotate=3
dtoverlay=i2c-gpio,i2c_gpio_scl=24,i2c_gpio_sda=23
fi
EOF
    init 6
fi