#!/usr/bin/python
import codecs, os, sys, base64

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# ! always activate virtual env first: source /home/admin/python-env-lnd/bin/activate")
    print("# ! and run with with: python /home/admin/config.scripts/lnd.initwallet.py")
    print("# creating or recovering the LND wallet")
    print("# lnd.winitwallet.py new [walletpassword] [?seedpassword]")
    print("# lnd.winitwallet.py seed [walletpassword] [\"seeds-words-seperated-spaces\"] [?seedpassword]")
    print("# lnd.winitwallet.py scb [walletpassword] [\"seeds-words-seperated-spaces\"] [filepathSCB] [?seedpassword]")
    print("err='missing parameters'")
    sys.exit(1)

import grpc
from lndlibs import rpc_pb2 as ln
from lndlibs import rpc_pb2_grpc as lnrpc
from pathlib2 import Path

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

elif mode=="seed" or mode=="scb":

    if len(sys.argv)>2:
        walletpassword=sys.argv[2]
        if len(walletpassword)<8:
            print("err='wallet password is too short'")
            sys.exit(1)
    else:
        print("err='not correct amount of parameter - missing wallet password'")
        sys.exit(1)

    if len(sys.argv)>3:
        seedwordString=sys.argv[3]
        seedwords=seedwordString.split(" ")
        if len(seedwords)<24:
            print("err='not 24 seed words seperated by just spaces (surrounded with \")'")
            sys.exit(1)
    else:
        print("err='not correct amount of parameter  - missing seed string'")
        sys.exit(1)

    if mode=="seed":

        if len(sys.argv)>4:
            seedpassword=sys.argv[4]

    elif mode=="scb":

        if len(sys.argv)>4:
            filepathSCB=sys.argv[4]
            scbFile = Path(filepathSCB)
            if scbFile.is_file():
                print("# OK SCB file exists")
            else:
                print("err='the given filepathSCB - file does not exists or no permission'")
                sys.exit(1)
        else:
            print("err='not correct amount of parameter  - missing seed filepathSCB'")
            sys.exit(1)

        if len(sys.argv)>5:
            seedpassword=sys.argv[4]

else:

    print("err='unkown mode parameter - run without any parameters to see options'")
    sys.exit(1)

os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
cert = open('/mnt/hdd/lnd/tls.cert', 'rb').read()
ssl_creds = grpc.ssl_channel_credentials(cert)
channel = grpc.secure_channel('localhost:10009', ssl_creds)
stub = lnrpc.WalletUnlockerStub(channel)
if mode=="new":

    request = ln.GenSeedRequest()
    try:
        response = stub.GenSeed(request)
        seedwords = response.cipher_seed_mnemonic
        seedwordsString=', '.join(seedwords)
        print("seedwords='"+seedwordsString+"'")

        # add a 6x4 formatted version to the output
        seedwords6x4=""
        for i in range(0,len(seedwords)):
            if i % 6 == 0 and i != 0:
                seedwords6x4=seedwords6x4+"\n"
            singleWord=str(i+1)+":"+seedwords[i]
            while len(singleWord)<12:
                singleWord=singleWord+" "
            seedwords6x4=seedwords6x4+singleWord
        print("seedwords6x4='"+seedwords6x4+"'")

    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print >> sys.stderr, code
        details = rpc_error_call.details()  
        print("err='RPCError GenSeedRequest'")
        print("errMore='"+details+"'")
        sys.exit(1)
    except: 
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='GenSeedRequest'")
        sys.exit(1)

    request = ln.InitWalletRequest(
        wallet_password=walletpassword,
        cipher_seed_mnemonic=seedwords
    )
    try:
      response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print >> sys.stderr, code
        details = rpc_error_call.details()  
        print("err='RPCError InitWallet'")
        print("errMore='"+details+"'")
        sys.exit(1)
    except: 
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='InitWallet'")
        sys.exit(1)

elif mode=="seed":

    request = ln.InitWalletRequest(
        wallet_password=walletpassword,
        cipher_seed_mnemonic=seedwords,
        recovery_window=5000,
        aezeed_passphrase=seedpassword
    )
    
    try:
        response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print >> sys.stderr, code
        details = rpc_error_call.details()  
        print("err='RPCError InitWallet'")
        print("errMore='"+details+"'")
        sys.exit(1)
    except: 
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='InitWallet'")
        sys.exit(1)

elif mode=="scb":

    import binascii
    with open(filepathSCB, 'rb') as f:
        content = f.read()
    scbHexString=binascii.hexlify(content)
    print(scbHexString)

    request = ln.InitWalletRequest(
        wallet_password=walletpassword,
        cipher_seed_mnemonic=seedwords,
        recovery_window=5000,
        aezeed_passphrase=seedpassword,
        channel_backups=scbHexString
    )

    try:
        response = stub.InitWallet(request)
    except grpc.RpcError as rpc_error_call:
        code = rpc_error_call.code()
        print >> sys.stderr, code
        details = rpc_error_call.details()  
        print("err='RPCError InitWallet'")
        print("errMore='"+details+"'")
        sys.exit(1)
    except:
        e = sys.exc_info()[0]
        print >> sys.stderr, e
        print("err='InitWallet'")
        sys.exit(1)

    print("err='TODO: implement creating from seed/scb'")
    sys.exit(1)