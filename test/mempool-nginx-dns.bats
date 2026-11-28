#!/usr/bin/env bats

setup() {
  renderer="$BATS_TEST_DIRNAME/../home.admin/config.scripts/mempool.nginx-config.py"
}

render_dns() {
  python3 - "$renderer" "$1" <<'PY'
from pathlib import Path
import runpy
import sys

render = runpy.run_path(sys.argv[1])["render"]
print(render("before\n# MEMPOOL_SYSTEM_DNS\nafter", sys.argv[2]))
PY
}

@test "use the node's IPv4 and IPv6 resolvers once in configured order" {
  run render_dns $'nameserver 127.0.0.53\nnameserver 2001:db8::53\nnameserver 127.0.0.53\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'before\nresolver 127.0.0.53 [2001:db8::53];\nafter' ]
}

@test "an unusable or absent DNS configuration leaves local sites independent of an external resolver" {
  for conf in '' $'search example.test\nnameserver test.invalid\nnameserver fe80::53%eth0\n'; do
    run render_dns "$conf"
    [ "$status" -eq 0 ]
    [ "$output" = $'before\n\nafter' ]
  done
}
