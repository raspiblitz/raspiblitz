#!/bin/bash

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
SERVICE_NAME="joinmarket-ng-maker.service"
BITCOIN_CONFIG="/mnt/hdd/app-data/bitcoin/bitcoin.conf"
RUNTIME_DIR="/run/joinmarket-ng"
RUNTIME_ENV="${RUNTIME_DIR}/rpc.env"

if [ "${EUID}" -ne 0 ]; then
  echo "# FAIL: This helper must run as root."
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "# FAIL: Expected exactly one action."
  exit 1
fi

escape_environment_value() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

prepare_runtime_environment() {
  local rpc_user rpc_password escaped_user escaped_password temporary_env

  if [ ! -r "${BITCOIN_CONFIG}" ]; then
    echo "# FAIL: Bitcoin configuration is not readable."
    return 1
  fi

  rpc_user=$(grep -m1 '^rpcuser=' "${BITCOIN_CONFIG}" | cut -d '=' -f 2-)
  rpc_password=$(grep -m1 '^rpcpassword=' "${BITCOIN_CONFIG}" | cut -d '=' -f 2-)
  if [ -z "${rpc_user}" ] || [ -z "${rpc_password}" ]; then
    echo "# FAIL: Bitcoin RPC credentials are missing."
    return 1
  fi

  install -d -o root -g root -m 700 "${RUNTIME_DIR}" || return 1
  temporary_env=$(mktemp "${RUNTIME_DIR}/rpc.env.XXXXXX") || return 1
  trap 'rm -f "${temporary_env}"' RETURN

  escaped_user=$(escape_environment_value "${rpc_user}")
  escaped_password=$(escape_environment_value "${rpc_password}")
  if ! printf 'BITCOIN__RPC_USER="%s"\nBITCOIN__RPC_PASSWORD="%s"\n' \
    "${escaped_user}" "${escaped_password}" > "${temporary_env}"; then
    return 1
  fi

  chown root:root "${temporary_env}" && chmod 600 "${temporary_env}" \
    && mv -f "${temporary_env}" "${RUNTIME_ENV}"
}

case "$1" in
  prepare)
    prepare_runtime_environment
    ;;
  start)
    exec systemctl start "${SERVICE_NAME}"
    ;;
  stop)
    exec systemctl stop "${SERVICE_NAME}"
    ;;
  status)
    exec systemctl status "${SERVICE_NAME}" --no-pager -l
    ;;
  enable)
    exec systemctl enable "${SERVICE_NAME}"
    ;;
  *)
    echo "# FAIL: Unsupported action '$1'."
    exit 1
    ;;
esac
