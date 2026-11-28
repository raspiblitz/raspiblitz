#!/usr/bin/env python3
"""Preserve the legacy JoinMarket state and prepare its local Core RPC wallet."""

import configparser
import fcntl
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path


DATA = Path("/mnt/hdd/app-data")
CORE_CONF = DATA / "bitcoin/bitcoin.conf"
JM_CONF = DATA / ".joinmarket/joinmarket.cfg"
LEGACY_WALLET = "wallet.dat"
DESCRIPTOR_WALLET = "watch-only-descriptor-wallet"
USER_SCRIPT = Path(__file__).resolve()
ASSETS = USER_SCRIPT.parent.parent / "assets"
SYSTEMD = Path("/etc/systemd/system")
RPC_PORTS = {"mainnet": 8332, "testnet": 18332, "signet": 38332, "regtest": 18443}


def modern_core(version=None):
    if version is None:
        result = subprocess.run(
            ["/usr/local/bin/bitcoind", "--version"], capture_output=True, text=True, check=True
        )
        match = re.search(r"^Bitcoin Core(?: daemon)? version v([0-9]+)\.", result.stdout)
    else:
        match = re.fullmatch(r"v?([0-9]+)\.[0-9]+(?:\.[0-9]+)?(?:rc[0-9]+)?", version)
    return bool(match and int(match[1]) >= 30)


def local_blockchain():
    """Read the settings for an existing JoinMarket installation on this node."""
    config = configparser.ConfigParser(interpolation=None, inline_comment_prefixes=("#", ";"))
    try:
        with regular_file(JM_CONF) as stream:
            config.read_string(stream.read().decode("utf-8"))
    except FileNotFoundError:
        return None
    if not config.has_section("BLOCKCHAIN"):
        raise ValueError("JoinMarket config has no BLOCKCHAIN section")
    chain = config["BLOCKCHAIN"]
    if chain.get("rpc_host", "localhost") not in ("127.0.0.1", "localhost", "::1"):
        return None
    if chain.get("blockchain_source", "bitcoin-rpc") not in ("bitcoin-rpc", "bitcoin-rpc-no-history"):
        return None
    return chain


def local_wallet():
    settings = local_blockchain()
    return settings.get("rpc_wallet_file", "") if settings is not None else None


