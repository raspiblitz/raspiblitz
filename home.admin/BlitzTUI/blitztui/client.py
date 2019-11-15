# -*- coding: utf-8 -*-

import base64
import codecs
import logging
import os
import sys
from os.path import isfile

import grpc

log = logging.getLogger(__name__)

IS_WIN32_ENV = sys.platform == "win32"

if IS_WIN32_ENV:
    cur_path = os.path.abspath(os.path.curdir)
    config_script1 = os.path.join(cur_path, "home.admin", "config.scripts")
    config_script2 = os.path.abspath(os.path.join(cur_path, "..", "..", "home.admin", "config.scripts"))
    sys.path.insert(1, config_script1)
    sys.path.insert(1, config_script2)
else:
    sys.path.insert(1, '/home/admin/config.scripts')

from lndlibs import rpc_pb2 as ln
try:
    from lndlibs import rpc_pb2_grpc as lnrpc
except ModuleNotFoundError as err:
    log.error("ModuleNotFoundError - most likely an issue with incompatible Python3 import.\n"
              "Please run the following two lines to fix this: \n"
              "\n"
              "sed -i -E '1 a from __future__ import absolute_import' "
              "/home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py\n"
              "sed -i -E 's/^(import.*_pb2)/from . \\1/' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py")
    sys.exit(1)

if not IS_WIN32_ENV:
    import psutil

MACAROON_LIST = ["admin", "readonly", "invoice"]


class AdminStub(lnrpc.LightningStub):
    def __init__(self, network="bitcoin", chain="main"):
        self.channel = get_rpc_channel(macaroon_path=build_macaroon_path("admin", network=network, chain=chain))
        super().__init__(self.channel)


class ReadOnlyStub(lnrpc.LightningStub):
    def __init__(self, network="bitcoin", chain="main"):
        self.channel = get_rpc_channel(macaroon_path=build_macaroon_path("readonly", network=network, chain=chain))
        super().__init__(self.channel)


class InvoiceStub(lnrpc.LightningStub):
    def __init__(self, network="bitcoin", chain="main"):
        self.channel = get_rpc_channel(macaroon_path=build_macaroon_path("invoice", network=network, chain=chain))
        super().__init__(self.channel)


def convert_r_hash(r_hash):
    """ convert_r_hash

    >>> convert_r_hash("+eMo9YTaZIjkJacclb6LYUocwa0q7cgVOBPf/0aclYQ=")
    'f9e328f584da6488e425a71c95be8b614a1cc1ad2aedc8153813dfff469c9584'

    """
    r_hash_bytes = codecs.decode(r_hash.encode(), 'base64')
    r_hash_hex_bytes = codecs.encode(r_hash_bytes, 'hex')
    return r_hash_hex_bytes.decode()


def convert_r_hash_hex(r_hash_hex):
    """ convert_r_hash_hex

    >>> convert_r_hash_hex("f9e328f584da6488e425a71c95be8b614a1cc1ad2aedc8153813dfff469c9584")
    '+eMo9YTaZIjkJacclb6LYUocwa0q7cgVOBPf/0aclYQ='

    """
    r_hash = codecs.decode(r_hash_hex, 'hex')
    r_hash_b64_bytes = base64.b64encode(r_hash)
    return r_hash_b64_bytes.decode()


def convert_r_hash_hex_bytes(r_hash_hex_bytes):
    """ convert_r_hash_hex_bytes

    >>> convert_r_hash_hex_bytes(b'\xf9\xe3(\xf5\x84\xdad\x88\xe4%\xa7\x1c\x95\xbe\x8baJ\x1c\xc1\xad*\xed\xc8\x158\x13\xdf\xffF\x9c\x95\x84')
    'f9e328f584da6488e425a71c95be8b614a1cc1ad2aedc8153813dfff469c9584'

    """
    r_hash_hex_bytes = codecs.encode(r_hash_hex_bytes, 'hex')
    return r_hash_hex_bytes.decode()


def get_rpc_channel(host="localhost", port="10009", cert_path=None, macaroon_path=None):
    if not macaroon_path:
        raise Exception("need to specify a macaroon path!")

    def metadata_callback(context, callback):
        # for more info see grpc docs
        callback([('macaroon', macaroon)], None)

    # Due to updated ECDSA generated tls.cert we need to let gprc know that
    # we need to use that cipher suite otherwise there will be a handshake
    # error when we communicate with the lnd rpc server.
    os.environ["GRPC_SSL_CIPHER_SUITES"] = 'HIGH+ECDSA'

    if not cert_path:
        cert_path = os.path.expanduser('~/.lnd/tls.cert')

    assert isfile(cert_path) and os.access(cert_path, os.R_OK), \
        "File {} doesn't exist or isn't readable".format(cert_path)
    cert = open(cert_path, 'rb').read()

    with open(macaroon_path, 'rb') as f:
        macaroon_bytes = f.read()
        macaroon = codecs.encode(macaroon_bytes, 'hex')

    # build ssl credentials using the cert the same as before
    cert_creds = grpc.ssl_channel_credentials(cert)

    # now build meta data credentials
    auth_creds = grpc.metadata_call_credentials(metadata_callback)

    # combine the cert credentials and the macaroon auth credentials
    # such that every call is properly encrypted and authenticated
    combined_creds = grpc.composite_channel_credentials(cert_creds, auth_creds)

    # finally pass in the combined credentials when creating a channel
    return grpc.secure_channel('{}:{}'.format(host, port), combined_creds)


