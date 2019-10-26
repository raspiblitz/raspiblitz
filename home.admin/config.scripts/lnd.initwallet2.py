#!/usr/bin/python
import os
import sys
import binascii
import grpc
from lndlibs import rpc_pb2 as ln
from lndlibs import rpc_pb2_grpc as lnrpc
from pathlib2 import Path

print("This is the legacy - Python2 only - version.")
if sys.version_info > (3, 0):
    print("Can't run on Python3")
    sys.exit()

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# ! always activate virtual env first: source /home/admin/python-env-lnd/bin/activate")
    print("# ! and run with with: python /home/admin/config.scripts/lnd.initwallet.py")
    print("# creating or recovering the LND wallet")
    print("# lnd.initwallet.py new [walletpassword] [?seedpassword]")
    print("# lnd.initwallet.py seed [walletpassword] [\"seeds-words-seperated-spaces\"] [?seedpassword]")
    print("# lnd.initwallet.py scb [walletpassword] [\"seeds-words-seperated-spaces\"] [filepathSCB] [?seedpassword]")
    print("err='missing parameters'")
    sys.exit(1)

mode = sys.argv[1]


def new(stub, wallet_password="", seed_entropy=None):
    if seed_entropy:
        # provide 16-bytes of static data to get reproducible seeds for TESTING!)
        print("WARNING: Use this for testing only!!")
        request = ln.GenSeedRequest(seed_entropy=seed_entropy)
    else:
        request = ln.GenSeedRequest()

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
        print >> sys.stderr, code
        details = rpc_error_call.details()
        print("err='RPCError GenSeedRequest'")
        print("errMore='" + details + "'")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='GenSeedRequest'")
        sys.exit(1)

    request = ln.InitWalletRequest(
        wallet_password=wallet_password,
        cipher_seed_mnemonic=seed_words
    )
    try:
        response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print >> sys.stderr, code
        details = rpc_error_call.details()
        print("err='RPCError InitWallet'")
        print("errMore='" + details + "'")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='InitWallet'")
        sys.exit(1)


def seed(stub, wallet_password="", seed_words="", seed_password=""):
    request = ln.InitWalletRequest(
        wallet_password=wallet_password,
        cipher_seed_mnemonic=seed_words,
        recovery_window=250,
        aezeed_passphrase=seed_password
    )

    try:
        response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print >> sys.stderr, code
        details = rpc_error_call.details()
        print("err='RPCError InitWallet'")
        print("errMore='" + details + "'")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='InitWallet'")
        sys.exit(1)


def scb(stub, wallet_password="", seed_words="", seed_password="", file_path_scb=""):
    with open(file_path_scb, 'rb') as f:
        content = f.read()
    scb_hex_str = binascii.hexlify(content)
    print(scb_hex_str)

    request = ln.InitWalletRequest(
        wallet_password=wallet_password,
        cipher_seed_mnemonic=seed_words,
        recovery_window=250,
        aezeed_passphrase=seed_password,
        channel_backups=scb_hex_str
    )

    try:
        response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print >> sys.stderr, code
        details = rpc_error_call.details()
        print("err='RPCError InitWallet'")
        print("errMore='" + details + "'")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='InitWallet'")
        sys.exit(1)

    print("err='TODO: implement creating from seed/scb'")
    sys.exit(1)


def parse_args():
    wallet_password = ""
    seed_words = ""
    seed_password = ""
    filepath_scb = ""

    if mode == "new":

        print("# *** CREATING NEW LND WALLET ***")

        if len(sys.argv) > 2:
            wallet_password = sys.argv[2]
            if len(wallet_password) < 8:
                print("err='wallet password is too short'")
                sys.exit(1)
        else:
            print("err='wallet password is too short'")
            sys.exit(1)

        if len(sys.argv) > 3:
            seed_password = sys.argv[3]

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

    return wallet_password, seed_words, seed_password, filepath_scb


def main():
    wallet_password, seed_words, seed_password, file_path_scb = parse_args()

    os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
    cert = open('/mnt/hdd/lnd/tls.cert', 'rb').read()
    ssl_creds = grpc.ssl_channel_credentials(cert)
    channel = grpc.secure_channel('localhost:10009', ssl_creds)
    stub = lnrpc.WalletUnlockerStub(channel)

    if mode == "new":
        new(stub, wallet_password)

    elif mode == "seed":
        seed(stub, wallet_password, seed_words, seed_password)

    elif mode == "scb":
        scb(stub, wallet_password, seed_words, seed_password, file_path_scb)


if __name__ == '__main__':
    main()