@contextmanager
def migration_lock():
    descriptor = os.open("/run/raspiblitz-joinmarket-wallet.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "r+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


@contextmanager
def backup_directory():
    # app-data belongs to bitcoin. Pin the root-owned backup directories so a
    # replacement or symlink cannot redirect a privileged wallet copy.
    parent = os.open(DATA, os.O_RDONLY | os.O_DIRECTORY)
    descriptors = [parent]
    try:
        for name, mode in (("backup", 0o755), ("joinmarket", 0o700)):
            created = False
            try:
                os.mkdir(name, 0o700, dir_fd=parent)
                created = True
            except FileExistsError:
                pass
            directory = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            descriptors.append(directory)
            info = os.fstat(directory)
            if info.st_uid != 0 or info.st_mode & 0o022:
                raise PermissionError("JoinMarket backup parent must be root-owned and protected")
            if created:
                os.fchmod(directory, mode)
                os.fsync(directory)
                os.fsync(parent)
            parent = directory
        if os.fstat(parent).st_mode & 0o077:
            raise PermissionError("JoinMarket backup directory must have mode 0700")
        yield Path(f"/proc/self/fd/{parent}")
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


@contextmanager
def open_wallet_path(path):
    """Open a path under app-data without following application-owned links."""
    components = path.relative_to(DATA).parts
    parent = os.open(DATA, os.O_RDONLY | os.O_DIRECTORY)
    descriptors = [parent]
    try:
        for component in components[:-1]:
            parent = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            descriptors.append(parent)
        descriptor = os.open(components[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        descriptors.append(descriptor)
        yield descriptor
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


@contextmanager
def regular_file(path):
    with open_wallet_path(path) as descriptor:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError(f"Expected a regular wallet file: {path}")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            yield stream


def wallet_files(path, optional=True):
    try:
        with open_wallet_path(path) as descriptor:
            mode = os.fstat(descriptor).st_mode
            entries = sorted(os.listdir(descriptor)) if stat.S_ISDIR(mode) else []
    except FileNotFoundError:
        if optional:
            return
        raise
    if stat.S_ISREG(mode):
        yield path
    elif stat.S_ISDIR(mode):
        for entry in entries:
            if entry.startswith(".") and entry.endswith(".lock"):
                raise ValueError("Close open JoinMarket wallets before backing up")
            yield from wallet_files(path / entry, optional=False)
    else:
        raise ValueError(f"Unsupported file in wallet backup: {path}")


def copy_wallet_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with regular_file(source) as reader:
        with destination.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
            writer.flush()
            os.fsync(writer.fileno())


def matches_backup(source, backup):
    with regular_file(source) as original, backup.open("rb") as copy:
        while True:
            data = original.read(64 * 1024)
            if data != copy.read(64 * 1024):
                return False
            if not data:
                return True


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def backup_legacy_wallet(core_wallet_loaded=False, core_already_started=False):
    sources = [
        CORE_CONF,
        JM_CONF,
        *wallet_files(JM_CONF.parent / "wallets"),
        *wallet_files(CORE_CONF.parent / "wallets" / LEGACY_WALLET),
        *wallet_files(CORE_CONF.parent / LEGACY_WALLET),
    ]
    files = {source.relative_to(DATA): source for source in sources}
    with backup_directory() as destination:
        for previous in sorted(destination.glob("20*T*Z-*"), reverse=True):
            if previous.is_symlink() or not previous.is_dir():
                continue
            previous_files = {entry.relative_to(previous) for entry in previous.rglob("*") if entry.is_file()}
            # Pre-start commands compare the complete snapshot. After Core's
            # precheck, keep that original Core config for rollback.
            if previous_files == files.keys() and all(
                matches_backup(source, previous / relative)
                for relative, source in files.items()
                if source != CORE_CONF or not core_already_started
            ):
                report_backup(previous.name)
                return
        if core_wallet_loaded:
            raise ValueError("Stop Bitcoin Core and back up wallet.dat before migrating the loaded wallet")
        with tempfile.TemporaryDirectory(prefix=".incomplete-", dir=destination) as temporary:
            staging = Path(temporary)
            for relative, source in files.items():
                copy_wallet_file(source, staging / relative)
            if not all(matches_backup(source, staging / relative) for relative, source in files.items()):
                raise ValueError("Could not verify the JoinMarket wallet backup")
            for directory, _, _ in os.walk(staging, topdown=False):
                sync_directory(directory)
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            name = stamp + "-" + staging.name[len(".incomplete-"):]
            staging.rename(destination / name)
            sync_directory(destination)
        report_backup(name)


def report_backup(name):
    print(f"# JoinMarket wallet backup: {DATA / 'backup/joinmarket' / name}", flush=True)


def backup(version, stop_services=False):
    if not modern_core(version) or local_wallet() not in ("", LEGACY_WALLET):
        return
    stopped = []
    try:
        if stop_services:
            for service in ("joinmarket-api.service", "bitcoind.service", "tbitcoind.service", "sbitcoind.service"):
                if subprocess.run(["systemctl", "is-active", "--quiet", service], check=False).returncode == 0:
                    subprocess.run(["systemctl", "stop", service], check=True)
                    stopped.append(service)
        with migration_lock():
            if local_wallet() in ("", LEGACY_WALLET):
                backup_legacy_wallet()
    except Exception:
        for service in reversed(stopped):
            subprocess.run(["systemctl", "start", service], check=False)
        raise


def rpc(*arguments):
    settings = local_blockchain()
    if settings is None:
        raise ValueError("JoinMarket is no longer configured for this node")
    connection = [f"-rpcconnect={settings.get('rpc_host', 'localhost')}"]
    port = settings.get("rpc_port") or RPC_PORTS.get(settings.get("network", "mainnet"))
    if not port:
        raise ValueError("JoinMarket RPC port is missing")
    connection.append(f"-rpcport={int(port)}")
    username = settings.get("rpc_user", "")
    password = settings.get("rpc_password")
    if settings.get("rpc_cookie_file"):
        cookie = subprocess.run(
            ["runuser", "-u", "joinmarket", "--", "cat", "--", settings["rpc_cookie_file"]],
            capture_output=True, text=True, timeout=5, check=False,
        )
        if cookie.returncode or ":" not in cookie.stdout:
            raise ValueError("Could not read the JoinMarket RPC cookie")
        username, password = cookie.stdout.strip().split(":", maxsplit=1)
    if password:
        connection.extend([f"-rpcuser={username}", "-stdinrpcpass"])
    result = subprocess.run(
        [
            "runuser", "-u", "bitcoin", "--", "/usr/local/bin/bitcoin-cli",
            f"-conf={CORE_CONF}", "-datadir=/mnt/hdd/app-storage/bitcoin", *connection, *arguments,
        ],
        input=f"{password}\n" if password else None,
        capture_output=True, text=True, timeout=75, check=False,
    )
    if result.returncode:
        raise ValueError("Bitcoin Core RPC failed while preparing the JoinMarket wallet")
    return json.loads(result.stdout)


def prepare():
    with migration_lock():
        wallet = local_wallet()
        if wallet not in ("", LEGACY_WALLET, DESCRIPTOR_WALLET) or not modern_core():
            return
        if rpc("-rpcwait", "-rpcwaittimeout=60", "getnetworkinfo")["version"] < 300000:
            raise ValueError("The running Bitcoin Core is older than the installed binary")
        loaded = rpc("listwallets")
        if wallet != DESCRIPTOR_WALLET:
            backup_legacy_wallet(core_wallet_loaded=LEGACY_WALLET in loaded, core_already_started=True)
        if DESCRIPTOR_WALLET not in loaded:
            names = {entry["name"] for entry in rpc("listwalletdir")["wallets"]}
            if DESCRIPTOR_WALLET in names:
                rpc("loadwallet", DESCRIPTOR_WALLET, "true")
            else:
                rpc("-named", "createwallet", f"wallet_name={DESCRIPTOR_WALLET}", "disable_private_keys=true",
                    "load_on_startup=true")
        info = rpc(f"-rpcwallet={DESCRIPTOR_WALLET}", "getwalletinfo")
        if info["descriptors"] is not True or info["private_keys_enabled"] is not False:
            raise ValueError("The JoinMarket RPC wallet must be a watch-only descriptor wallet")
        if wallet != DESCRIPTOR_WALLET:
            subprocess.run(["runuser", "-u", "joinmarket", "--", sys.executable, str(USER_SCRIPT), "select"], check=True)
            print("# Open each existing JoinMarket wallet, then use WALLET > RESCAN to recover its history.")


def select_descriptor():
    if local_wallet() not in ("", LEGACY_WALLET):
        raise ValueError("JoinMarket RPC wallet selection changed during migration")
    original = JM_CONF.read_text()
    section = re.search(r"(?im)^[ \t]*\[BLOCKCHAIN\][^\n]*\n[^\x00]*?(?=^[ \t]*\[|\Z)", original)
    if not section:
        raise ValueError("Cannot locate the JoinMarket BLOCKCHAIN settings")
    settings, count = re.subn(
        r"(?im)^[ \t]*rpc_wallet_file[ \t]*[:=].*$",
        f"rpc_wallet_file = {DESCRIPTOR_WALLET}", section[0],
    )
    if count == 0:
        header, _, rest = settings.partition("\n")
        settings = f"{header}\nrpc_wallet_file = {DESCRIPTOR_WALLET}\n{rest}"
    with tempfile.NamedTemporaryFile(mode="w", dir=JM_CONF.parent, delete=False) as output:
        path = Path(output.name)
        try:
            output.write(original[:section.start()] + settings + original[section.end():])
            output.flush()
            os.fsync(output.fileno())
            path.replace(JM_CONF)
            sync_directory(JM_CONF.parent)
        finally:
            path.unlink(missing_ok=True)


def install_service():
    if local_wallet() is None or not modern_core():
        return
    service = SYSTEMD / "joinmarket-wallet.service"
    shutil.copyfile(ASSETS / service.name, service)
    service.chmod(0o644)
    jam_service = SYSTEMD / "joinmarket-api.service"
    if jam_service.is_file():
        drop_in = SYSTEMD / "joinmarket-api.service.d/20-wallet-prepare.conf"
        drop_in.parent.mkdir(exist_ok=True)
        shutil.copyfile(ASSETS / "joinmarket-wallet-jam.conf", drop_in)
        drop_in.chmod(0o644)
    subprocess.run(["systemctl", "enable", "joinmarket-wallet.service"], check=True)
    subprocess.run(["systemctl", "daemon-reload"], check=True)


def main():
    action, *args = sys.argv[1:]
    if action == "modern":
        return 0 if modern_core() else 1
    if action == "select":
        if os.geteuid() == 0:
            raise ValueError("Select the RPC wallet as the JoinMarket service user")
        select_descriptor()
        return 0
    if os.geteuid() != 0:
        raise ValueError("Run the JoinMarket wallet migration as root")
    os.umask(0o077)
    if action == "backup":
        backup(None)
    elif action == "backup-update":
        backup(args[0], stop_services=True)
    elif action == "prepare":
        prepare()
    elif action == "install-service":
        install_service()
    else:
        raise ValueError("Unknown JoinMarket wallet action")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except configparser.Error:
        sys.exit("# JoinMarket wallet migration failed: invalid JoinMarket configuration")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"# JoinMarket wallet migration failed: {error}")
