#!/bin/bash
sudo killall -3 fbi
shred /home/admin/qr.png 2> /dev/null
rm -f /home/admin/qr.png 2> /dev/null
