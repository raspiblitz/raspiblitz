#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "config script to install or remove the Let's Encrypt Client (ACME.SH)"
  echo "bonus.letsencrypt.sh [on|off]"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

ACME_LOAD_BASE_URL="https://codeload.github.com/acmesh-official/acme.sh/tar.gz"
ACME_VERSION="2.8.6"

ACME_INSTALL_HOME="/home/admin/.acme.sh"
ACME_CONFIG_HOME="/mnt/hdd/app-data/letsencrypt"
ACME_CERT_HOME="${ACME_CONFIG_HOME}/certs"

ACME_IS_INSTALLED=0

###################
# FUNCTIONS
###################
function menu_enter_email() {
  HEIGHT=18
  WIDTH=56
  BACKTITLE="Manage TLS certificates"
  TITLE="Let's Encrypt - eMail"
  INPUTBOX="\n
You can *optionally* enter an eMail address.\n
\n
The address will not be included in the generated certificates.\n
\n
It will be used to e.g. notify you about certificate expiries and changes
to the Terms of Service of Let's Encrypt.\n
\n
Feel free to leave empty."

  ADDRESS=$(dialog --clear \
    --backtitle "${BACKTITLE}" \
    --title "${TITLE}" \
    --inputbox "${INPUTBOX}" ${HEIGHT} ${WIDTH} 2>&1 >/dev/tty)
  echo "${ADDRESS}"
}

function acme_status() {
  # check if acme is installed (either directory or cronjob)
  cron_count=$(crontab -l | grep "acme.sh" -c)
  if [ -f "${ACME_INSTALL_HOME}/acme.sh" ] || [ "${cron_count}" = "1" ]; then
    ACME_IS_INSTALLED=1
  else
    ACME_IS_INSTALLED=0
  fi
}

function acme_install() {
  email="${1}"

  # ensure socat
  if ! command -v socat >/dev/null; then
    echo "# installing socat..."
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install -y socat >/dev/null 2>&1
  fi

  if ! [ -d "/mnt/hdd/app-data/letsencrypt" ]; then
    sudo mkdir -p "/mnt/hdd/app-data/letsencrypt"
  fi
  sudo chown admin:admin "/mnt/hdd/app-data/letsencrypt"

  rm -f "/tmp/acme.sh_${ACME_VERSION}.tar.gz"
  if ! curl --silent --fail -o "/tmp/acme.sh_${ACME_VERSION}.tar.gz" "${ACME_LOAD_BASE_URL}/${ACME_VERSION}" 2>&1; then
    echo "Error ($?): Download failed from: ${ACME_LOAD_BASE_URL}/${ACME_VERSION}"
    rm -f "/tmp/acme.sh_${ACME_VERSION}.tar.gz"
    exit 1
  fi

  if tar xzf "/tmp/acme.sh_${ACME_VERSION}.tar.gz" -C /tmp/; then
    cd "/tmp/acme.sh-${ACME_VERSION}" || exit

    if [ -n "${email}" ]; then
      ./acme.sh --install \
        --noprofile \
        --home "${ACME_INSTALL_HOME}" \
        --config-home "${ACME_CONFIG_HOME}" \
        --cert-home "${ACME_CERT_HOME}" \
        --accountemail "${email}"
    else
      ./acme.sh --install \
        --noprofile \
        --home "${ACME_INSTALL_HOME}" \
        --config-home "${ACME_CONFIG_HOME}" \
        --cert-home "${ACME_CERT_HOME}"
    fi

  fi

  rm -f "/tmp/acme.sh_${ACME_VERSION}.tar.gz"
  rm -Rf "/tmp/acme.sh_${ACME_VERSION}"

}


###################
# running as admin
###################
adminUserId=$(id -u admin)
if [ "${EUID}" != "${adminUserId}" ]; then
  echo "error='please run as admin user'"
  exit 1
fi


# add default value to RaspiBlitz config if needed
if ! grep -Eq "^letsencrypt" /mnt/hdd/raspiblitz.conf; then
  echo "letsencrypt=off" >> /mnt/hdd/raspiblitz.conf
fi


###################
# update status
###################
acme_status

###################
# ON
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ ${ACME_IS_INSTALLED} -eq 0 ]; then
    echo "*** INSTALLING Let's Encrypt Client 'acme.sh' ***"

    # setting value in RaspiBlitz config
    sudo sed -i "s/^letsencrypt=.*/letsencrypt=on/g" /mnt/hdd/raspiblitz.conf

    address=$(menu_enter_email)
    echo ""

    acme_install "${address}"
    echo ""

  else
    echo "*** Let's Encrypt Client 'acme.sh' appears to be installed already ***"
  fi

###################
# OFF
###################
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then
  if [ ${ACME_IS_INSTALLED} -eq 1 ]; then
    echo "*** UNINSTALLING Let's Encrypt Client 'acme.sh' ***"

    # setting value in RaspiBlitz config
    sudo sed -i "s/^letsencrypt=.*/letsencrypt=off/g" /mnt/hdd/raspiblitz.conf

    "${ACME_INSTALL_HOME}/acme.sh" --uninstall \
      --home "${ACME_INSTALL_HOME}" \
      --config-home "${ACME_CONFIG_HOME}" \
      --cert-home "${ACME_CERT_HOME}"

  else
    echo "*** Let's Encrypt Client 'acme.sh' not installed ***"
  fi

else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
