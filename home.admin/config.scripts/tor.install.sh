#!/usr/bin/env bash

#### INFO ####

## Lines that begin with "## " try to explain what's going on. Lines
## that begin with just "#" are disabled commands: you can enable them
## by removing the "#" symbol.

## https://onion.torproject.org/ or http://xao2lxsmia2edq2n5zxg6uahx6xox2t7bfjw6b5vdzsxi7ezmqob6qid.onion/
## https://support.torproject.org/apt/ or http://rzuwtpc4wb3xdzrj3yeajsvm3fkq4vbeubm2tdxaqruzzzgs5dwemlad.onion/apt/
## https://support.torproject.org/apt/tor-deb-repo/
## https://support.torproject.org/apt/apt-over-tor/

# command info
usage(){
 echo "script to switch Tor on or off"
 echo "tor.install.sh [install|enable|update]"
 exit 1
}

#### VARIABLES (some might be reset by prepare) ####

hdd_path="/mnt/hdd/app-data"
download_dir="/home/admin/download"
tor_data_dir="${hdd_path}/tor"
tor_conf_dir="${hdd_path}/tor"
torrc="/etc/tor/torrc"
torrc_bridges="${tor_conf_dir}/torrc.d/bridges"
torrc_services="${tor_conf_dir}/torrc.d/services"
tor_pkgs="torsocks nyx obfs4proxy python3-stem apt-transport-tor curl gpg"
tor_deb_repo="tor+http://apow7mjfryruh65chtdydfmqfpj5btws7nbocgtaovhvezgccyjazpqd.onion"
#tor_deb_repo="tor+https://deb.torproject.org"
#tor_deb_repo="https://deb.torproject.org"
tor_deb_repo_clean="${tor_deb_repo#*tor+}"
tor_deb_repo_pgp_fingerprint="A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89"
tor_min_supported_version="0.4.9"

## https://github.com/keroserene/snowflake/commits/master
snowflake_commit_hash="af6e2c30e1a6aacc6e7adf9a31df0a387891cc37"

distribution=$(lsb_release -sc)
architecture=$(dpkg --print-architecture)

#### FUNCTIONS ####

