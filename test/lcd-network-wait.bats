#!/usr/bin/env bats

setup() {
  export sandbox="$BATS_TEST_TMPDIR"
  admin="$BATS_TEST_DIRNAME/../home.admin"
  export PATH="$sandbox/bin:$PATH" TERM=dumb
  mkdir -p "$sandbox/bin" "$sandbox/admin/setup.scripts" "$sandbox/net"
  touch "$sandbox/admin/raspiblitz.info" "$sandbox/admin/_version.info"
  printf '%s\n' '#!/bin/bash' ':' >"$sandbox/admin/_cache.sh"
  printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$@"' >"$sandbox/bin/dialog"
  printf '%s\n' '#!/bin/bash' ':' >"$sandbox/bin/sleep"
  chmod +x "$sandbox/bin/"* "$sandbox/admin/_cache.sh"
  render="$sandbox/admin/setup.scripts/eventInfoWait.sh"
  sed -e "s|/home/admin|$sandbox/admin|g" -e "s|/sys/class/net|$sandbox/net|g" \
    "$admin/setup.scripts/eventInfoWait.sh" >"$render"
  chmod +x "$render"
}

@test "unplugged physical link shows a network hint during early LCD startup" {
  mkdir -p "$sandbox/net/eth0/device"
  echo 0 >"$sandbox/net/eth0/carrier"
  run bash "$render" starting bootstrap lcd
  [ "$status" -eq 0 ]
  [[ "$output" == *"No network link"* && "$output" == *"Ethernet cable"* ]]
  run bash "$render" starting bootstrap ssh
  [[ "$output" == *"Starting RaspiBlitz"* ]]
}

@test "unknown carrier or a second connected physical interface preserves the startup message" {
  mkdir -p "$sandbox/net/eth0/device" "$sandbox/net/wlan0/device" "$sandbox/net/lo"
  echo 1 >"$sandbox/net/lo/carrier"
  run bash "$render" system-init '' lcd
  [[ "$output" == *"Starting RaspiBlitz"* ]]
  echo 0 >"$sandbox/net/eth0/carrier"
  echo 1 >"$sandbox/net/wlan0/carrier"
  run bash "$render" system-init '' lcd
  [[ "$output" == *"Starting RaspiBlitz"* ]]
}

@test "configured and fresh nodes show bootstrap network events before the normal dashboard" {
  # Run one LCD refresh; keep the real dispatcher and renderer.
  sed -e "s|/home/admin|$sandbox/admin|g" -e "s|/mnt/hdd/app-data|$sandbox/data|g" \
    -e 's/^while :$/for iteration in once/' "$admin/00infoLCD.sh" >"$sandbox/lcd"
  for phase in boot done; do
    for sample in 'noIP-LAN:Waiting for Network' 'noIP-WIFI:Waiting for Network' 'noDHCP:Waiting for local IP' 'noInternet:Waiting for Internet'; do
      printf 'setupPhase=%s\nstate=%s\n' "$phase" "${sample%%:*}" >"$sandbox/admin/raspiblitz.info"
      run env USER=pi bash "$sandbox/lcd" --pause 0
      [ "$status" -eq 0 ]
      [[ "$output" == *"${sample#*:}"* ]]
    done
  done
}

@test "bootstrap displays missing link and DHCP promptly, probes the Internet only with an address" {
  mkdir -p "$sandbox/admin/config.scripts"
  cat >"$sandbox/admin/config.scripts/internet.sh" <<'MOCK'
#!/bin/bash
echo "$*" >> "$sandbox/probes"
printf 'localip=%s\ndhcp=%s\nnetwork_device=%s\nconfigWifiExists=0\n' "$address" "$lease" "$iface"
[ "${2:-}" = online ] && echo "online=$reachable"
MOCK
  printf '%s\n' '#!/bin/bash' 'echo "$*" >> "$sandbox/state"' >"$sandbox/admin/_cache.sh"
  chmod +x "$sandbox/admin/config.scripts/internet.sh"
  # Keep the production wait loop, limiting it to one retry per fixture.
  sed -n '/^# WAIT LOOP: LOCALNET/,/^# PRE-SETUP INIT(RASPBERRY PI)/p' "$admin/_bootstrap.sh" |
    sed -e "s|/home/admin|$sandbox/admin|g" -e 's/^while true; do/for iteration in once; do/' >"$sandbox/wait"
  export logFile="$sandbox/log" address= lease=1 iface= reachable=0
  for scenario in unplugged dhcp linklocal offline online; do
    case "$scenario" in
      unplugged) expected=noIP-LAN ;;
      dhcp) iface=eth0; expected=noDHCP ;;
      linklocal) address=169.254.1.2; lease=0; expected=noDHCP ;;
      offline) address=192.0.2.10; lease=1; expected=noInternet ;;
      online) reachable=1; expected= ;;
    esac
    : >"$sandbox/probes"; : >"$sandbox/state"
    run bash "$sandbox/wait"
    [ "$status" -eq 0 ]
    if [ -n "$expected" ]; then grep -Fx "set state $expected" "$sandbox/state"; else [ ! -s "$sandbox/state" ]; fi
    if [[ "$scenario" = offline || "$scenario" = online ]]; then
      grep -Fx 'status online' "$sandbox/probes"
    else
      [ "$(cat "$sandbox/probes")" = status ]
    fi
  done
}
