# Installs package if not yet installed
if [ $(sudo dpkg-query -l | grep "ii  $1" | wc -l) = 0 ]; then
   sudo apt-get install $1 -y > /dev/null
fi
