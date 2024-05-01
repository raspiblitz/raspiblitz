#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "config script to install or remove the Let's Encrypt Client (ACME.SH)"
  echo "bonus.letsencrypt.sh [on|off]"
  echo "bonus.letsencrypt.sh issue-cert DNSSERVICE FULLDOMAINNAME APITOKEN ip|tor|ip&tor"
  echo "bonus.letsencrypt.sh remove-cert FULLDOMAINNAME ip|tor|ip&tor"
  echo "bonus.letsencrypt.sh refresh-nginx-certs"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# https://github.com/acmesh-official/acme.sh/releases
ACME_LOAD_BASE_URL="https://github.com/acmesh-official/acme.sh/archive/refs/tags/3.0.7.tar.gz"
ACME_VERSION="3.0.7"

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
It will be used to e.g. notify you about certificate expiration and changes
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

  # make sure config directory exists
  if ! [ -d $ACME_CONFIG_HOME ]; then
    sudo mkdir -p $ACME_CONFIG_HOME
  fi
  sudo chown admin:admin $ACME_CONFIG_HOME

  # download and install acme.sh
  echo "# download acme.sh release ${ACME_VERSION} from ${ACME_LOAD_BASE_URL}"
  rm -r /tmp/acme.sh*
  if ! curl -L --silent --fail -o "/tmp/acme.sh.tar.gz" "${ACME_LOAD_BASE_URL}" 2>&1; then
    echo "Error ($?): Download failed from: ${ACME_LOAD_BASE_URL}"
    rm -r /tmp/acme.sh*
    exit 1
  fi

  if tar xzf "/tmp/acme.sh.tar.gz" -C /tmp/; then
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

  else
    echo "# Error ($?): Extracting failed"
    exit 1
  fi

  rm -r /tmp/acme.sh*
}

