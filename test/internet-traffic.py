#!/usr/bin/env python3
"""Offline traffic regression: python3 test/internet-traffic.py [internet.sh].

Execute the production interface-selection/traffic block, not the configuration,
network checks, or update commands. Only ip, ifconfig, and os-release reads are
fixtures. No node, root privileges, packages, or network access are required.
"""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import unittest

SOURCE = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / "home.admin/config.scripts/internet.sh"
)
TEXT = SOURCE.read_text()
BLOCK = TEXT.split("# get active network device (eth0 or wlan0) & traffic\n", 1)[1].split(
    "# get local IP (from different sources)", 1
)[0]


class TrafficTests(unittest.TestCase):
    def run_block(self, device, missing=False, empty=False):
        # eth0 exists but is not the active interface in the Wi-Fi fixture.
        setup = "\n".join([
            "fixture_device=" + shlex.quote(device),
            "fixture_missing=" + str(int(missing)),
            "fixture_empty=" + str(int(empty)),
            r'''ip() {
  printf '1: lo: <LOOPBACK,UP> mtu 65536 state UNKNOWN\n'
  if [ -n "$fixture_device" ]; then
    printf '3: %s: <BROADCAST,MULTICAST,UP> mtu 1500 state UP\n' "$fixture_device"
  fi
}
cat() {
  [ "$1" = /etc/os-release ] || return 99
  printf 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nID=debian\n'
}
ifconfig() {
  [ "$fixture_missing" = 0 ] || return 127
  [ "$fixture_empty" = 0 ] || return 0
  case "${1:-all}" in
    all|eth0) printf 'eth0: flags=4099<UP,BROADCAST,MULTICAST> mtu 1500\n    RX packets 0 bytes 0 (0.0 B)\n    TX packets 0 bytes 0 (0.0 B)\n' ;;
    wlan0|ens18) printf '%s: flags=4163<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500\n    RX packets 42 bytes 12582912 (12.0 MiB)\n    TX packets 21 bytes 3145728 (3.0 MiB)\n' "$1" ;;
    *) return 1 ;;
  esac
  if [ "${1:-all}" = all ]; then
    printf 'wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500\n    RX packets 42 bytes 12582912 (12.0 MiB)\n    TX packets 21 bytes 3145728 (3.0 MiB)\n'
  fi
}''',
        ])
        result = subprocess.run(
            ["bash", "--noprofile", "--norc"],
            input=setup + "\n" + BLOCK + '\nprintf "%s\\n%s\\n%s\\n" "$networkDevice" "$network_rx" "$network_tx"\n',
            text=True, capture_output=True, check=True,
            env={"PATH": os.environ["PATH"], "LC_ALL": "C"},
        )
        self.assertEqual(result.stderr, "")
        return result.stdout.splitlines()

    def test_wifi_traffic_not_idle_ethernet(self):
        self.assertEqual(self.run_block("wlan0"), ["wlan0", "12.0MiB", "3.0MiB"])

    def test_vm_non_eth_interface(self):
        self.assertEqual(self.run_block("ens18"), ["ens18", "12.0MiB", "3.0MiB"])

    def test_ethernet_unchanged(self):
        self.assertEqual(self.run_block("eth0"), ["eth0", "0.0B", "0.0B"])

    def test_no_active_interface_preserves_first_interface_fallback(self):
        self.assertEqual(self.run_block(""), ["", "0.0B", "0.0B"])

    def test_missing_ifconfig(self):
        self.assertEqual(self.run_block("wlan0", missing=True), ["wlan0", "", ""])

    def test_empty_ifconfig(self):
        self.assertEqual(self.run_block("wlan0", empty=True), ["wlan0", "", ""])


if __name__ == "__main__":
    unittest.main(verbosity=2)
