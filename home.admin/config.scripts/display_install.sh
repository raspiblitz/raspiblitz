
echo "Press ENTER to install LCD and reboot ..."
read key
echo "stopping services ... (please wait)"
echo "- background"
sudo systemctl stop background 2>/dev/null
echo "- lnd"
sudo systemctl stop lnd.service 2>/dev/null
echo "- blockchain"
sudo systemctl stop bitcoind.service 2>/dev/null
# *** Display selection ***
dialog --title "Display" --yesno "Are you using the default display available from Amazon?\nSelect 'No' if you are using the Swiss version from play-zone.ch!" 6 80
defaultDisplay=$?
if [ "${defaultDisplay}" = "0" ]; then
  # *** RASPIBLITZ / LCD (at last - because makes a reboot) ***
  # based on https://www.elegoo.com/tutorial/Elegoo%203.5%20inch%20Touch%20Screen%20User%20Manual%20V1.00.2017.10.09.zip
  
  echo "--> LCD DEFAULT"
  cd /home/admin/
  sudo apt-mark hold raspberrypi-bootloader
  git clone https://github.com/goodtft/LCD-show.git
  sudo chmod -R 755 LCD-show
  sudo chown -R admin:admin LCD-show
  cd LCD-show/
  sudo ./LCD35-show
else
  # Download and install the driver
  # based on http://www.raspberrypiwiki.com/index.php/3.5_inch_TFT_800x480@60fps
  echo "--> LCD ALTERNATIVE"
  cd /boot
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