function refresh_certs_with_nginx() {

    # FIRST: SET ALL TO DEFAULT SELF SIGNED

    echo "# default IP certs"
    sudo rm /mnt/hdd/app-data/nginx/tls.cert
    sudo rm /mnt/hdd/app-data/nginx/tls.key
    sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tls.cert
    sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tls.key

    echo "# default TOR certs"
    sudo rm /mnt/hdd/app-data/nginx/tor_tls.cert
    sudo rm /mnt/hdd/app-data/nginx/tor_tls.key
    sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tor_tls.cert
    sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tor_tls.key

    # SECOND: SET LETSENCRPYT CERTS FOR SUBSCRIPTIONS

    if [ "${letsencrypt}" != "on" ]; then
      echo "# lets encrypt is off - so no certs replacements"
      return
    fi

    certsDirectories=$(sudo ls ${ACME_CERT_HOME})
    echo "# certsDirectories(${certsDirectories})"
    directoryArray=(`echo "${certsDirectories}" | tr '  ' ' '`)
    for i in "${directoryArray[@]}"; do
      FQDN=$(echo "${i}" | cut -d "_" -f1)
      echo "# i(${i})"
      echo "# FQDN(${FQDN})"
      # check if there is a LetsEncrypt Subscription for this domain
      details=$(/home/admin/config.scripts/blitz.subscriptions.letsencrypt.py subscription-detail $FQDN)
      if [ $(echo "${details}" | grep -c "error=") -eq 0 ] && [ ${#details} -gt 10 ]; then

        echo "# details(${details})"

        # get target for that domain
        options=$(echo "${details}" | jq -r ".target")

        # replace certs for clearnet
        if [ "${options}" == "ip" ] || [ "${options}" == "ip&tor" ]; then
          echo "# replacing IP certs for ${FQDN}"
          sudo rm /mnt/hdd/app-data/nginx/tls.cert
          sudo rm /mnt/hdd/app-data/nginx/tls.key
          sudo ln -s ${ACME_CERT_HOME}/${FQDN}_ecc/fullchain.cer /mnt/hdd/app-data/nginx/tls.cert
          sudo ln -s ${ACME_CERT_HOME}/${FQDN}_ecc/${FQDN}.key /mnt/hdd/app-data/nginx/tls.key
        fi

        # replace certs for tor
        if [ "${options}" == "tor" ] || [ "${options}" == "ip&tor" ]; then
          echo "# replacing TOR certs for ${FQDN}"
          sudo rm /mnt/hdd/app-data/nginx/tor_tls.cert
          sudo rm /mnt/hdd/app-data/nginx/tor_tls.key
          sudo ln -s ${ACME_CERT_HOME}/${FQDN}_ecc/fullchain.cer /mnt/hdd/app-data/nginx/tor_tls.cert
          sudo ln -s ${ACME_CERT_HOME}/${FQDN}_ecc/${FQDN}.key /mnt/hdd/app-data/nginx/tor_tls.key
        fi

        # todo maybe allow certs for single services later (dont forget that these also need to be replaced in 'on' then)
        if [ "${options}" != "tor" ] && [ "${options}" != "ip" ] && [ "${options}" != "ip&tor" ]; then
          echo "# FAIL target '${options}' not supported yet'"
        fi

      fi
    done

}

###################
# running as admin
###################
adminUserId=$(id -u admin)
if [ "${EUID}" != "${adminUserId}" ]; then
  echo "error='please run as admin user'"
  exit 1
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
    /home/admin/config.scripts/blitz.conf.sh set letsencrypt "on"

    address="$2"
    if [ "$2" == "enter-email" ]; then
      address=$(menu_enter_email)
      echo ""
    fi

    # make sure storage directory exist
    sudo mkdir -p $ACME_CERT_HOME 2>/dev/null
    sudo chown -R admin:admin $ACME_CONFIG_HOME
    sudo chmod -R 733 $ACME_CONFIG_HOME

    # install the acme script
    echo "# acme_install"
    acme_install "${address}"
    echo ""

    # make sure already existing certs get refreshed in to nginx
    refresh_certs_with_nginx
    echo "# restarting nginx"
    sudo systemctl restart nginx 2>&1

    exit 0

  else
    echo "# *** Let's Encrypt Client 'acme.sh' appears to be installed already ***"
    exit 1
  fi

###################
# ISSUE-CERT
###################

elif [ "$1" = "issue-cert" ]; then

  # check if letsencrypt is on
  if [ "${letsencrypt}" != "on" ]; then
    echo "error='letsencrypt is not on'"
    exit 1
  fi

  # make sure storage directory exist
  sudo mkdir -p $ACME_CERT_HOME 2>/dev/null
  sudo chown -R admin:admin $ACME_CONFIG_HOME
  sudo chmod -R 733 $ACME_CONFIG_HOME

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
  elif [ "${dnsservice}" == "dynu" ]; then
      echo "# preparing DYNYU"
      dnsservice="dns_dynu"
      clientid=$(echo "${apitoken}" | cut -d ':' -f 1)
      secret=$(echo "${apitoken}" | cut -d ':' -f 2)
      export Dynu_ClientId="${clientid}"
      export Dynu_Secret="${secret}"
  else
    echo "error='not supported dnsservice'"
    exit 1
  fi

  # create certificates
  echo "# creating certs for ${FQDN}"
  $ACME_INSTALL_HOME/acme.sh --home "${ACME_INSTALL_HOME}" --config-home "${ACME_CONFIG_HOME}" --cert-home "${ACME_CERT_HOME}" --issue --dns ${dnsservice} -d ${FQDN} --keylength ec-256 2>&1
  success1=$($ACME_INSTALL_HOME/acme.sh --list --home "${ACME_INSTALL_HOME}" --config-home "${ACME_CONFIG_HOME}" --cert-home "${ACME_CERT_HOME}" | grep -c "${FQDN}")
  success2=$(sudo ls ${ACME_CERT_HOME}/${FQDN}_ecc//fullchain.cer | grep -c "/fullchain.cer")
  if [ ${success1} -eq 0 ] || [ ${success2} -eq 0 ]; then
    sleep 6
    echo "error='acme failed'"
    exit 1
  fi

  # test nginx config
  refresh_certs_with_nginx
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

  exit 0

###################
# REMOVE-CERT
###################

elif [ "$1" = "remove-cert" ]; then

  # make sure storage directory exist
  sudo mkdir -p $ACME_CERT_HOME 2>/dev/null
  sudo chown -R admin:admin $ACME_CONFIG_HOME
  sudo chmod -R 733 $ACME_CONFIG_HOME

  # get and check parameters
  FQDN=$2
  options=$3
  if [ ${#FQDN} -eq 0 ]; then
    echo "error='invalid parameters'"
    exit 1
  fi
  if [ ${#options} -eq 0 ]; then
    options="ip&tor"
  fi

  echo "# bonus.letsencrypt.sh remove-cert ${FQDN} ${options}"

  # remove cert from renewal
  $ACME_INSTALL_HOME/acme.sh --remove -d "${FQDN}" --ecc --home "${ACME_INSTALL_HOME}" --config-home "${ACME_CONFIG_HOME}" --cert-home "${ACME_CERT_HOME}" 2>&1

  # delete cert files
  sudo rm -r  ${ACME_CERT_HOME}/${FQDN}_ecc

  # test nginx config
  refresh_certs_with_nginx
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

  exit 0


###################
# REFRESH NGINX CERTS
###################

elif [ "$1" = "refresh-nginx-certs" ]; then

  # refresh nginx
  refresh_certs_with_nginx
  syntaxOK=$(sudo nginx -t 2>&1 | grep -c "syntax is ok")
  testOK=$(sudo nginx -t 2>&1 | grep -c "test is successful")
  if [ ${syntaxOK} -eq 0 ] || [ ${testOK} -eq 0 ]; then
    echo "# to check details on nginx config use: sudo nginx -t"
    echo "error='nginx config failed'"
    exit 1
  fi

  echo "# restarting nginx"
  sudo systemctl restart nginx 2>&1


###################
# OFF
###################
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then
  if [ ${ACME_IS_INSTALLED} -eq 1 ]; then
    echo "*** UNINSTALLING Let's Encrypt Client 'acme.sh' ***"

    # setting value in RaspiBlitz config
    /home/admin/config.scripts/blitz.conf.sh set letsencrypt "off"

    "${ACME_INSTALL_HOME}/acme.sh" --uninstall \
      --home "${ACME_INSTALL_HOME}" \
      --config-home "${ACME_CONFIG_HOME}" \
      --cert-home "${ACME_CERT_HOME}"

    # refresh nginx
    refresh_certs_with_nginx
    echo "# restarting nginx"
    sudo systemctl restart nginx 2>&1

    # remove old script install
    sudo rm -r ${ACME_INSTALL_HOME}
    sudo rm -r ${ACME_CONFIG_HOME}

    exit 0

  else
    echo "# *** Let's Encrypt Client 'acme.sh' not installed ***"
    exit 1
  fi

else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
