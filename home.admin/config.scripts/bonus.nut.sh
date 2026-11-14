#!/bin/bash
APPID="nut"
VERSION="0.1"
# bonus.nut.sh — Universal NUT Installer for RaspiBlitz
# References:
# Network UPS Tools (NUT): https://github.com/networkupstools/nut
# NUT report script reference: https://rogerprice.org/NUT/nut-report
# NUT configuration examples: https://rogerprice.org/NUT/ConfigExamples.A5.pdf
# Features:
#  - Auto-detect USB UPS (HID, QX, Riello)
#  - Riello USB quirk: force riello_usb + user=root
#  - Bookworm-safe systemd override for nut-monitor (PIDFile issue)
#  - Early-shutdown timer (300s ONBATT) via upssched
#  - Uses shutdown.return when supported, falls back to FSD-only otherwise
#  - I2C UPS HAT awareness (PiJuice / Geekworm / Waveshare) with safe messaging
#  - Report mode: runs nut-report.sh if present, or prints how to get it
#  - Check mode: Show nut journalctl and shutdown process (info only)
# Location: /home/admin/config.scripts/bonus.nut.sh
#

set -e

# ---------------------------------------------------------------------------
# AUTO-SUDO
# ---------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "### Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

CMD="$1"

# ---------------------------------------------------------------------------
# HELP
# ---------------------------------------------------------------------------
if [ $# -eq 0 ] || [[ "$CMD" =~ ^(-h|--help|help)$ ]]; then
  echo "### RaspiBlitz NUT Control Script (v$VERSION)"
  echo ""
  echo "Usage:"
  echo "  $0 install       Install & configure NUT"
  echo "  $0 start         Start NUT services"
  echo "  $0 stop          Stop NUT services"
  echo "  $0 restart       Restart NUT services"
  echo "  $0 status        Show NUT service + UPS status"
  echo "  $0 check         Show nut journalctl and shutdown process (info only)"
  echo "  $0 report        Run NUT report (nut-report.sh)"
  echo "  $0 uninstall     Remove NUT completely"
  echo "  $0 menu          Open NUT menu in RaspiBlitz SSH UI"
  echo ""
  exit 0
fi

# ---------------------------------------------------------------------------
# SERVICE CONTROL
# ---------------------------------------------------------------------------
if [ "$CMD" = "stop" ]; then
  systemctl stop nut-monitor || true
  systemctl stop nut-server || true
  echo "### NUT services stopped"
  exit 0
fi

if [ "$CMD" = "start" ]; then
  systemctl start nut-server || true
  systemctl start nut-monitor || true
  echo "### NUT services started"
  exit 0
fi

if [ "$CMD" = "restart" ]; then
  systemctl restart nut-server || true
  systemctl restart nut-monitor || true
  echo "### NUT services restarted"
  exit 0
fi

if [ "$CMD" = "status" ]; then
  echo "### NUT Service Status"
  systemctl status nut-server --no-pager || true
  echo ""
  systemctl status nut-monitor --no-pager || true
  echo ""
  echo "### UPS Status (upsc)"
  if upsc ups@localhost >/dev/null 2>&1; then
    upsc ups@localhost | sed 's/^/  /'
  else
    echo "UPS not detected or NUT not configured."
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# CHECK MODE (SAFE CHECK ONLY — AUTO EXIT, NO CTRL+C REQUIRED)
# ---------------------------------------------------------------------------
if [ "$CMD" = "check" ]; then
  echo "### NUT JOURNALCTL CHECK (INFO ONLY)"
  echo "### No shutdown will be triggered."
  echo "### This will show live NUT logs for 20 seconds and then auto-exit."
  read -rp "Continue? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "### Check cancelled."
    exit 0
  fi

  logger "NUT CHECK: Check only — following logs, no UPS commands, no shutdown."

  echo ""
  echo "### STEP 1: Following NUT logs for 20 seconds..."
  echo "### Command: journalctl -u nut-monitor -u nut-server -u nut-driver@ups -f"
  echo ""

  journalctl -u nut-monitor -u nut-server -u nut-driver@ups -f &
  JPID=$!

  sleep 20
  kill $JPID 2>/dev/null || true
  wait $JPID 2>/dev/null || true

  echo ""
  echo "### STEP 2: Explanation of REAL behavior (not executed in this check)"
  echo "### When mains power is lost and UPS goes ONBATT:"
  echo "###   1) nut-monitor logs: 'UPS ups@localhost on battery'"
  echo "###   2) upssched starts timer: earlyshutdown (300 seconds)"
  echo "###   3) If power returns before 300s:"
  echo "###        - nut-monitor logs: 'UPS ups@localhost on line'"
  echo "###        - upssched cancels timer earlyshutdown"
  echo "###   4) If power does NOT return within 300s:"
  echo "###        - upssched EXECUTE earlyshutdown"
  echo "###        - upssched-cmd calls upsmon -c fsd"
  echo "###        - upsmon runs:"
  echo "###            SHUTDOWNCMD \"/home/admin/config.scripts/blitz.shutdown.sh\""
  echo "###        - RaspiBlitz safely stops bitcoind, lnd, and shuts down."
  echo ""
  echo "### This check did NOT trigger any of that — it only showed logs."
  echo "### For the ultimate confidence test, you can repeat a real power cut."
  echo ""
  echo "### Check finished (nut logs and principles of shutdown process only)."
  exit 0
fi

# ---------------------------------------------------------------------------
# REPORT MODE
# ---------------------------------------------------------------------------
if [ "$CMD" = "report" ]; then
  if [ -x /usr/local/sbin/nut-report.sh ]; then
    /usr/local/sbin/nut-report.sh
  elif [ -x /usr/sbin/nut-report.sh ]; then
    /usr/sbin/nut-report.sh
  else
    echo "nut-report.sh not found."
    echo "Download from: https://rogerprice.org/NUT/nut-report"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# UNINSTALL
# ---------------------------------------------------------------------------
if [ "$CMD" = "uninstall" ]; then
  systemctl stop nut-monitor || true
  systemctl stop nut-server || true
  systemctl disable nut-monitor || true
  systemctl disable nut-server || true

  apt-get remove -y nut nut-client nut-server || true

  rm -f /etc/nut/nut.conf
  rm -f /etc/nut/ups.conf
  rm -f /etc/nut/upsd.conf
  rm -f /etc/nut/upsd.users
  rm -f /etc/nut/upsmon.conf
  rm -f /etc/nut/upssched.conf
  rm -f /usr/bin/upssched-cmd

  rm -f /etc/killpower
  rm -rf /run/nut

  rm -rf /etc/systemd/system/nut-monitor.service.d

  echo "### NUT successfully uninstalled"
  exit 0
fi

# ---------------------------------------------------------------------------
# INSTALL
# ---------------------------------------------------------------------------
if [ "$CMD" = "install" ]; then

  apt-get update
  apt-get install -y nut nut-client nut-server

  mkdir -p /etc/nut
  chown root:nut /etc/nut
  chmod 750 /etc/nut

  I2C_HINT=0
  if [ -e /dev/i2c-1 ]; then
    if lsmod | grep -qi pijuice; then I2C_HINT=1; fi
    if command -v i2cdetect >/dev/null 2>&1; then
      if i2cdetect -y 1 | grep -qE '36|37|43|75'; then I2C_HINT=1; fi
    fi
  fi

  if [ "$I2C_HINT" -eq 1 ]; then
    echo "### I2C UPS HAT detected — NUT may not apply to this device."
  fi

  SCAN_OUTPUT=$(nut-scanner 2>/dev/null || true)

  if [ -z "$SCAN_OUTPUT" ]; then
    if [ "$I2C_HINT" -eq 1 ]; then
      echo "### No USB UPS found, but I2C HAT detected — exiting."
      exit 1
    fi
    echo "### No USB UPS detected — exiting."
    exit 1
  fi

  DRIVER_GUESS=$(echo "$SCAN_OUTPUT" | grep -i 'driver' | head -n1 | awk -F'"' '{print $2}')
  PORT_GUESS=$(echo "$SCAN_OUTPUT" | grep -i 'port' | head -n1 | awk -F'"' '{print $2}')
  VENDORID=$(echo "$SCAN_OUTPUT" | grep -i 'vendorid' | head -n1 | awk -F'"' '{print $2}')
  PRODUCTID=$(echo "$SCAN_OUTPUT" | grep -i 'productid' | head -n1 | awk -F'"' '{print $2}')

  [ -z "$PORT_GUESS" ] && PORT_GUESS="auto"

  UPS_DRIVER=""
  UPS_EXTRA=""
  UPS_USER="nut"

  if echo "$VENDORID:$PRODUCTID" | grep -qiE '04b4:5500'; then
    UPS_DRIVER="riello_usb"
    UPS_USER="root"
  else
    if echo "$DRIVER_GUESS" | grep -qi 'usbhid-ups'; then
      UPS_DRIVER="usbhid-ups"
    elif echo "$DRIVER_GUESS" | grep -qi 'nutdrv_qx'; then
      UPS_DRIVER="nutdrv_qx"
      UPS_EXTRA="subdriver = auto"
    else
      if echo "$VENDORID" | grep -qiE '0665|0925|0d9f|10af|16c0'; then
        UPS_DRIVER="nutdrv_qx"
        UPS_EXTRA="subdriver = auto"
      else
        UPS_DRIVER="usbhid-ups"
      fi
    fi
  fi

  UPS_PORT="$PORT_GUESS"

  while true; do
    read -rsp "Enter NUT monitor password: " NUTPASS
    echo
    read -rsp "Confirm password: " NUTPASS2
    echo
    [ "$NUTPASS" = "$NUTPASS2" ] && [ -n "$NUTPASS" ] && break
    echo "Passwords do not match — try again."
  done

  echo "MODE=standalone" > /etc/nut/nut.conf

  cat > /etc/nut/ups.conf <<EOF
[ups]
  driver = $UPS_DRIVER
  port = $UPS_PORT
  desc = "Auto-detected UPS"
  pollinterval = 2
EOF

  [ -n "$UPS_EXTRA" ] && echo "  $UPS_EXTRA" >> /etc/nut/ups.conf
  [ "$UPS_USER" != "nut" ] && echo "  user = $UPS_USER" >> /etc/nut/ups.conf

  cat > /etc/nut/upsd.users <<EOF
[monuser]
  password = $NUTPASS
  upsmon master
  actions = SET
  instcmds = ALL
EOF

  echo "LISTEN 127.0.0.1 3493" > /etc/nut/upsd.conf

  cat > /etc/nut/upsmon.conf <<EOF
RUN_AS_USER nut
MONITOR ups@localhost 1 monuser $NUTPASS master

MINSUPPLIES 1
SHUTDOWNCMD "/home/admin/config.scripts/blitz.shutdown.sh"
POWERDOWNFLAG /etc/killpower

NOTIFYCMD /usr/sbin/upssched

NOTIFYFLAG ONLINE     SYSLOG+WALL+EXEC
NOTIFYFLAG ONBATT     SYSLOG+WALL+EXEC
NOTIFYFLAG LOWBATT    SYSLOG+WALL
NOTIFYFLAG FSD        SYSLOG+WALL
NOTIFYFLAG COMMOK     SYSLOG+WALL+EXEC
NOTIFYFLAG COMMBAD    SYSLOG+WALL+EXEC
NOTIFYFLAG SHUTDOWN   SYSLOG+WALL
FINALDELAY 30
EOF

  cat > /etc/nut/upssched.conf <<EOF
CMDSCRIPT /usr/bin/upssched-cmd
PIPEFN /run/nut/upssched.pipe
LOCKFN /run/nut/upssched.lock

AT ONBATT * START-TIMER earlyshutdown 300
AT ONLINE * CANCEL-TIMER earlyshutdown
AT earlyshutdown * EXECUTE earlyshutdown
EOF

  cat > /usr/bin/upssched-cmd <<'EOF'
#!/bin/bash
logger "UPSSCHED-CMD invoked with argument: $1"
NUTPASS=$(grep -E '^MONITOR ' /etc/nut/upsmon.conf | awk '{print $5}')

case "$1" in
  earlyshutdown)
    if upscmd -l ups 2>/dev/null | grep -q 'shutdown.return'; then
      /usr/bin/upscmd -u monuser -p "$NUTPASS" ups shutdown.return
    fi
    /usr/sbin/upsmon -c fsd
    ;;
