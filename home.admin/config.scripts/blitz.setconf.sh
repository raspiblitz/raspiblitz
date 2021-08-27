#!/bin/bash

EDITFILE="$1"
USER="$2"
if [ ${#USER} -eq 0 ];then
  USER="admin"
fi
if [ ${#EDITFILE} -eq 0 ]; then
  echo "# Please specify a file to edit"
else
  echo "Opening $EDITFILE"
fi

# temp conf
conf=$(mktemp -p /dev/shm/)

# trap it
trap 'rm -f $conf' 0 1 2 5 15

dialog \
--title "Editing the $EDITFILE" \
--editbox "$EDITFILE" 200 200 2> "$conf"

# make decision
pressed=$?
case $pressed in
  0)
    dialog --title "Finished editing" \
    --msgbox "
Saving to:
$EDITFILE" 7 56
    sudo -u $USER tee "$EDITFILE" 1>/dev/null < "$conf"
    shred "$conf"
    exit 0;;
  1)
    shred "$conf"
    dialog --title "Finished editing" \
    --msgbox "
Cancelled editing:
$EDITFILE" 7 56
    echo "# Cancelled"
    exit 1;;
  255)
    shred "$conf"
    [ -s "$conf" ] &&  cat "$conf" || echo "ESC pressed."
    exit 1;;
esac