#!/bin/sh

# name of torrentfile = name of directory in torrent
torrent="raspiblitz-hdd-2018-07-16"

echo ""
echo "*** Checking HDD ***"
mountOK=$(df | grep -c /mnt/hdd)
if [ ${mountOK} -eq 1 ]; then
  # HDD is mounted
  if [ -d "/mnt/hdd/bitcoin" ]; then
    # HDD has already content 
    echo "It seems that HDD has already content. Try to continue with ./finishHDD.sh"
  else
    # HDD is empty - download HDD content
    echo "OK - HDD is ready."
    echo ""
    echo "*** Downloading HDD ***"
    tmpfile=$(mktemp)
    chmod a+x $tmpfile
    echo "killall transmission-cli" > $tmpfile
    sudo transmission-cli ./assets/$torrent.torrent -D -w /mnt/hdd -f $tmpfile
    echo ""
    echo "*** Moving Files ***"
    echo "moving files ..."
    mv /mnt/hdd/$torrent/* /mnt/hdd
    rm -R /mnt/hdd/$torrent
    echo ""

    # set SetupState
    echo "50" > /home/admin/.setup
    
    echo "*** Next Step  ***"
    echo "You can now use this HDD as a source to copy the Blockchain during the setup of another RaspiBlitz."
    sleep 4

    # continue setup
    ./60finishHDD.sh

  fi
else
  # HDD is not available yet
  echo "*** Mount HDD on /mnt/hdd first ***"
fi