esac
EOF

  chmod +x /usr/bin/upssched-cmd

  chown root:nut /etc/nut/*
  chmod 640 /etc/nut/*
  chmod 755 /usr/bin/upssched-cmd

  systemctl enable nut-server
  systemctl enable nut-monitor

  mkdir -p /etc/systemd/system/nut-monitor.service.d
  echo -e "[Service]\nPIDFile=" > /etc/systemd/system/nut-monitor.service.d/override.conf

  systemctl daemon-reload
  systemctl restart nut-server
  systemctl restart nut-monitor

  echo "### Waiting for UPS to become READY..."

  READY=0
  if echo "$VENDORID:$PRODUCTID" | grep -qiE '04b4:5500'; then
    RETRIES=12
  else
    RETRIES=5
  fi

  for i in $(seq 1 $RETRIES); do
    STATUS=$(upsc ups@localhost 2>/dev/null | grep '^ups.status:' | awk '{print $2}')
    if [ "$STATUS" = "OL" ] || [ "$STATUS" = "OB" ] || [ "$STATUS" = "LB" ]; then
      READY=1
      break
    fi
    sleep 2
  done

  if [ "$READY" -eq 0 ]; then
    echo "ERROR: UPS did not reach READY state in time."
    exit 1
  fi

  echo "### UPS is READY:"
  upsc ups@localhost | sed 's/^/  /'

  echo "### Checking shutdown.return support..."

  if upscmd -l ups 2>/dev/null | grep -q 'shutdown.return'; then
    echo "### UPS supports shutdown.return — auto-restart enabled."
  else
    echo "### UPS does NOT support shutdown.return."
  fi

  echo "### NUT installation complete."
  exit 0
fi

# ---------------------------------------------------------------------------
# MENU (RaspiBlitz SSH integration)
# ---------------------------------------------------------------------------
if [ "$CMD" = "menu" ]; then
  CHOICE=$(dialog --clear --stdout \
    --backtitle "RaspiBlitz - NUT UPS Integration" \
    --title "NUT (Network UPS Tools)" \
    --menu "Choose action:" 14 70 7 \
      install   "Install & configure NUT" \
      status    "Show NUT + UPS status" \
      check     "Follow NUT logs (20s) + explain shutdown chain" \
      report    "Run NUT report (nut-report.sh)" \
      restart   "Restart NUT services" \
      uninstall "Uninstall NUT completely" \
      cancel    "Back to main menu")

  case "$CHOICE" in
    install)   "$0" install ;;
    status)    "$0" status ;;
    check)     "$0" check ;;
    report)    "$0" report ;;
    restart)   "$0" restart ;;
    uninstall) "$0" uninstall ;;
    *)         ;;
  esac
  exit 0
fi

echo "Unknown command: $CMD"
exit 1
