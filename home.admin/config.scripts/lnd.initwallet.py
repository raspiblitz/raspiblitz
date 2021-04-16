#!/usr/bin/env python3
import binascii
import os
import sys
from pathlib import Path

import grpc
from lndlibs import walletunlocker_pb2 as lnrpc
from lndlibs import walletunlocker_pb2_grpc as rpcstub

if sys.version_info < (3, 0):
    print("Can't run on Python2")
    sys.exit()

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] in ["-h", "--help", "help"]:
    print("# creating or recovering the LND wallet")
    print("# lnd.initwallet.py new [walletpassword] [?seedpassword]")
    print("# lnd.initwallet.py seed [walletpassword] [\"seeds-words-seperated-spaces\"] [?seedpassword]")
    print("# lnd.initwallet.py scb [walletpassword] [\"seeds-words-seperated-spaces\"] [filepathSCB] [?seedpassword]")
    print("# lnd.initwallet.py change-password [walletpassword-old] [walletpassword-new]")
    print("err='missing parameters'")
    sys.exit(1)

mode = sys.argv[1]

def new(stub, wallet_password="", seed_entropy=None):
    if seed_entropy:
        # provide 16-bytes of static data to get reproducible seeds for TESTING!)
        print("WARNING: Use this for testing only!!")
        request = lnrpc.GenSeedRequest(seed_entropy=seed_entropy)
    else:
        request = lnrpc.GenSeedRequest()

    try:
        response = stub.GenSeed(request)
        seed_words = response.cipher_seed_mnemonic
        seed_words_str = ', '.join(seed_words)
        print("seedwords='" + seed_words_str + "'")

        # add a 6x4 formatted version to the output
        seed_words_6x4 = ""
        for i in range(0, len(seed_words)):
            if i % 6 == 0 and i != 0:
                seed_words_6x4 = seed_words_6x4 + "\n"
            single_word = str(i + 1) + ":" + seed_words[i]
            while len(single_word) < 12:
                single_word = single_word + " "
            seed_words_6x4 = seed_words_6x4 + single_word
        print("seedwords6x4='" + seed_words_6x4 + "'")

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


def seed(stub, wallet_password="", seed_words="", seed_password=""):
    request = lnrpc.InitWalletRequest(
        wallet_password=wallet_password.encode(),
        cipher_seed_mnemonic=[x.encode() for x in seed_words],
        recovery_window=5000,
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


def scb(stub, wallet_password="", seed_words="", seed_password="", file_path_scb=""):
    with open(file_path_scb, 'rb') as f:
        content = f.read()
    scb_hex_str = binascii.hexlify(content)
    print(scb_hex_str)

    request = lnrpc.InitWalletRequest(
        wallet_password=wallet_password.encode(),
        cipher_seed_mnemonic=[x.encode() for x in seed_words],
        recovery_window=5000,
        aezeed_passphrase=seed_password.encode(),
        channel_backups=scb_hex_str.encode()
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

    # TODO(rootzoll) implement creating from seed/scb
    print("err='TODO: implement creating from seed/scb'")
    sys.exit(1)

def change_password(stub, wallet_password="", wallet_password_new=""):

    request = lnrpc.ChangePasswordRequest(
        current_password=wallet_password.encode(),
        new_password=wallet_password_new.encode()
    )

    try:
        response = stub.ChangePassword(request)
        print("ok")
        print(response.admin_macaroon)

    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print(code, file=sys.stderr)
        details = rpc_error_call.details()
        print("err='RPCError ChangePassword'")
        print("errMore=\"" + details + "\"")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print(e, file=sys.stderr)
        print("err='ChangePassword'")
        sys.exit(1)

def parse_args():
    wallet_password = ""
    wallet_password_new = ""
    seed_words = ""
    seed_password = ""
    filepath_scb = ""

    if mode == "new":
        if len(sys.argv) > 2:
            wallet_password = sys.argv[2]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
        else:
            print("err='missing parameters'")
            sys.exit(1)

        if len(sys.argv) > 3:
            seed_password = sys.argv[3]

    elif mode == "change-password":

        if len(sys.argv) > 3:
            wallet_password = sys.argv[2]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
            wallet_password_new = sys.argv[3]
            if len(wallet_password_new ) < 8:
                print("err='wallet password new is too short'")
                sys.exit(1)
        else:
            print("err='missing parameters'")
            sys.exit(1)

    elif mode == "seed" or mode == "scb":

        if len(sys.argv) > 2:
            wallet_password = sys.argv[2]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter - missing wallet password'")
            sys.exit(1)

        if len(sys.argv) > 3:
            seed_word_str = sys.argv[3]
            seed_words = seed_word_str.split(" ")
            if len(seed_words) < 24:
                print("err='not 24 seed words separated by just spaces (surrounded with \")'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter  - missing seed string'")
            sys.exit(1)

        if mode == "seed":

            if len(sys.argv) > 4:
                seed_password = sys.argv[4]

        elif mode == "scb":

            if len(sys.argv) > 4:
                filepath_scb = sys.argv[4]
                scb_file = Path(filepath_scb)
                if scb_file.is_file():
                    print("# OK SCB file exists")
                else:
                    print("err='the given filepathSCB - file does not exists or no permission'")
                    sys.exit(1)
            else:
                print("err='not correct amount of parameter  - missing seed filepathSCB'")
                sys.exit(1)

            if len(sys.argv) > 5:
                seed_password = sys.argv[4]

    else:

        print("err='unknown mode parameter - run without any parameters to see options'")
        sys.exit(1)

    return wallet_password, seed_words, seed_password, filepath_scb, wallet_password_new 


def main():
    os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
    cert = open('/mnt/hdd/lnd/tls.cert', 'rb').read()
    ssl_creds = grpc.ssl_channel_credentials(cert)
    channel = grpc.secure_channel('localhost:10009', ssl_creds)
    stub = rpcstub.WalletUnlockerStub(channel)

    wallet_password, seed_words, seed_password, file_path_scb, wallet_password_new = parse_args()

    if mode == "new":
        print("# *** CREATING NEW LND WALLET ***")
        new(stub, wallet_password)

    elif mode == "seed":
        print("# *** RECOVERING LND WALLET FROM SEED ***")
        seed(stub, wallet_password, seed_words, seed_password)

    elif mode == "scb":
        print("# *** RECOVERING LND WALLET FROM SEED + SCB ***")
        scb(stub, wallet_password, seed_words, seed_password, file_path_scb)

    elif mode == "change-password":
        print("# *** SETTING NEW PASSWORD FOR WALLET ***")
        change_password(stub, wallet_password, wallet_password_new)


if __name__ == '__main__':
    main()
