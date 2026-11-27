# Running tests

## Install bats
```
sudo apt install bats
```

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
bats --verbose-run ./shutdown.bats
```

## Checking watchdog shutdown on a release candidate

Use a test node available for a reboot and a power cycle. The original reports in
[#4534](https://github.com/raspiblitz/raspiblitz/issues/4534) involved Raspberry
Pi 4 hardware, including the first boot after an image upgrade. Record the board
revision, image version and variant, running apps and whether the node is in
setup or already operational. Use HDMI or a serial console so observations
continue after SSH disconnects.

1. Record the current boot ID with `cat /proc/sys/kernel/random/boot_id` and the
   watchdog driver with `cat /sys/class/watchdog/watchdog0/identity`, if present.
2. From the main menu select **REBOOT**, confirm, and time the return to login.
   Check for a new boot ID and that the previously enabled node services return.
3. Select **OFF**, confirm, and observe the board's shutdown indication. Once the
   board is off, start it normally. Check the boot ID and node services again.
4. Repeat the observed failing path on the corresponding image/upgrade state.
   If it stalls, note the elapsed time and the last visible console messages.
   Record whether it eventually reboots or powers off. If previous boot logs
   were retained, inspect `journalctl -b -1 -e` locally. A final watchdog log
   line alone does not establish a hang.

Record virtual watchdog results and physical board results separately.
