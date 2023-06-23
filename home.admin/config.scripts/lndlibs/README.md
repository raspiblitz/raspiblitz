For every new LND version the LND RPC libs need to be compiled from the matching protobuff files.
Do this on a raspberrypi with the exact same python version the scripts will be are running on.
See https://dev.lightning.community/guides/python-grpc/


To generate the lnd RPC libs - login as admin and run:
```
cd
sudo python3 -m pip install grpcio grpcio-tools googleapis-common-protos pathlib2
rm -rf googleapis 
git clone https://github.com/googleapis/googleapis.git
rm -rf protobuffs
mkdir protobuffs
curl -o ./walletunlocker.proto -s https://raw.githubusercontent.com/lightningnetwork/lnd/master/lnrpc/walletunlocker.proto
curl -o ./lightning.proto -s https://raw.githubusercontent.com/lightningnetwork/lnd/master/lnrpc/lightning.proto
python3 -m grpc_tools.protoc --proto_path=googleapis:. --python_out=./protobuffs --grpc_python_out=./protobuffs ./walletunlocker.proto ./lightning.proto
cp ./*.proto ./protobuffs
````

*NOTE: If LND master branch is already a version ahead .. use the rpc.proto from the version tagged branch.*

Now copy the generated RPC libs per SFTP over to your Laptop and add them to the `/home/admin/config.scripts/lndlibs`.

scp -r admin@192.168.X.X:/home/admin/protobuffs ./protobuffs

Make sure the first lines (ignore comments) of the `lightning_pb2_grpc.py` look like the following for python3 compatibility:
```
from __future__ import absolute_import
import grpc

from . import lightning_pb2 as lightning__pb2
```

Make sure the first lines (ignore comments) of the `walletunlocker_pb2_grpc.py` look like the following for python3 compatibility:
```
from __future__ import absolute_import
import grpc

from . import walletunlocker_pb2 as walletunlocker__pb2
```

Make sure the first lines (ignore comments) of the `walletunlocker_pb2.py` look like the following for python3 compatibility:
```
from google.protobuf.internal import builder as _builder
from google.protobuf import descriptor as _descriptor
from google.protobuf import descriptor_pool as _descriptor_pool
from google.protobuf import message as _message
from google.protobuf import reflection as _reflection
from google.protobuf import symbol_database as _symbol_database
# @@protoc_insertion_point(imports)

_sym_db = _symbol_database.Default()


from . import lightning_pb2 as lightning__pb2
```


