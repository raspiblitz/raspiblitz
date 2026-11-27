#!/usr/bin/env python3
"""Read a SMART summary for a disk already selected by blitz.hardware.sh."""
import json
import subprocess
import sys


def read_smart(device, transport, sat=False):
    options = ["smartctl", "-a", "-j"]
    if transport != "nvme":
        options += ["-n", "standby,2"]
    if sat:
        options += ["-d", "sat"]
    result = subprocess.run(options + [device], capture_output=True, timeout=20)
    try:
        return json.loads(result.stdout), result.returncode
    except (ValueError, UnicodeError):
        return {}, result.returncode or 1


def asleep(data):
    return any("STANDBY" in msg.get("string", "").upper()
               or "SLEEP mode" in msg.get("string", "")
               for msg in data.get("smartctl", {}).get("messages", []))


def report(device, transport):
    data, status = read_smart(device, transport)
    if (transport == "usb" and status & 7 and not asleep(data)
            and "smart_status" not in data and "nvme_smart_health_information_log" not in data):
        data, status = read_smart(device, transport, sat=True)
    if asleep(data):
        print("Drive asleep; health check skipped.")
        return 0

    passed = data.get("smart_status", {}).get("passed")
    print("Overall SMART health:", {True: "PASSED", False: "FAILED"}.get(passed, "unavailable"))
    attention = passed is not True or bool(status)
    if status & 7:
        print("Some SMART commands were unavailable on this drive or bridge.")
    if status & 0xf0:
        print("SMART reports an attribute or a logged error to review.")

    for attr in data.get("ata_smart_attributes", {}).get("table", []):
        if attr.get("id") in (5, 187, 196, 197, 198):
            raw = attr.get("raw", {}).get("value")
            flag = isinstance(raw, int) and raw > 0
            print(f"ATA {attr['id']} {attr.get('name', '')}: {raw if raw is not None else 'unavailable'}"
                  + (" (review)" if flag else ""))
            attention |= flag
    count = data.get("ata_smart_error_log", {}).get("summary", {}).get("count")
    if isinstance(count, int):
        print(f"ATA logged errors: {count}")
        attention |= count > 0

    nvme = data.get("nvme_smart_health_information_log", {})
    for field, label in (("critical_warning", "NVMe critical warning"),
                         ("media_errors", "NVMe media/data integrity errors"),
                         ("num_err_log_entries", "NVMe error log entries")):
        if field in nvme:
            print(f"{label}: {nvme[field]}")
            attention |= field != "num_err_log_entries" and nvme[field] != 0
    used = nvme.get("percentage_used")
    if isinstance(used, int):
        suffix = " (critical wear)" if used > 90 else " (wear warning)" if used > 75 else ""
        print(f"Estimated NVMe endurance used: {used}%{suffix}")
        attention |= used > 75
    units = nvme.get("data_units_written")
    if isinstance(units, int):
        print(f"NVMe host writes: {units * 512000 / 10**12:.2f} TB (compare with the model's rated TBW).")
    return int(attention)


if __name__ == "__main__":
    try:
        sys.exit(report(sys.argv[1], sys.argv[2]))
    except subprocess.TimeoutExpired:
        print("Drive did not respond within 20 seconds.")
        sys.exit(1)
