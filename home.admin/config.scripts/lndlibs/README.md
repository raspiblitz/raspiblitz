For every new LND version the LND RPC libs need to be compiled from the matching protobuff files.
Do this on a raspberrypi with the exact same python version the scripts will be are running on.
See https://dev.lightning.community/guides/python-grpc/

Make sure Virtual Environment is setup: 
```
sudo apt-get -f -y install virtualenv
virtualenv lnd
source lnd/bin/activate
pip install grpcio grpcio-tools googleapis-common-protos
```

Normally that is already done by build_sdcard.sh for user admin user. So just run:
```
source lnd/bin/activate
````

Now to generate the lnd RPC libs:
```
git clone https://github.com/googleapis/googleapis.git
curl -o rpc.proto -s https://raw.githubusercontent.com/lightningnetwork/lnd/master/lnrpc/rpc.proto
python -m grpc_tools.protoc --proto_path=googleapis:. --python_out=. --grpc_python_out=. rpc.proto
````

*NOTE: If LND master branch is already a version ahead .. use the rpc.proto from the version tagged branch.*

Now copy the generated RPC libs per SCP over to your Laptop and add them to the `/home/admin/config.scripts/lndlibs`.