def build_macaroon_path(name=None, network="bitcoin", chain="main"):
    if not name.lower() in MACAROON_LIST:
        raise Exception("name must be one of: {}".format(", ".join(MACAROON_LIST)))

    macaroon_path = os.path.expanduser('~/.lnd/data/chain/{}/{}net/{}.macaroon'.format(network, chain, name.lower()))
    assert isfile(macaroon_path) and os.access(macaroon_path, os.R_OK), \
        "File {} doesn't exist or isn't readable".format(macaroon_path)

    return macaroon_path


def check_lnd(stub, proc_name="lnd", rpc_listen_ports=None):
    if not rpc_listen_ports:
        rpc_listen_ports = [10009]

    pid_ok = False
    listen_ok = False
    unlocked = False
    synced_to_chain = False
    synced_to_graph = False

    if IS_WIN32_ENV:
        return pid_ok, listen_ok, unlocked, synced_to_chain, synced_to_graph

    if not [p.info for p in psutil.process_iter(attrs=['pid', 'name']) if proc_name in p.info['name']]:
        return pid_ok, listen_ok, unlocked, synced_to_chain, synced_to_graph
    else:
        pid_ok = True

    if not [net_con for net_con in psutil.net_connections(kind='inet')
            if (net_con.status == psutil.CONN_LISTEN and net_con.laddr[1] in rpc_listen_ports)]:
        return pid_ok, listen_ok, unlocked, synced_to_chain, synced_to_graph
    else:
        listen_ok = True

    try:
        get_info = stub.GetInfo(ln.GetInfoRequest())
        unlocked = True
        synced_to_chain = get_info.synced_to_chain
        synced_to_graph = get_info.synced_to_graph

    except grpc.RpcError as err:
        if err._state.__dict__['code'] == grpc.StatusCode.UNIMPLEMENTED:
            log.debug("wallet is 'locked'")
        else:
            log.warning("an unknown RpcError occurred")
            log.warning(err)

    except Exception as err:
        log.warning("an error occurred: {}".format(err))

    return pid_ok, listen_ok, unlocked, synced_to_chain, synced_to_graph


def check_lnd_channels(stub):
    """let's assume that check_lnd() was called just before calling this"""
    total_active_channels = 0
    total_remote_balance_sat = 0

    try:
        request = ln.ListChannelsRequest(
            active_only=True,
            inactive_only=False,
            public_only=False,
            private_only=False,
        )
        response = stub.ListChannels(request)

        total_active_channels = len(response.channels)
        for channel in response.channels:
            # log.debug(channel)
            total_remote_balance_sat += channel.remote_balance

    except grpc.RpcError as err:
        if err._state.__dict__['code'] == grpc.StatusCode.UNIMPLEMENTED:
            log.debug("wallet is 'locked'")
        else:
            log.warning("an unknown RpcError occurred")
            log.warning(err)

    except Exception as err:
        log.warning("an error occurred: {}".format(err))

    return total_active_channels, total_remote_balance_sat


def check_invoice_paid(stub, invoice_r_hash, num_max_invoices=3):
    # ToDo error handling
    request = ln.ListInvoiceRequest(num_max_invoices=num_max_invoices, reversed=True)
    response = stub.ListInvoices(request)

    for invoice in response.invoices:
        hex_str = convert_r_hash_hex_bytes(invoice.r_hash)

        if hex_str == invoice_r_hash:
            if invoice.settled:
                log.debug("found - and settled: {}".format(invoice))
                amt_paid_sat = invoice.amt_paid_sat
                return True, amt_paid_sat
            else:
                log.debug("found - but NOT settled.")
                return False, None
    else:
        log.warning("invoice NOT found")
        return False, None


def create_invoice(stub, memo="", value=0):
    # ToDo error handling
    request = ln.Invoice(memo=memo, value=value)
    response = stub.AddInvoice(request)
    return response


def get_node_uri(stub):
    # ToDo error handling
    response = stub.GetInfo(ln.GetInfoRequest())
    if response.uris:
        return response.uris[0]


def main():
    network = "bitcoin"
    chain = "main"

    stub_readonly = ReadOnlyStub(network=network, chain=chain)
    pid_ok, listen_ok, unlocked, synced_to_chain, synced_to_graph = check_lnd(stub_readonly)
    print(pid_ok, listen_ok, unlocked, synced_to_chain, synced_to_graph)

    if pid_ok and listen_ok and unlocked:
        node_uri = get_node_uri(stub_readonly)
        print("Node URI: {}".format(node_uri))

        num, sats = check_lnd_channels(stub_readonly)
        print("Total Channels: {}".format(num))
        print("Total Remote Capacity: {}".format(sats))


if __name__ == "__main__":
    main()
