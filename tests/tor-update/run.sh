#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ "${TOR_UPDATE_SKIP_BUILD:-0}" != 1 ]; then
  docker build -t raspiblitz-tor-update-tests tests/tor-update
fi
COPYFILE_DISABLE=1 tar -c home.admin/config.scripts/tor.install.sh tests/tor-update |
  docker run --rm -i --network none --tmpfs /tmp:rw,size=64m --cap-drop ALL \
    --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
    --cap-add SETUID --cap-add SETGID raspiblitz-tor-update-tests \
    bash -c 'tar -x && bash -n home.admin/config.scripts/tor.install.sh &&
      shellcheck --severity=error home.admin/config.scripts/tor.install.sh &&
      python3 tests/tor-update/test_update.py'
