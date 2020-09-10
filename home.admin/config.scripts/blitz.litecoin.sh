# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# installing and changing to litecoin as base blockchain"
 echo "# IMPORTANT: JUST MAKE CHANGE DURING SETUP"
 echo "# blitz.litecoin.sh [on]"
 echo "error='missing parameters'"
 exit 1
fi

isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
if [ ${isRaspbian} -eq 0]; then

  echo "error='litecoin is only avaulable for raspbian realease'"
  exit 1

else

  echo ""
  echo "# *** LITECOIN ***"
  # based on https://medium.com/@jason.hcwong/litecoin-lightning-with-raspberry-pi-3-c3b931a82347

  # set version (change if update is available)
  litecoinVersion="0.18.1"
  litecoinSHA256="59b73bc8f034208295634da56a175d74668b07613cf6484653cb467deafb1d52"

  # cleaning download folder 
  sudo rm -r /home/admin/download 1>/dev/null
  sudo -u admin mkdir -p /home/admin/download
  cd /home/admin/download

  # download
  binaryName="litecoin-${litecoinVersion}-arm-linux-gnueabihf.tar.gz"
  sudo -u admin wget https://download.litecoin.org/litecoin-${litecoinVersion}/linux/${binaryName} 1>/dev/null

  # check download
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  if [ "${binaryChecksum}" != "${litecoinSHA256}" ]; then
    echo "# !!! FAIL !!! Downloaded LITECOIN BINARY not matching SHA256 checksum: ${litecoinSHA256}"
    echo "error='checksum failed'"
    exit 1
  fi

  # install
  sudo -u admin tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin litecoin-${litecoinVersion}/bin/*
  installed=$(sudo -u admin litecoind --version | grep "${litecoinVersion}" -c)
  if [ ${installed} -lt 1 ]; then

    echo ""
    echo "# !!! BUILD FAILED --> Was not able to install litecoind version(${litecoinVersion})"
    echo "error='install failed'"
    exit 1

  else
  
    # set network info
    sed -i "s/^network=.*/network=litecoin/g" ${infoFile}
    sed -i "s/^chain=.*/chain=main/g" ${infoFile}
    
    ###### OPTIMIZE IF RAM >1GB
    kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
    if [ ${kbSizeRAM} -gt 1500000 ]; then
        echo "Detected RAM >1GB --> optimizing ${network}.conf"
        sudo sed -i "s/^dbcache=.*/dbcache=512/g" /home/admin/assets/litecoin.conf
        sudo sed -i "s/^maxmempool=.*/maxmempool=300/g" /home/admin/assets/litecoin.conf
    fi

  fi
fi