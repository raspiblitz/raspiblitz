#!/usr/bin/env python3
import os
import re
import stat
import sys
import time
from pathlib import Path

import grpc

if sys.version_info < (3, 0):
    print("Can't run on Python2")
    sys.exit()

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] in ["-h", "--help", "help"]:
    print("# creating or recovering the LND wallet")
    print("# lnd.initwallet.py new [mainnet|testnet|signet] [walletpassword] [--stage-seed]")
    print("# lnd.initwallet.py seed [mainnet|testnet|signet] [walletpassword] [\"seeds-words-seperated-spaces\"] [?seedpassword]")
    print("# lnd.initwallet.py unlock [mainnet|testnet|signet] [walletpassword] [recovery_window]")
    print("# lnd.initwallet.py scb [mainnet|testnet|signet] [filepathSCB] [macaroonPath]")
    print("# lnd.initwallet.py change-password [mainnet|testnet|signet] [walletpassword-old] [walletpassword-new]")
    print("err='missing parameters'")
    sys.exit(1)

mode = sys.argv[1]

if mode == "scb":
    import codecs
    from lndlibs import lightning_pb2 as lnrpc
    from lndlibs import lightning_pb2_grpc as lightningstub
    
else:
    from lndlibs import walletunlocker_pb2 as lnrpc
    from lndlibs import walletunlocker_pb2_grpc as rpcstub
    

def stage_recovery(path, record):
    # O_EXCL also refuses a previous, uncertain initialization attempt.
    path.parent.mkdir(mode=0o700, exist_ok=True)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(directory)
        if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise PermissionError("unsafe recovery directory")
        parent = os.open("..", os.O_RDONLY | os.O_DIRECTORY, dir_fd=directory)
        try:
            os.fsync(parent)
        finally:
            os.close(parent)
        fd = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=directory)
        created = os.fstat(fd)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(record)
                stream.flush()
                os.fsync(stream.fileno())
            os.fsync(directory)
        except OSError:
            # No InitWallet RPC has run. Remove only this attempt's inode.
            current = os.stat(path.name, dir_fd=directory, follow_symlinks=False)
            if os.path.samestat(created, current):
                os.unlink(path.name, dir_fd=directory)
                os.fsync(directory)
            raise
    finally:
        os.close(directory)


def new(stub, wallet_password="", seed_entropy=None, recovery_path=None):
    if seed_entropy:
        # provide 16-bytes of static data to get reproducible seeds for TESTING!)
        print("WARNING: Use this for testing only")
        request = lnrpc.GenSeedRequest(seed_entropy=seed_entropy)
    else:
        request = lnrpc.GenSeedRequest()

    try:
        response = stub.GenSeed(request)
        seed_words = response.cipher_seed_mnemonic
        if len(seed_words) != 24 or not all(re.fullmatch("[a-z]+", word) for word in seed_words):
            sys.exit(wallet_error("invalid mnemonic returned by LND"))
        seed_words_str = ', '.join(seed_words)

        # add a 6x4 formatted version to the output
        seed_words_6x4 = ""
        for i in range(0, len(seed_words)):
            if i % 6 == 0 and i != 0:
                seed_words_6x4 = seed_words_6x4 + "\n"
            single_word = str(i + 1) + ":" + seed_words[i]
            while len(single_word) < 12:
                single_word = single_word + " "
            seed_words_6x4 = seed_words_6x4 + single_word
        record = f"seedwords='{seed_words_str}'\nseedwords6x4='{seed_words_6x4}'\n"

    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print(code, file=sys.stderr)
        details = rpc_error_call.details()
        print("err='RPCError GenSeedRequest'")
        print("errMore=\"" + details + "\"")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print(e, file=sys.stderr)
        print("err='GenSeedRequest'")
        sys.exit(1)

    if recovery_path is None:
        print(record, end="", flush=True)
    else:
        try:
            stage_recovery(recovery_path, record)
        except OSError:
            sys.exit(wallet_error("cannot stage recovery words; check the data drive and any pending seed file"))

    request = lnrpc.InitWalletRequest(
        wallet_password=wallet_password.encode(),
        cipher_seed_mnemonic=seed_words
    )
    try:
        response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print(code, file=sys.stderr)
        details = rpc_error_call.details()
        print("err='RPCError InitWallet'")
        print("errMore=\"" + details + "\"")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print(e, file=sys.stderr)
        print("err='InitWallet'")
        sys.exit(1)
    if recovery_path is not None:
        print(record, end="")

