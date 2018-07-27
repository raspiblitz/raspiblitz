#!/bin/sh

# name of torrentfile = name of directory in torrent
torrent="raspiblitz-hdd-2018-07-16"
# size of a valid download (run on seed directory 'du -s ./[TORRENTDIRECTORY]')
torrentsize=231230512

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

    downloading=1
    retry=0
    while [ $downloading -eq 1 ]
    do
      echo "*** Downloading HDD ***"
      tmpfile=$(mktemp)
      chmod a+x $tmpfile
      echo "killall transmission-cli" > $tmpfile
      sudo transmission-cli ./assets/$torrent.torrent -D -et -w /mnt/hdd -f $tmpfile
      echo ""
      echo "*** Checking Download ***"
      echo "wait a moment"
      sleep 5
      downloadsize=$(sudo du -s /mnt/hdd/$torrent/ | awk '{print $1}' | tr -dc '0-9')
      if [ ${#downloadsize} -eq 0 ]; then 
        downloadsize=0
      fi
      # add some tolerance for checking 
      torrentsize="$(($torrentsize-1024000))"
      echo "download size is(${downloadsize})"
      if [ ${downloadsize} -lt ${torrentsize} ]; then
        echo ""
        echo "FAIL - download is not ${torrentsize}"
        retry=$(($retry+1))
        if [ ${retry} -gt 2 ]; then 
          echo "All Retry FAILED"
          downloading=0
        else
          echo "--> RETRY(${retry}) in 10 secs"
          sleep 10
          echo ""
        fi  
      else
        echo "OK - Download is complete"
        downloading=0
      fi
    done  
    if [ ${downloadsize} -lt ${torrentsize} ]; then
      sleep 3
      dialog --title " WARNING " --yesno "The download failed or is not complete. Do you want to clean all download data before you continue?" 6 57
      response=$?
      case $response in
        0) sudo rm -rf /mnt/hdd/$torrent ; sudo rm -rf /root/.config/transmission ;;
      esac
      # 
      ./00mainMenu.sh
      exit 1;
    fi
    echo ""

    echo "*** Moving Files ***"
    echo "moving files ..."
    sudo mv /mnt/hdd/$torrent /mnt/hdd/bitcoin
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
