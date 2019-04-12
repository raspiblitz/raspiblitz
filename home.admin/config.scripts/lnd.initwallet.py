#!/usr/bin/python3
import codecs, grpc, os, sys
import rpc_pb2 as ln, rpc_pb2_grpc as lnrpc

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("creating or recovering the LND wallet")
    print("lnd.winitwallet.py new [walletpassword] [?seedpassword]")
    print("lnd.winitwallet.py seed [walletpassword] [seedstring] [?seedpassword]")
    print("lnd.winitwallet.py scb [walletpassword] [seedstring] [filepathSCB] [?seedpassword]")
    sys.exit(1)

walletpassword=""
seedwords=""
seedpassword=""
filepathSCB=""

mode=sys.argv[1]

if mode=="new":
    print("NEW")
elif mode=="seed":
    print("SEED")
elif mode=="scb":
    print("SCB")
else:
    print("unkown mode - run without parameter to see options")
    sys.exit(1)

print("TODO: Implement")
sys.exit(1)

os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
cert = open('/mnt/hdd/lnd/tls.cert', 'rb').read()
ssl_creds = grpc.ssl_channel_credentials(cert)
channel = grpc.secure_channel('localhost:10009', ssl_creds)
stub = lnrpc.WalletUnlockerStub(channel)
request = ln.InitWalletRequest(
        wallet_password=base64.b64encode(sys.argv[1]).decode(),
        cipher_seed_mnemonic=<array string>,
        aezeed_passphrase=<bytes>,
        recovery_window=<int32>,
        channel_backups=<ChanBackupSnapshot>,
    )
response = stub.InitWallet(request)
print(response)
