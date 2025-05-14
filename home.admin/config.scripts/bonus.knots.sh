#!/bin/bash

# This is a template bonus script you can use to add your own app to RaspiBlitz.
# So just copy it within the `/home.admin/config.scripts` directory and
# rename it for your app - example: `bonus.myapp.sh`.
# Then go thru this script and delete parts/comments you dont need or add
# needed configurations.

# id string of your app (short single string unique in raspiblitz)
# should be same as used in name if script
APPID="knots" # one-word lower-case no-specials

# clean human readable version - will be displayed in UI
# just numbers only separated by dots (2 or 0.1 or 1.3.4 or 3.4.5.2)
VERSION="28.1"

FILEMASTER="28.x"
FILEMASTERTAG="28.1.knots20250305"

# the git repo to get the source code from for install
GITHUB_REPO="https://github.com/bitcoinknots/bitcoin"

# the github tag of the version of the source code to install
# can also be a commit hash
# if empty it will use the latest source version
GITHUB_TAG="v28.1.knots20250305"

# the github signature to verify the author
# leave GITHUB_SIGN_AUTHOR empty to skip verifying
GITHUB_SIGN_AUTHOR="luke-jr"
GITHUB_SIGN_PUBKEYLINK="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x1a3e761f19d2cc7785c5502ea291a2c45d0c504a"
GITHUB_SIGN_FINGERPRINT="A291A2C45D0C504A"


# BASIC COMMANDLINE OPTIONS
# you can add more actions or parameters if needed - for example see the bonus.rtl.sh
# to see how you can deal with an app that installs multiple instances depending on
# lightning implementation or testnets - but this should be OK for a start:
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status    -> status information (key=value)"
  echo "# bonus.${APPID}.sh on        -> install the app"
  echo "# bonus.${APPID}.sh off       -> uninstall the app"
  exit 1
fi

# echoing comments is useful for logs - but start output with # when not a key=value
echo "# Running: 'bonus.${APPID}.sh $*'"

# check & load raspiblitz config
source /mnt/hdd/raspiblitz.conf

#########################
# INFO
#########################

# this section is always executed to gather status information that
# all the following commands can use & execute on

# check if app is already installed
if bitcoin-cli --version | grep -q "knots"; then
  isInstalled=1
else
  isInstalled=0
fi

# check if service is running
isRunning=$(systemctl status bitcoind 2>/dev/null | grep -c 'active (running)')

if [ "${isInstalled}" == "1" ]; then

  # gather address info (whats needed to call the app)
  localIP=$(hostname -I | awk '{print $1}')
fi

# if the action parameter `status` was called - just stop here and output all
# status information as a key=value list
if [ "$1" = "status" ]; then
  echo "appID='${APPID}'"
  echo "version='${VERSION}'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "githubVersion='${GITHUB_TAG}'"
  echo "githubSignature='${GITHUB_SIGNATURE}'"
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  if [ "${isInstalled}" == "1" ]; then
    echo "localIP='${localIP}'"
  fi
  exit
fi

##########################
# ON / INSTALL
##########################

# This section takes care of installing the app.
# The template contains some basic steps but also look at other install scripts
# to see how special cases are solved.

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
    bitcoinOSversion="arm-linux-gnueabihf"
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
    bitcoinOSversion="aarch64-linux-gnu"
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
    bitcoinOSversion="x86_64-linux-gnu"
  fi


  # dont run install if already installed
  if [ ${isInstalled} -eq 1 ]; then
    echo "# ${APPID}.service is already installed."
    exit 1
  fi

  echo "# Installing ${APPID} ..."

  echo "# create user"
  # If the user is intended to be loeed in to add '--shell /bin/bash'
  # and copy the skeleton files
  sudo adduser --system --group --shell /bin/bash --home /home/${APPID} ${APPID} || exit 1
  # copy the skeleton files for login
  sudo -u ${APPID} cp -r /etc/skel/. /home/${APPID}/


  # make sure needed debian packages are installed
  # 'fbi' is here just an example - change to what you need or delete
  echo "# install from tarball"
  sudo apt install -y gpg wget

  # download source code and verify
  # BACKGROUND is that now you download the code from github, reset to a given version tag/commit,
  # verify the author. If you app provides its source/binaries in another way, may check
  # other install scripts to see how that implement code download & verify.
  echo "# download the tarball & verify"
  mkdir /home/${APPID}/${APPID}
  sudo -u ${APPID} wget "https://bitcoinknots.org/files/${FILEMASTER}/${FILEMASTERTAG}/bitcoin-${FILEMASTERTAG}-${bitcoinOSversion}.tar.gz" -P /home/${APPID}/${APPID}
  sudo -u ${APPID} wget "https://bitcoinknots.org/files/${FILEMASTER}/${FILEMASTERTAG}/SHA256SUMS" -P /home/${APPID}/${APPID}
  sudo -u ${APPID} wget "https://bitcoinknots.org/files/${FILEMASTER}/${FILEMASTERTAG}/SHA256SUMS.asc" -P /home/${APPID}/${APPID}
  
  echo "# Receive signer keys"
  curl -s "https://api.github.com/repos/bitcoinknots/guix.sigs/contents/builder-keys" |
    jq -r '.[].download_url' | while read url; do curl -s "$url" | sudo -u ${APPID} gpg --import; done
  
  echo "Verify bin"
  cd /home/${APPID}/${APPID}
  sudo -u ${APPID} gpg --verify SHA256SUMS.asc SHA256SUMS
  sudo -u ${APPID} sha256sum -c SHA256SUMS --ignore-missing


  # stop bitcoind
  sudo systemctl stop bitcoind
  cd /usr/local/bin/
  sudo rm bitcoin*

  # install the app
  cd /home/${APPID}/${APPID}
  sudo -u ${APPID} tar -xf bitcoin-${FILEMASTERTAG}-${bitcoinOSversion}.tar.gz
  cd /home/${APPID}/${APPID}/bitcoin-${FILEMASTERTAG}

  sudo cp bin/bitcoin* /usr/local/bin/

  # mark app as installed in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "on"

  # start app (only when blitz is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    sudo systemctl --no-block start bitcoind
    echo "# OK - the bitcoind.service is now started"
  fi

  echo "bitcoind can take a lot of time to restart because of the blocks verification, please be patient."
  exit 0

fi

###########################################
# OFF / UNINSTALL
###########################################

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# stop bitcoind and reinstall Core"
  sudo systemctl stop bitcoind 2>/dev/null

  echo "# delete user"
  sudo userdel -rf ${APPID}

  echo "# mark app as uninstalled in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "off"

  echo "reinstall core"
  cd /usr/local/bin
  sudo rm bitcoin*
  sudo -u admin /home/admin/config.scripts/bitcoin.install.sh install
  sudo systemctl restart bitcoind

  echo "# OK - app should be uninstalled now"
  exit 0

fi

echo "# FAIL - Unknown Parameter $1"
exit 1