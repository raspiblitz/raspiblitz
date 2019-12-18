For every new LND version the LND RPC libs need to be compiled from the matching protobuff files.
Do this on a raspberrypi with the exact same python version the scripts will be are running on.
See https://dev.lightning.community/guides/python-grpc/


To generate the lnd RPC libs:
```
cd
source /home/admin/python3-env-lnd/bin/activate
git clone https://github.com/googleapis/googleapis.git
curl -o rpc.proto -s https://raw.githubusercontent.com/lightningnetwork/lnd/master/lnrpc/rpc.proto
python -m grpc_tools.protoc --proto_path=googleapis:. --python_out=. --grpc_python_out=. rpc.proto
````

*NOTE: If LND master branch is already a version ahead .. use the rpc.proto from the version tagged branch.*

Now copy the generated RPC libs per SCP over to your Laptop and add them to the `/home/admin/config.scripts/lndlibs`.

