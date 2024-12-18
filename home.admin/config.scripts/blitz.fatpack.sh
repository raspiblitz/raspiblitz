#!/bin/bash
# setup script - to be called by build_sdcard.sh or on a stopped minimal build sd card image

echo -e "\n*** FATPACK ***"

# check if su
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit 1
fi

# determine correct raspberrypi boot drive path (that easy to access when sd card is insert into laptop)
raspi_bootdir=""
if [ -d /boot/firmware ]; then
  raspi_bootdir="/boot/firmware"
elif [ -d /boot ]; then
  raspi_bootdir="/boot"
fi
echo "# raspi_bootdir(${raspi_bootdir})"

# determine if this is a early release candidate (use file not cache)
codeVersion=$(git -C /home/admin/raspiblitz branch --show-current)
isReleaseCandidate=0
if [[ "$codeVersion" == *"dev"* ]]; then
  isReleaseCandidate=1
fi
echo "# isReleaseCandidate(${isReleaseCandidate})"

# make sure LCD is on (default for fatpack)
/home/admin/config.scripts/blitz.display.sh set-display lcd

# check if sd card needs expansion before fatpack
source <(sudo /home/admin/config.scripts/blitz.bootdrive.sh status)
if [ "${needsExpansion}" == "1" ]; then

    echo "################################################"
    echo "# SD CARD NEEDS EXPANSION BEFORE FATPACK"
    echo "# this will be done now ... and trigger a reboot"
    echo "# after reboot run this script again"
    echo "################################################"

    # write a stop file to prevent full bootstrap
    # after fsexpand reboot
    touch ${raspi_bootdir}/stop

    # trigger fsexpand
    /home/admin/config.scripts/blitz.bootdrive.sh fsexpand

    # make sure this expand is not marked (because its not done after release)
    sed -i "s/^fsexpanded=.*/fsexpanded=0/g" /home/admin/raspiblitz.info

    echo "################################################"
    echo "# SD CARD GOT EXPANSION BEFORE FATPACK"
    echo "# triggering a reboot"
    echo "# after reboot run this script again"
    echo "################################################"

    # trigger reboot
    shutdown -h -r now
    exit 0
fi

apt_install() {
  sudo DEBIAN_FRONTEND=noninteractive apt install -y ${@}
  if [ $? -eq 100 ]; then
    echo "FAIL! apt failed to install needed packages!"
    echo ${@}
    exit 1
  fi
}

echo "# getting default user/repo from build_sdcard.sh"
sudo cp /home/admin/raspiblitz/build_sdcard.sh /home/admin/build_sdcard.sh
sudo chmod +x /home/admin/build_sdcard.sh 2>/dev/null
source <(sudo /home/admin/build_sdcard.sh -EXPORT)
branch="${githubBranch}"
echo "# branch(${branch})"
echo "# defaultAPIuser(${defaultAPIuser})"
echo "# defaultAPIrepo(${defaultAPIrepo})"
echo "# defaultWEBUIuser(${defaultWEBUIuser})"
echo "# defaultWEBUIrepo(${defaultWEBUIrepo})"
sleep 3

if [ "${defaultAPIuser}" == "" ] || [ "${defaultAPIrepo}" == "" ]; then
  echo "FAIL: missing defaultAPIuser or defaultAPIrepo"
  exit 1
fi

if [ "${defaultWEBUIuser}" == "" ] || [ "${defaultWEBUIrepo}" == "" ]; then
  echo "FAIL: missing defaultWEBUIuser or defaultWEBUIrepo"
  exit 1
fi

echo "* Adding nodeJS Framework ..."
/home/admin/config.scripts/bonus.nodejs.sh on || exit 1

echo "* Optional Packages (may be needed for extended features)"
apt_install qrencode secure-delete fbi msmtp unclutter xterm python3-pyqt5 xfonts-terminus python3-jinja2 socat libatlas-base-dev hexyl

echo "* Adding LND ..."
/home/admin/config.scripts/lnd.install.sh install || exit 1

echo "* Adding Core Lightning ..."
/home/admin/config.scripts/cl.install.sh install || exit 1

# *** AUTO UPDATE FALLBACK NODE LIST FROM INTERNET (only in fatpack)
echo "*** FALLBACK NODE LIST ***"
# see https://github.com/rootzoll/raspiblitz/issues/1888
sudo -u admin curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ -o /home/admin/fallback.bitnodes.nodes
# Fallback Nodes List from Bitcoin Core
sudo -u admin curl https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/seeds/nodes_main.txt -o /home/admin/fallback.bitcoin.nodes

# use dev branch when its an Release Candidate
if [ "${isReleaseCandidate}" == "1" ]; then
  echo "# RELEASE CANDIDATE: using development branches for WebUI & API"
  echo "* Adding Raspiblitz API (a)..."
  sudo /home/admin/config.scripts/blitz.web.api.sh on "${defaultAPIuser}" "${defaultAPIrepo}" "dev" || exit 1
  echo "* Adding Raspiblitz WebUI (a) ..."
  sudo /home/admin/config.scripts/blitz.web.ui.sh on "${defaultWEBUIuser}" "${defaultWEBUIrepo}" "master" || exit 1
else
  echo "* Adding Raspiblitz API (b) ..."
  sudo /home/admin/config.scripts/blitz.web.api.sh on "${defaultAPIuser}" "${defaultAPIrepo}" "blitz-${branch}" || exit 1
  echo "* Adding Raspiblitz WebUI (b) ..."
  sudo /home/admin/config.scripts/blitz.web.ui.sh on "${defaultWEBUIuser}" "${defaultWEBUIrepo}" "release/${branch}" || exit 1
fi

# set build code as new www default
sudo rm -r /home/admin/assets/nginx/www_public
mkdir -p /home/admin/assets/nginx/www_public
sudo cp -a /home/blitzapi/blitz_web/build/* /home/admin/assets/nginx/www_public
sudo chown admin:admin /home/admin/assets/nginx/www_public
sudo rm -r /home/blitzapi/blitz_web/build/*

echo "* Adding Code&Compile for WEBUI-APP: ALBYHUB"
/home/admin/config.scripts/bonus.albyhub.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: LNBITS"
/home/admin/config.scripts/bonus.lnbits.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: JAM"
/home/admin/config.scripts/bonus.jam.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: BTCPAYSERVER"
/home/admin/config.scripts/bonus.btcpayserver.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: RTL"
/home/admin/config.scripts/bonus.rtl.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: THUNDERHUB"
/home/admin/config.scripts/bonus.thunderhub.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: BTC RPC EXPLORER"
/home/admin/config.scripts/bonus.btc-rpc-explorer.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: MEMPOOL"
/home/admin/config.scripts/bonus.mempool.sh install || exit 1
echo "* Adding Code&Compile for WEBUI-APP: ELECTRS"
/home/admin/config.scripts/bonus.electrs.sh install || exit 1