add_tor_sources(){
  local key_dir endpoint fingerprint key_info
  key_dir=$(mktemp -d) || return 1
  # Compare the complete primary fingerprint before trusting the key. Keep the
  # previous keyring intact if either transport or key validation fails.
  for endpoint in "${tor_deb_repo_clean}" "https://deb.torproject.org"; do
    if [ "${endpoint}" = "${tor_deb_repo_clean}" ]; then
      curl -fsS -x socks5h://127.0.0.1:9050 --connect-timeout 60 \
        "${endpoint}/torproject.org/${tor_deb_repo_pgp_fingerprint}.asc" -o "${key_dir}/key.asc" || continue
    else
      curl -fsS --connect-timeout 60 \
        "${endpoint}/torproject.org/${tor_deb_repo_pgp_fingerprint}.asc" -o "${key_dir}/key.asc" || continue
    fi
    key_info=$(gpg --batch --show-keys --with-colons "${key_dir}/key.asc" 2>/dev/null) || continue
    fingerprint=$(echo "${key_info}" |
      awk -F: '$1 == "pub" {keys++} $1 == "fpr" && !fingerprint {fingerprint=$10}
        END {if (keys == 1) print fingerprint}')
    if [ "${fingerprint}" = "${tor_deb_repo_pgp_fingerprint}" ] &&
       gpg --batch --yes --dearmor -o "${key_dir}/key.gpg" "${key_dir}/key.asc" &&
       sudo install -m 644 "${key_dir}/key.gpg" /usr/share/keyrings/torproject.gpg; then
      rm -rf "${key_dir}"
      echo "deb [arch=${architecture} signed-by=/usr/share/keyrings/torproject.gpg] ${tor_deb_repo}/torproject.org ${distribution} main
 deb-src [arch=${architecture} signed-by=/usr/share/keyrings/torproject.gpg] ${tor_deb_repo}/torproject.org ${distribution} main" |
        sudo tee /etc/apt/sources.list.d/tor.list || return 1
      # Remove legacy global trust only after scoped trust and sources exist.
      sudo rm -f /etc/apt/trusted.gpg.d/torproject.gpg
      return $?
    fi
  done
  rm -rf "${key_dir}"
  echo "! FAIL: Was not able to verify deb.torproject.org key"
  return 1
}

configure_default_torrc(){
  echo -e "\n*** updating Tor config ${torrc} ***"
  echo "## raspiblitz torrc (anchor, do not remove this line)
## See 'man tor', or https://2019.www.torproject.org/docs/tor-manual.html.en
## See https://github.com/torproject/tor/blob/main/src/config/torrc.sample.in

%include ${tor_conf_dir}/torrc.d

DataDirectory ${tor_data_dir}/sys
PidFile ${tor_data_dir}/sys/tor.pid

SafeLogging 0
Log notice stdout
Log notice file ${tor_data_dir}/notice.log
Log info file ${tor_data_dir}/info.log

RunAsDaemon 1
ControlPort 9051
SocksPort 9050 IsolateDestAddr
ExitRelay 0
CookieAuthentication 1
CookieAuthFileGroupReadable 1
" | sudo tee ${torrc}
}


configure_bridges_torrc(){
  echo -e "\n*** updating Tor config ${torrc_bridges} ***"
  echo "
#UseBridges 1
#UpdateBridgesFromAuthority 1
#ClientTransportPlugin meek_lite,obfs4 exec /usr/bin/obfs4proxy
#ClientTransportPlugin snowflake exec /usr/bin/snowflake-client -url https://snowflake-broker.torproject.net.global.prod.fastly.net/ -front cdn.sstatic.net -ice stun:stun.l.google.com:19302,stun:stun.voip.blackberry.com:3478,stun:stun.altar.com.pl:3478,stun:stun.antisip.com:3478,stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,stun:stun.sonetel.net:3478,stun:stun.stunprotocol.org:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.voys.nl:3478

## Meek-Azure
#Bridge meek_lite 192.0.2.2:2 97700DFE9F483596DDA6264C4D7DF7641E1E39CE url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com

## Snowflake
#Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72

## Obfs4
##Bridge obfs4 IP:PORT FINGERPRINT cert=CERTIFICATE iat-mode=[0|1|2]
" | sudo tee ${torrc_bridges}
}

require_supported_tor_version(){
  local tor_output
  tor_output=$(tor --version) || { echo "! FAIL: Tor version command failed"; return 1; }
  tor_version=$(echo "${tor_output}" | awk 'NR==1 {print $3}' | sed 's/\.$//')
  if [ ${#tor_version} -eq 0 ]; then
    echo "! FAIL: Was not able to detect installed Tor version"
    return 1
  fi
  if ! dpkg --compare-versions "${tor_version}" ge "${tor_min_supported_version}"; then
    echo "! FAIL: Installed Tor ${tor_version} is older than required ${tor_min_supported_version}"
    echo "! INFO: Tor 0.4.8 and older are EOL and scheduled to stop working on the Tor network"
    return 1
  fi
  echo "- OK Tor ${tor_version} >= ${tor_min_supported_version}"
}

restart_tor_service(){
  if systemctl cat tor@default.service >/dev/null 2>&1; then
    sudo systemctl restart tor@default
  else
    sudo systemctl restart tor
  fi
}


action=$1

#### INSTALL ####
if [ "${action}" = "install" ]; then

  echo -e "*** Installing tor (but not run it yet - needs HDD connected )***\n"

  echo -e "\n--> Configuring pluggable transports ***"

  ## https://github.com/radio24/TorBox/blob/master/install/run_install.sh
  ## Configuring Tor with the pluggable transports
  sudo apt install -y obfs4proxy
  sudo setcap 'cap_net_bind_service=+ep' /usr/bin/obfs4proxy

  ## Install Snowflake
  ## nyxnor: unfortunately it reaches TPO domain for a lib which I can't fix
  if [ ! -f /usr/bin/snowflake-proxy ] || [ ! -f /usr/bin/snowflake-client ]; then
    sudo rm -rf "${download_dir}"/snowflake
    git clone https://github.com/keroserene/snowflake.git "${download_dir}"/snowflake
    if [ ! -d "${download_dir}"/snowflake ]; then
      echo "FAIL: COULDN'T CLONE THE SNOWFLAKE REPOSITORY!"
      echo "INFO: The Snowflake repository may be blocked or offline!"
      echo "INFO: Please try again later and if the problem persists, please report it"
    else
      git -C "${download_dir}"/snowflake -c advice.detachedHead=false checkout "${snowflake_commit_hash}"
      echo; sudo bash /home/admin/config.scripts/bonus.go.sh on
      . /etc/profile ## GOPATH
      export GO111MODULE="on"
      cd "${download_dir}"/snowflake/proxy || exit 1
      echo -e "\n*** Installing snowflake-proxy ***"
      go get
      go build
      sudo cp proxy /usr/bin/snowflake-proxy
      cd "${download_dir}"/snowflake/client || exit 1
      echo -e "\n*** Installing snowflake-client ***"
      go get
      go build
      sudo cp client /usr/bin/snowflake-client
      cd ~ || exit 1
      sudo rm -rf "${download_dir}"/snowflake
    fi
  else
    echo -e "\n--> Snowflake client and proxy already installed ***\n"
  fi

  # install tor
  echo -e "\n*** Install Tor ***"
  sudo apt -o Dpkg::Options::="--force-confold" install -y tor
  # shellcheck disable=SC2086
  sudo apt install -y ${tor_pkgs}

  add_tor_sources || exit 1

  echo -e "\n*** Reinstall ***"
  sudo apt update -y
  sudo apt -o Dpkg::Options::="--force-confold" install -y tor
  # shellcheck disable=SC2086
  sudo apt install -y ${tor_pkgs}
  require_supported_tor_version || exit 1

  # make sure tor is not running after is was installed
  # should be enabled after main menu when HDD is mounted
  # while user has options to configure
  sudo systemctl disable --now tor@default

  echo
  exit
fi

#### ENABLE (once HDD is available) ####
if [ "${action}" = "enable" ]; then

  echo -e "\n*** Enable Tor Service ***"

  # check if /mnt/hdd/app-data is available and symbolic link
  if [ ! -L /mnt/hdd/app-data ]; then
    echo "# FAIL: '/mnt/hdd/app-data' needs to be mounted/linked to enable Tor"
    exit 1
  fi

  # create tor dirs and set permissions
  echo -e "*** Create directories and set permissions ***"
  sudo mkdir -pv "${tor_conf_dir}"/torrc.d "${tor_data_dir}"/sys/keys "${tor_data_dir}"/services "${tor_data_dir}"/onion_auth
  sudo chmod -v 700 "${tor_data_dir}"
  sudo chmod -v 755 "${tor_conf_dir}" "${tor_conf_dir}"/torrc.d
  sudo chmod -v 644 "${torrc}" "${tor_conf_dir}"/torrc.d/*
  # make sure its the correct owner
  sudo chown -Rv debian-tor:debian-tor "${tor_data_dir}"
  sudo chown -Rv root:root "${tor_conf_dir}"

  # create tor config if not existent
  if [ $(sudo grep -c "raspiblitz" ${torrc}) -lt 1 ]; then
    echo "- ${torrc} will get edited"
    configure_default_torrc
  else
    echo "- ${torrc} already edited"
  fi
  if [ $(sudo grep -c "Bridge" ${torrc_bridges}) -lt 1 ]; then
    echo "- ${torrc_bridges} will get edited"
    configure_bridges_torrc
  else
    echo "- ${torrc_bridges} already edited"
  fi

  # edit tor services
  sudo sed -i "s/^NoNewPrivileges=yes/NoNewPrivileges=no/g" /lib/systemd/system/tor@default.service
  sudo mkdir -p /etc/systemd/system/tor@default.service.d
  echo "# DO NOT EDIT! This file is generated by raspiblitz and will be overwritten
[Service]
ReadWriteDirectories=-${tor_data_dir}
[Unit]
After=network.target nss-lookup.target mnt-hdd.mount
" | sudo tee /etc/systemd/system/tor@default.service.d/raspiblitz.conf

  # fix apparmor - https://github.com/rootzoll/raspiblitz/issues/2531
  if [ $(systemctl --type=service | grep -c apparmor) -gt 0 ]; then
    echo "- add custom directories to apparmor"
    echo "\
    # vim:syntax=apparmor
#include <tunables/global>

profile system_tor flags=(attach_disconnected) {
  #include <abstractions/tor>

  owner /var/lib/tor/** rwk,
  owner /var/lib/tor/ r,
  owner /var/log/tor/* w,

  owner ${tor_data_dir}/** rwk,
  owner ${tor_data_dir}/ r,
  owner ${tor_conf_dir}/** rwk,

  /mnt/hdd/app-data/tor/              rUx,
  /mnt/hdd/app-data/tor/**            rwkix,
  /mnt/disk_data/app-data/tor/        rUx,
  /mnt/disk_data/app-data/tor/**      rwkix,
  /mnt/disk_storage/app-data/tor/     rUx,
  /mnt/disk_storage/app-data/tor/**   rwkix,

  # During startup, tor (as root) tries to open various things such as
  # directories via check_private_dir().  Let it.
  /var/lib/tor/** r,
  ${tor_data_dir}/** r,
  ${tor_conf_dir}/** r,

  /{,var/}run/tor/ r,
  /{,var/}run/tor/control w,
  /{,var/}run/tor/socks w,
  /{,var/}run/tor/tor.pid w,
  /{,var/}run/tor/control.authcookie w,
  /{,var/}run/tor/control.authcookie.tmp rw,
  /{,var/}run/systemd/notify w,

  # Site-specific additions and overrides. See local/README for details.
  #include <local/system_tor>
}"  | sudo tee /etc/apparmor.d/system_tor
    sudo systemctl restart apparmor
  fi

  # enable tor services
  sudo systemctl unmask tor@default
  sudo systemctl daemon-reload
  sudo systemctl enable --now tor@default
  sudo systemctl restart tor@default

  echo
  exit
fi

if [ "${action}" = "update" ]; then
  # Preserve the whole installed package when available. Repositories may
  # retain only the newest version, so rollback cannot be an upgrade prerequisite.
  previous_version=$(dpkg-query -W -f='${Version}' tor) || exit 1
  update_stage=$(sudo mktemp -d /var/tmp/tor-update.XXXXXXXX) || exit 1
  install_attempted=0
  stop_attempted=0
  update_complete=0
  finish_update(){
    local result=$?
    trap - EXIT
    if [ "${update_complete}" -eq 0 ]; then
      if [ "${install_attempted}" -eq 1 ] && sudo test -f "${update_stage}/previous.deb"; then
        sudo dpkg --force-confold -i "${update_stage}/previous.deb" ||
          echo "! FAIL: Package rollback failed; recovery package: ${update_stage}/previous.deb"
      fi
      if [ "${stop_attempted}" -eq 1 ]; then
        restart_tor_service || echo "! FAIL: Unable to restart the Tor service"
      fi
      echo "! INFO: Recovery files retained in ${update_stage}"
    else
      sudo rm -rf "${update_stage}"
    fi
    exit "${result}"
  }
  trap finish_update EXIT
  trap 'exit 1' HUP INT TERM
  # Download through authenticated APT first. Copy a matching cached package
  # only as a fallback, validating metadata rather than trusting its filename.
  if ! sudo bash -c '
    cd "$1" || exit 1
    valid_package(){
      [ "$(dpkg-deb -f "$1" Package)" = tor ] &&
      [ "$(dpkg-deb -f "$1" Version)" = "$2" ] &&
      { [ "$(dpkg-deb -f "$1" Architecture)" = all ] ||
        [ "$(dpkg-deb -f "$1" Architecture)" = "$3" ]; }
    }
    if apt download "tor=$2"; then
      for package in ./*.deb; do
        if valid_package "$package" "$2" "$3"; then
          mv -- "$package" previous.deb && exit 0
        fi
      done
    fi
    for package in /var/cache/apt/archives/tor_*.deb; do
      [ -f "$package" ] || continue
      cp -- "$package" cached.deb || continue
      if valid_package cached.deb "$2" "$3"; then
        mv cached.deb previous.deb && exit 0
      fi
      rm -f cached.deb
    done
    exit 1' bash "${update_stage}" "${previous_version}" "${architecture}"; then
    echo "! WARNING: Previous Tor package unavailable, continuing without package rollback"
  fi

  case "$2" in
    source)
      sudo apt -o APT::Update::Error-Mode=any update || exit 1
      sudo apt install -y build-essential fakeroot devscripts || exit 1
      sudo apt build-dep -y tor deb.torproject.org-keyring || exit 1
      # A fresh build directory prevents installing stale .deb files after a
      # failed download/build. Source signatures are checked by APT.
      mkdir -p "${download_dir}" || exit 1
      build_dir=$(mktemp -d "${download_dir}/tor-source.XXXXXXXX") || exit 1
      cd "${build_dir}" || exit 1
      apt source tor || exit 1
      cd tor-* || exit 1
      debuild -rfakeroot -uc -us || exit 1
      cd .. || exit 1
      set -- tor_*.deb
      [ "$#" -eq 1 ] && [ -f "$1" ] || exit 1
      stop_attempted=1
      if systemctl cat tor@default.service >/dev/null 2>&1; then
        sudo systemctl stop tor@default || exit 1
      else
        sudo systemctl stop tor || exit 1
      fi
      install_attempted=1
      sudo dpkg -i "$1" || exit 1
      ;;
    *)
      add_tor_sources || exit 1
      sudo apt -o APT::Update::Error-Mode=any update || exit 1
      # Download and authenticate all packages before the first install.
      sudo apt -o Dpkg::Options::="--force-confold" install --download-only -y tor || exit 1
      # shellcheck disable=SC2086
      sudo apt install --download-only -y ${tor_pkgs} || exit 1
      install_attempted=1
      # APT may stop the service even when installation reports an error.
      stop_attempted=1
      sudo apt -o Dpkg::Options::="--force-confold" install -y tor || exit 1
      # shellcheck disable=SC2086
      sudo apt install -y ${tor_pkgs} || exit 1
      ;;
  esac
  require_supported_tor_version || exit 1
  restart_tor_service || exit 1
  update_complete=1
  exit 0
fi

# if above didnt matched - show info onf usage
usage