# init wallet with recovery_window=0 (to not trigger rescan)
# but make sure to put lnd into recovery mode with lnd.backup.sh
#  script after that
def seed(stub, wallet_password="", seed_words="", seed_password=""):
    request = lnrpc.InitWalletRequest(
        wallet_password=wallet_password.encode(),
        cipher_seed_mnemonic=[x.encode() for x in seed_words],
        recovery_window=0,
        aezeed_passphrase=seed_password.encode()
    )

    try:
        response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print(code, file=sys.stderr)
        details = rpc_error_call.details()
        print("err='RPCError InitWallet'")
        print("errMore=\"" + details + "\"")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print(e, file=sys.stderr)
        print("err='InitWallet'")
        sys.exit(1)

def unlock(stub, wallet_password="", scan_depth=int):
    request = lnrpc.UnlockWalletRequest(
        wallet_password=wallet_password.encode(),
        recovery_window=scan_depth,
    )

    try:
        response = stub.UnlockWallet(request)
        print("# ok - wallet unlocked - using recovery window:", scan_depth)

    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print(code, file=sys.stderr)
        details = rpc_error_call.details()
        print("err='RPCError UnlockWallet'")
        print("errMore=\"" + details + "\"")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print(e, file=sys.stderr)
        print("err='UnlockWallet'")
        sys.exit(1)


def scb(stub, file_path_scb="", macaroon_path=""):
    macaroon_file = Path(macaroon_path)
    print(macaroon_file)
    macaroon = codecs.encode(open(macaroon_file, 'rb').read(), 'hex')
    with open(file_path_scb, 'rb') as f:
        content = f.read()
        request = lnrpc.RestoreChanBackupRequest(
        multi_chan_backup=content
    )

    try:
        response = stub.RestoreChannelBackups(request, metadata=[('macaroon', macaroon)])
        print(response)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print(code, file=sys.stderr)
        details = rpc_error_call.details()
        print("err='RPCError RestoreChanBackupRequest'")
        print("errMore=\"" + details + "\"")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print(e, file=sys.stderr)
        print("err='RestoreChanBackupRequest'")
        sys.exit(1)


def change_password(stub, wallet_password="", wallet_password_new=""):
    request = lnrpc.ChangePasswordRequest(
        current_password=wallet_password.encode(),
        new_password=wallet_password_new.encode()
    )

    try:
        response = stub.ChangePassword(request)
        print("# ok - password changed")
        #print(response.admin_macaroon)

    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print(code, file=sys.stderr)
        details = rpc_error_call.details()
        print("err='RPCError ChangePassword'")
        print("errMore=\"" + details + "\"")
        print("# make sure wallet is locked when trying to change password'", file=sys.stderr)
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print(e, file=sys.stderr)
        print("err='ChangePassword'")
        sys.exit(1)


def parse_args():
    network = ""
    wallet_password = ""
    wallet_password_new = ""
    seed_words = ""
    seed_password = ""
    filepath_scb = ""
    macaroon_path = ""
    scan_depth = int

    if len(sys.argv) > 2:
        network = sys.argv[2]
    else:
        print("err='missing parameters'")
        sys.exit(1)

    if mode == "new":
        if len(sys.argv) > 3:
            wallet_password = sys.argv[3]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
        else:
            print("err='missing parameters'")
            sys.exit(1)

        if len(sys.argv) > 4 and sys.argv[4] != "--stage-seed":
            seed_password = sys.argv[4]

    elif mode == "change-password":

        if len(sys.argv) > 4:
            wallet_password = sys.argv[3]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
            wallet_password_new = sys.argv[4]
            if len(wallet_password_new ) < 8:
                print("err='wallet password new is too short'")
                sys.exit(1)
        else:
            print("err='missing parameters'")
            sys.exit(1)

    elif mode == "seed":

        if len(sys.argv) > 3:
            wallet_password = sys.argv[3]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter - missing wallet password'")
            sys.exit(1)

        if len(sys.argv) > 4:
            seed_word_str = sys.argv[4]
            seed_words = seed_word_str.split(" ")
            if len(seed_words) < 24:
                print("err='not 24 seed words separated by just spaces (surrounded with \")'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter  - missing seed string'")
            sys.exit(1)

        if len(sys.argv) > 5:
                seed_password = sys.argv[5]


    elif mode == "unlock":

        if len(sys.argv) > 3:
            wallet_password = sys.argv[3]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter - missing wallet password'")
            sys.exit(1)
        if len(sys.argv) > 4:
            scan_depth = int(sys.argv[4])
            if type(scan_depth) is not int:
                print("err='expecting a number for recovery_window'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter - missing recovery_window'")
            sys.exit(1)

    elif mode == "scb":

        if len(sys.argv) > 3:
            filepath_scb = sys.argv[3]
            scb_file = Path(filepath_scb)
            if scb_file.is_file():
                print("# OK the SCB file exists")
            else:
                print("err='the given filepathSCB - file does not exist or no permission'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter  - missing filepathSCB'")
            sys.exit(1)
        
        if len(sys.argv) > 4:
            macaroon_path = sys.argv[4]
            macaroon_file = Path(macaroon_path)
            if macaroon_file.is_file():
                print("# OK the admin.macaroon exists")
            else:
                print("err='the given macaroonPath - file does not exist or no permission'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter  - missing macaroonPath'")
            sys.exit(1)

    else:

        print("err='unknown mode parameter - run without any parameters to see options'")
        sys.exit(1)

    return network, wallet_password, seed_words, seed_password, filepath_scb, macaroon_path, wallet_password_new, scan_depth


