#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "config script to install or remove the Let's Encrypt Client (ACME.SH)"
  echo "bonus.letsencrypt.sh [on|off]"
  echo "bonus.letsencrypt.sh issue-cert DNSSERVICE FULLDOMAINNAME APITOKEN ip|tor|ip&tor"
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

    address="$2"
    if [ "$2" == "enter-email" ]; then
      address=$(menu_enter_email)
      echo ""
    fi

    # make sure storage directory exist
    sudo mkdir -p /mnt/hdd/app-data/letsencrypt/certs 2>/dev/null
    sudo chown -R admin:admin /mnt/hdd/app-data/letsencrypt
    sudo chmod -R 733 /mnt/hdd/app-data/letsencrypt

    acme_install "${address}"
    echo ""

  else
    echo "*** Let's Encrypt Client 'acme.sh' appears to be installed already ***"
  fi

###################
# ISSUE-CERT
###################

elif [ "$1" = "issue-cert" ]; then

  # get and check parameters
  dnsservice=$2
  FQDN=$3
  apitoken=$4
  options=$5
  if [ ${#dnsservice} -eq 0 ] || [ ${#FQDN} -eq 0 ] || [ ${#apitoken} -eq 0 ]; then
    echo "error='invalid parameters'"
    exit 1
  fi
  if [ ${#options} -eq 0 ]; then
    options="ip&tor"
  fi

  # prepare values and exports based on dnsservice
  if [ "${dnsservice}" == "duckdns" ]; then
      echo "# preparing DUCKDNS"
      dnsservice="dns_duckdns"
      export DuckDNS_Token=${apitoken}
  else
    echo "error='not supported dnsservice'"
    exit 1
  fi

  # create certicicates
  echo "# creating certs for ${FQDN}"
  /home/admin/.acme.sh/acme.sh --force --home "/home/admin/.acme.sh" --config-home "/mnt/hdd/app-data/letsencrypt" --cert-home "/mnt/hdd/app-data/letsencrypt/certs" --issue --dns ${dnsservice} -d ${FQDN} --keylength ec-256 2>&1
  success=$(./.acme.sh/acme.sh --list | grep -c "${FQDN}")
  if [ ${success} -eq 0 ]; then
    sleep 6
    echo "error='acme failed'"
    exit 1
  fi

  # replace certs for clearnet
  if [ "${options}" == "ip" ] || [ "${options}" == "ip&tor" ]; then
    echo "# replacing IP certs"
    sudo rm /mnt/hdd/app-data/nginx/tls.cert
    sudo rm /mnt/hdd/app-data/nginx/tls.key 
    sudo ln -s /mnt/hdd/app-data/letsencrypt/certs/${FQDN}_ecc/fullchain.cer /mnt/hdd/app-data/nginx/tls.cert
    sudo ln -s /mnt/hdd/app-data/letsencrypt/certs/${FQDN}_ecc/${FQDN}.key /mnt/hdd/app-data/nginx/tls.key
  fi

  # repleace certs for tor
  if [ "${options}" == "tor" ] || [ "${options}" == "ip&tor" ]; then
    echo "# replacing TOR certs"
    sudo rm /mnt/hdd/app-data/nginx/tor_tls.cert
    sudo rm /mnt/hdd/app-data/nginx/tor_tls.key
    sudo ln -s /mnt/hdd/app-data/letsencrypt/certs/${FQDN}_ecc/fullchain.cer /mnt/hdd/app-data/nginx/tor_tls.cert
    sudo ln -s /mnt/hdd/app-data/letsencrypt/certs/${FQDN}_ecc/${FQDN}.key /mnt/hdd/app-data/nginx/tor_tls.key
  fi

  # todo maybe allow certs for single servies later
  if [ "${options}" != "tor" ] && [ "${options}" != "ip" ] && [ "${options}" != "ip&tor" ]; then
    echo "error='option not supported yet'"
    exit 1
  fi

  # test nginx config
  syntaxOK=$(sudo nginx -t 2>&1 | grep -c "syntax is ok")
  testOK=$(sudo nginx -t 2>&1 | grep -c "test is successful")
  if [ ${syntaxOK} -eq 0 ] || [ ${testOK} -eq 0 ]; then
    echo "# to check details on nginx config use: sudo nginx -t"
    echo "error='nginx config failed'"
    exit 1
  fi

  # restart nginx
  echo "# restarting nginx"
  sudo systemctl restart nginx 2>&1


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

    # revert to old self-singed certs
    sudo rm /mnt/hdd/app-data/nginx/tls.cert
    sudo rm /mnt/hdd/app-data/nginx/tls.key 
    sudo rm /mnt/hdd/app-data/nginx/tor_tls.cert
    sudo rm /mnt/hdd/app-data/nginx/tor_tls.key
    sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tls.cert
    sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tls.key
    sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tor_tls.cert
    sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tor_tls.key
    sudo rm -r ${ACME_CONFIG_HOME}

    # restart nginx
    echo "# restarting nginx"
    sudo systemctl restart nginx 2>&1

  else
    echo "*** Let's Encrypt Client 'acme.sh' not installed ***"
  fi

else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
