#!/usr/bin/env python3
"""Exercise an existing disposable LNbits wallet through the real menu and HTTP API."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile
import time
from urllib.request import Request, urlopen


DATA = Path("/run/raspiblitz-lnbits-e2e")
CONFIG = Path("/mnt/hdd/app-data/LNBits/data/.env")
UPDATER = "/home/admin/config.scripts/bonus.lnbits.sh"
TARGET = "4fa70f338d274e14fc82746a83fba5c2c658211f"
V170 = "aaeff9a62a9310d9d14c22cc188bbd21c347577d"
LEGACY = "88b01e60795c488ae9fd8c2e634f3d218b901aaa"
TITLE = "RaspiBlitz release test"


def call(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def api(path, payload=None, headers=None):
    request = Request("http://127.0.0.1:5000" + path, headers=headers or {})
    if payload is not None:
        request.add_header("Content-Type", "application/json")
        request.data = json.dumps(payload).encode()
    with urlopen(request, timeout=8) as response:
        return json.load(response)


def wallet_check():
    wallet = json.loads((DATA / "wallet.json").read_text())
    result = api("/api/v1/wallet", headers={"X-Api-Key": wallet["adminkey"]})
    assert (result["id"], result["name"], result["balance"]) == (wallet["id"], TITLE, 0)
    assert isinstance(api("/api/v1/health")["server_time"], int)


def prepare():
    state = DATA / "wallet.json"
    if not state.exists():
        if installed_head() == LEGACY:
            wallet = api("/api/v1/account", {"name": TITLE})
        else:
            password = secrets.token_urlsafe(24)
            token = api("/api/v1/auth/register", {
                "username": "rbtest" + secrets.token_hex(5), "password": password,
                "password_repeat": password,
            })["access_token"]
            wallet = api("/api/v1/wallet", {"name": TITLE}, {"Authorization": "Bearer " + token})
        with state.open("x") as out:
            json.dump({"id": wallet["id"], "adminkey": wallet["adminkey"]}, out)
    wallet_check()


def installed_head():
    return call("sudo", "-u", "lnbits", "git", "-C", "/home/lnbits/lnbits",
                "rev-parse", "HEAD", capture_output=True).stdout.strip()


def wait_wallet():
    deadline = time.monotonic() + 60
    while True:
        try:
            wallet_check()
            return
        except (OSError, AssertionError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.3)


class Menu:
    def __init__(self):
        self.session = "lnbits-e2e-" + secrets.token_hex(5)

    def keys(self, *keys):
        call("tmux", "send-keys", "-t", self.session, *keys)

    def screen(self, color=False):
        return call("tmux", "capture-pane", "-pe" if color else "-p",
                    "-t", self.session, capture_output=True).stdout

    def wait(self, text, timeout=45):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            screen = self.screen()
            if text in screen:
                return screen
            if "LNbits update failed" in screen and text == "PRESS ENTER to continue":
                raise AssertionError("Update failed in the operator menu")
            time.sleep(0.3)
        raise AssertionError("Expected menu text: " + text)

    def open(self):
        call("tmux", "new-session", "-d", "-s", self.session, "-x", "100", "-y", "32",
             "sudo -Hu admin env TERM=xterm /home/admin/00mainMenu.sh")
        self.wait("Choose one of the following options")
        self.keys("u", "Enter")
        self.wait("Update LNbits")
        for _ in range(12):
            self.keys("l")
            time.sleep(0.15)
            row = next(line for line in self.screen(color=True).splitlines() if "Update LNbits" in line)
            colors = re.findall(r"\x1b\[([0-9;]*)m", row.split("Update LNbits")[0])
            if any("44" in color.split(";") for color in colors[-2:]):
                self.keys("Enter")
                return
        raise AssertionError("LNbits menu entry did not receive focus")

    def close(self):
        subprocess.run(["tmux", "kill-session", "-t", self.session], check=False, capture_output=True)


@contextmanager
def blocked_backup(enabled):
    if not enabled:
        yield lambda: None
        return
    pg = any(line.startswith("LNBITS_DATABASE_URL=postgres") for line in CONFIG.read_text().splitlines())
    target = Path("/mnt/hdd/app-data/backup") / ("lnbits_db" if pg else "lnbits_sqlite")
    saved = target.with_name(".rb-e2e-" + secrets.token_hex(8))
    if target.exists():
        if not target.is_dir() or target.is_symlink():
            raise RuntimeError("Unexpected backup target")
        target.rename(saved)
    try:
        target.touch(exist_ok=False)
        def repair():
            if target.is_file():
                target.unlink()
            if saved.is_dir():
                saved.rename(target)
        yield repair
    finally:
        if target.is_file():
            target.unlink()
        if saved.is_dir():
            saved.rename(target)


@contextmanager
def failed_start(enabled):
    dropin = Path("/run/systemd/system/lnbits.service.d/90-raspiblitz-e2e-start.conf")
    if not enabled:
        yield lambda: None
        return
    dropin.parent.mkdir(parents=True, exist_ok=True)
    with dropin.open("x") as out:
        out.write("[Service]\nExecStartPre=/usr/bin/false\n")
    def remove():
        if dropin.is_file():
            dropin.unlink()
            call("systemctl", "daemon-reload")
    try:
        call("systemctl", "daemon-reload")
        yield remove
    finally:
        remove()


@contextmanager
def blocked_fetch(enabled):
    if not enabled:
        yield
        return
    git = ["sudo", "-u", "lnbits", "git", "-C", "/home/lnbits/lnbits", "config", "--local"]
    assert subprocess.run(git + ["--get", "protocol.https.allow"], capture_output=True).returncode == 1
    call(*git, "protocol.https.allow", "never")
    try:
        yield
    finally:
        call(*git, "--unset", "protocol.https.allow")


def menu_update(case, old_head):
    assert re.fullmatch(r"[a-f0-9]{40}", old_head)
    assert (old_head == TARGET) == (case == "previous")
    assert installed_head() == old_head, "Restore the pre-update fixture before the menu run"
    wallet_check()
    menu = Menu()
    try:
        with blocked_backup(case in ("keep-stopped", "retry")) as repair, \
                failed_start(case == "failed-start") as fix_start, blocked_fetch(case == "previous"):
            menu.open()
            if case != "update":
                if case == "failed-start":
                    dialog = menu.wait("did not pass its health check", timeout=600)
                    assert installed_head() == TARGET
                elif case == "previous":
                    dialog = menu.wait("Download of the LNbits release failed. Service:")
                else:
                    dialog = menu.wait("Database backup failed. Service: inactive")
                dialog = menu.wait("Retry the update")
                assert not service_active()
                previous_offered = "Start the previous verified version" in dialog
                assert previous_offered == (case == "previous")
                if case == "previous":
                    assert previous_offered
                    menu.keys("Down", "Down", "Enter")
                    menu.wait("The previous version is running.")
                    assert installed_head() == old_head
                    wait_wallet()
                    return
                if case == "keep-stopped":
                    menu.keys("Enter")  # BACK is the default
                    time.sleep(1)
                    call("systemctl", "start", "lnbits")
                    assert not service_active(), "The interrupted update must inhibit startup"
                    assert installed_head() == old_head
                    return
                repair()
                fix_start()
                menu.keys("Down", "Enter")  # RETRY, now that the backup volume is available
                # Wait for the previous dialog to clear before looking for a new failure.
                end = time.monotonic() + 8
                while "LNbits update failed" in menu.screen() and time.monotonic() < end:
                    time.sleep(0.15)
            success = menu.wait("PRESS ENTER to continue", timeout=600)
            assert "reset all wallet keys" in success
            assert installed_head() == TARGET
            wait_wallet()
            menu.keys("Enter")
    finally:
        menu.close()


def custom_unit():
    wallet_check()
    old_head = installed_head()
    dropin = Path("/run/systemd/system/lnbits.service.d/91-raspiblitz-e2e-port.conf")
    dropin.parent.mkdir(parents=True, exist_ok=True)
    with dropin.open("x") as out:
        out.write("[Service]\nExecStart=\nExecStart=/home/lnbits/lnbits/.venv/bin/lnbits --port 5011 --host 127.0.0.1\n")
    try:
        call("systemctl", "daemon-reload")
        result = subprocess.run([UPDATER, "update"], text=True, capture_output=True)
        assert result.returncode and "Custom LNbits service command" in result.stdout
        assert installed_head() == old_head and service_active()
        wallet_check()
    finally:
        dropin.unlink()
        call("systemctl", "daemon-reload")


def health_available():
    try:
        return isinstance(api("/api/v1/health")["server_time"], int)
    except OSError:
        return False


def service_active():
    return subprocess.run(["systemctl", "is-active", "--quiet", "lnbits"]).returncode == 0


def interrupted_trial():
    assert installed_head() == TARGET
    wallet_check()
    permit = Path("/run/raspiblitz-lnbits/start-once")
    dropin = Path("/run/systemd/system/lnbits.service.d/95-raspiblitz-e2e-interrupt.conf")
    dropin.parent.mkdir(parents=True, exist_ok=True)
    with dropin.open("x") as out:
        out.write("[Service]\nExecStartPre=/bin/sleep 8\nExecStartPost=/bin/false\n")
    process = None
    try:
        call("systemctl", "daemon-reload")
        process = subprocess.Popen([UPDATER, "update"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 240
        while time.monotonic() < deadline:
            pid = call("systemctl", "show", "lnbits", "-P", "ControlPID", capture_output=True).stdout.strip()
            try:
                waiting = Path("/proc", pid, "cmdline").read_bytes().rstrip(b"\0") == b"/bin/sleep\0" + b"8"
            except FileNotFoundError:
                waiting = False
            if waiting:
                break
            assert process.poll() is None, "Updater exited before the startup trial"
            time.sleep(0.15)
        else:
            raise AssertionError("Trial never reached its controlled interruption point")
        assert not os.path.lexists(permit), "The startup permit must be consumed before the application starts"
        process.kill()
        process.wait(timeout=5)
        deadline = time.monotonic() + 75
        while time.monotonic() < deadline:
            state = call("systemctl", "show", "lnbits", "-P", "ActiveState", capture_output=True).stdout.strip()
            if state in ("failed", "inactive"):
                break
            time.sleep(0.3)
        else:
            raise AssertionError("An interrupted, unsuccessful trial remained active")
        call("systemctl", "start", "lnbits")
        assert not service_active()
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        dropin.unlink()
        call("systemctl", "daemon-reload")
    call(UPDATER, "update", stdout=subprocess.DEVNULL)
    wait_wallet()


def stopped_update(old_head):
    assert old_head != TARGET and installed_head() == old_head
    wallet_check()
    call("systemctl", "stop", "lnbits")
    call(UPDATER, "update", stdout=subprocess.DEVNULL)
    assert installed_head() == TARGET and not service_active()
    call("systemctl", "start", "lnbits")
    wait_wallet()


def restore(backend):
    wallet_check()
    source = Path("/mnt/hdd/app-data/backup")
    pg = backend == "postgres"
    dumps = source / ("lnbits_db" if pg else "lnbits_sqlite")
    pattern = "*.sql" if pg else "*.tar"
    call(UPDATER, "backup", stdout=subprocess.DEVNULL)
    wait_wallet()
    archive = max(dumps.glob(pattern), key=lambda path: path.stat().st_mtime_ns)
    assert archive.stat().st_mode & 0o077 == 0
    wallet_id = json.loads((DATA / "wallet.json").read_text())["id"]
    with tempfile.TemporaryDirectory(dir=DATA) as temp:
        valid = Path(temp) / archive.name
        shutil.copyfile(archive, valid)
        # A successful restore must bring back a value that is absent in the live DB.
        if pg:
            call("sudo", "-u", "postgres", "psql", "-Xq", "-v", "ON_ERROR_STOP=1",
                 "-v", "wallet=" + wallet_id, "-d", "lnbits_db",
                 input="UPDATE wallets SET name='after backup' WHERE id=:'wallet';")
        else:
            with sqlite3.connect(CONFIG.parent.parent / "database.sqlite3") as db:
                assert db.execute("UPDATE wallets SET name=? WHERE id=?", ("after backup", wallet_id)).rowcount == 1
        call("systemctl", "restart", "lnbits")  # discard the in-memory wallet cache
        deadline = time.monotonic() + 60
        while not health_available():
            if time.monotonic() > deadline:
                raise AssertionError("No health response after the marker change")
            time.sleep(0.3)
        key = json.loads((DATA / "wallet.json").read_text())["adminkey"]
        assert api("/api/v1/wallet", headers={"X-Api-Key": key})["name"] == "after backup"
        # A valid empty archive/SQL file exercises the app schema check.
        invalid = Path(temp) / ("other.sql" if pg else "other.tar")
        if pg:
            invalid.write_text("SELECT 1;\n")
        else:
            with tarfile.open(invalid, "w"):
                pass
        def must_reject(path):
            result = subprocess.run([UPDATER, "restore", str(path)], capture_output=True)
            assert result.returncode != 0 and not service_active()
            assert Path("/etc/systemd/system/lnbits.service.d/50-raspiblitz-update.conf").is_file()
        must_reject(invalid)
        # A real start failure *after* the swap must also preserve a retryable state.
        dropin = Path("/run/systemd/system/lnbits.service.d/90-rb-restore-test.conf")
        dropin.parent.mkdir(parents=True, exist_ok=True)
        with dropin.open("x") as out:
            out.write("[Service]\nExecStartPre=/usr/bin/false\n")
        try:
            call("systemctl", "daemon-reload")
            must_reject(valid)
            if pg:
                result = call("sudo", "-u", "postgres", "psql", "-XAt", "-d", "postgres", "-c",
                              "SELECT count(*) FROM pg_database WHERE datname LIKE 'rb_previous_%' AND NOT datallowconn",
                              capture_output=True)
                assert int(result.stdout) > 0
            else:
                assert any(CONFIG.parents[2].glob(".lnbits-restore.*/previous/database.sqlite3"))
        finally:
            dropin.unlink()
            call("systemctl", "daemon-reload")
        call(UPDATER, "restore", str(valid), stdout=subprocess.DEVNULL)
        wait_wallet()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=["prepare", "wallet", "update", "previous", "keep-stopped",
                                         "retry", "failed-start", "stopped", "custom-unit", "interrupted", "postgres-restore", "sqlite-restore"])
    parser.add_argument("--from-commit", default=V170)
    args = parser.parse_args()
    if (os.getuid() != 0 or not DATA.is_dir() or DATA.is_symlink() or DATA.stat().st_uid != 0
            or DATA.stat().st_mode & 0o077
            or "LNBITS_BACKEND_WALLET_CLASS=VoidWallet" not in CONFIG.read_text().splitlines()):
        parser.error("Use a dedicated VM with VoidWallet and a root-owned mode-0700 " + str(DATA))
    os.umask(0o077)
    if not __debug__:
        parser.error("Run with Python assertions enabled")
    if args.case in ("update", "previous", "keep-stopped", "retry", "failed-start"):
        menu_update(args.case, TARGET if args.case == "previous" else args.from_commit)
    elif args.case == "stopped":
        stopped_update(args.from_commit)
    elif args.case.endswith("-restore"):
        restore(args.case.split("-")[0])
    else:
        {"prepare": prepare, "wallet": wallet_check, "custom-unit": custom_unit, "interrupted": interrupted_trial}[args.case]()
    print("PASS", args.case)