def main():

    network, wallet_password, seed_words, seed_password, file_path_scb, macaroon_path, wallet_password_new, scan_depth = parse_args()

    grpcEndpoint="localhost:0"
    if network == "mainnet":
        grpcEndpoint="localhost:10009"
    elif network == "testnet":
        grpcEndpoint="localhost:11009"
    elif network == "signet":
        grpcEndpoint="localhost:13009"
    else:
        print("err='chain not supported'")
        sys.exit(1)

    os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
    cert_path = Path('/mnt/hdd/app-data/lnd/tls.cert')
    deadline = time.monotonic() + 60
    last_cert = None
    channel = None
    while True:
        cert = None
        try:
            cert = cert_path.read_bytes()
        except FileNotFoundError:
            pass  # On first start LND creates its certificate asynchronously.
        except OSError:
            sys.exit(wallet_error("cannot read the LND TLS certificate"))
        if cert and cert != last_cert:
            if channel is not None:
                channel.close()
            channel = grpc.secure_channel(grpcEndpoint, grpc.ssl_channel_credentials(cert))
            last_cert = cert
            if mode != "new":
                break
            ready = grpc.channel_ready_future(channel)
        remaining = deadline - time.monotonic()
        if not cert:
            if mode != "new" or remaining <= 0:
                sys.exit(wallet_error("LND TLS certificate is not ready"))
            time.sleep(min(1, remaining))
            continue
        try:
            ready.result(timeout=min(2, max(0, remaining)))
            break
        except grpc.FutureTimeoutError:
            if time.monotonic() >= deadline:
                channel.close()
                sys.exit(wallet_error("LND wallet RPC is not ready"))
    if mode == "scb":
        stub = lightningstub.LightningStub(channel)
    else:
        stub = rpcstub.WalletUnlockerStub(channel)

    if mode == "new":
        print("# *** CREATING NEW LND WALLET ***")
        recovery_path = None
        if "--stage-seed" in sys.argv[4:]:
            # app-data may be a symlink to the data disk. Keep secrets outside
            # the LND tree, whose ownership and permissions are reset on install.
            disk_root = cert_path.parent.parent.resolve().parent
            recovery_path = disk_root / ".raspiblitz-lnd-recovery" / f"{network}.pending"
        new(stub, wallet_password, recovery_path=recovery_path)

    elif mode == "seed":
        print("# *** RECOVERING LND WALLET FROM SEED ***")
        seed(stub, wallet_password, seed_words, seed_password)

    elif mode == "unlock":
        print("# *** UNLOCK WALLET WITH PASSWORD_C ***")
        unlock(stub, wallet_password, scan_depth)

    elif mode == "scb":
        print("# *** RECOVERING LND CHANNEL FUNDS FROM SCB ***")
        scb(stub, file_path_scb, macaroon_path)

    elif mode == "change-password":
        print("# *** SETTING NEW PASSWORD FOR WALLET ***")
        change_password(stub, wallet_password, wallet_password_new)


def wallet_error(message):
    print("err='" + message + "'")
    print(message, file=sys.stderr)
    return 1


if __name__ == '__main__':
    main()
