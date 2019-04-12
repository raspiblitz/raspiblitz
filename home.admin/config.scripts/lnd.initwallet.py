#!/usr/bin/python
import codecs, grpc, os, sys, base64
import rpc_pb2 as ln, rpc_pb2_grpc as lnrpc

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# creating or recovering the LND wallet")
    print("# lnd.winitwallet.py new [walletpassword] [?seedpassword]")
    print("# lnd.winitwallet.py seed [walletpassword] [seedstring] [?seedpassword]")
    print("# lnd.winitwallet.py scb [walletpassword] [seedstring] [filepathSCB] [?seedpassword]")
    print("err='missing parameters'")
    sys.exit(1)

walletpassword=""
seedwords=""
seedpassword=""
filepathSCB=""

mode=sys.argv[1]

if mode=="new":

    print("# *** CREATING NEW LND WALLET ***")

    if len(sys.argv)>2:
        walletpassword=sys.argv[2]
        if len(walletpassword)<8:
            print("err='wallet password is too short'")
            sys.exit(1)
    else:
        print("err='wallet password is too short'")
        sys.exit(1)

    if len(sys.argv)>3:
        seedpassword=sys.argv[3]

elif mode=="seed":

        print("err='TODO: implement creating from seed'")
        sys.exit(1)

elif mode=="scb":

        print("err='TODO: implement creating from seed/scb'")
        sys.exit(1)

else:

    print("err='unkown mode parameter - run without any parameters to see options'")
    sys.exit(1)

os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
cert = open('/mnt/hdd/lnd/tls.cert', 'rb').read()
ssl_creds = grpc.ssl_channel_credentials(cert)
channel = grpc.secure_channel('localhost:10009', ssl_creds)
stub = lnrpc.WalletUnlockerStub(channel)

if mode=="new":

    #request=False
    #if len(seedpassword)>0:
    #    request = ln.InitWalletRequest(wallet_password=base64.b64encode(walletpassword.decode(),aezeed_passphrase=base64.b64encode(seedpassword).decode())
    #else:
    request = ln.InitWalletRequest(wallet_password=walletpassword)
    response = stub.InitWallet(request)
    print(response)

elif mode=="seed":

    print("err='TODO: implement creating from seed'")
    sys.exit(1)

elif mode=="scb":

    print("err='TODO: implement creating from seed/scb'")
    sys.exit(1)

