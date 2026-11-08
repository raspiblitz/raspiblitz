#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
docker build -t raspiblitz-monitor-tests:local "$root/tests/bitcoin-monitor"
docker run --rm --init --network none --cap-drop ALL --pids-limit 128 \
  --security-opt no-new-privileges --env MONITOR_TEST_CONTAINER=1 \
  --mount "type=bind,src=$root,dst=/src,readonly" \
  raspiblitz-monitor-tests:local python3 /src/tests/bitcoin-monitor/test_monitor.py
