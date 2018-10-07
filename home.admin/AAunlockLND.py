#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import base64
import os
import signal
import subprocess
import sys
from optparse import OptionParser

try:  # make sure that (unsupported) Python2 can fail gracefully
    import configparser
except ImportError:
    pass

if sys.version_info < (3, 5, 0):
    print("Python2 not supported! Please run with Python3.5+")
    sys.exit(1)


def sigint_handler(signum, frame):
    print('CTRL+C pressed - exiting!')
    sys.exit(0)


def _read_pwd(password_file):
    # read and convert password from file
    p = subprocess.run("sudo cat {}".format(password_file),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=False, shell=True, timeout=None)
    if not p.returncode == 0:
        print("unable to read password from: {}".format(password_file))
        sys.exit(1)
    passwd_bytes = p.stdout.split(b"\n")[0]
    passwd_b64 = base64.encodebytes(passwd_bytes).decode('utf-8').split("\n")[0]
    return passwd_b64


def _read_macaroon(lnd_macaroon_file):
    # read and convert macaroon from file
    p = subprocess.run("sudo xxd -ps -u -c 1000 {}".format(lnd_macaroon_file),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True, shell=True, timeout=None)
    macaroon_hex_dump = p.stdout.split("\n")[0]
    return macaroon_hex_dump


def check_locked(password_file, lnd_cert_file, lnd_macaroon_file, host="localhost", port="8080", verbose=False):
    # check locked
    if verbose:
        print("Checking for lock")

    passwd_b64 = _read_pwd(password_file)
    macaroon_hex_dump = _read_macaroon(lnd_macaroon_file)

    cmds = ["curl", "-s",
            "-H", "'Grpc-Metadata-macaroon: {}'".format(macaroon_hex_dump),
            "--cacert", "{}".format(lnd_cert_file),
            "-d", "{{\"wallet_password\": \"{}\"}}".format(passwd_b64),
            "https://{}:{}/v1/getinfo".format(host, port)]

    p = subprocess.run(cmds,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True, shell=False, timeout=None)
    if not p.returncode == 0:
        print("\033[91mSomething went wrong!\033[00m \033[93mIs lnd running? Wrong credentials?\033[00m")
        # print("Returncode: {}".format(p.returncode))
        # print("Stderr: {}".format(p.stderr))
        sys.exit(1)

    if p.stdout == "Not Found\n":
        return True
    else:
        return False


def unlock(password_file, lnd_cert_file, lnd_macaroon_file, host="localhost", port="8080", verbose=False):
    if verbose:
        print("Trying to unlock")

    passwd_b64 = _read_pwd(password_file)
    macaroon_hex_dump = _read_macaroon(lnd_macaroon_file)

    # unlock lnd by calling curl
    cmds = ["curl", "-s",
            "-H", "'Grpc-Metadata-macaroon: {}'".format(macaroon_hex_dump),
            "--cacert", "{}".format(lnd_cert_file),
            "-d", "{{\"wallet_password\": \"{}\"}}".format(passwd_b64),
            "https://{}:{}/v1/unlockwallet".format(host, port)]

    p = subprocess.run(cmds,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True, shell=False, timeout=None)
    if p.returncode == 0:
        return True
    else:
        if verbose:
            print("\033[91mSomething went wrong!\033[00m \033[93mIs lnd running? Wrong credentials?\033[00m")
            # print("Returncode: {}".format(p.returncode))
            # print("Stderr: {}".format(p.stderr))
        return False


def main():
    signal.signal(signal.SIGINT, sigint_handler)

    usage = "usage: %prog [Options]"
    parser = OptionParser(usage=usage, version="%prog {}".format("0.1"))

    parser.add_option("-v", "--verbose", dest="verbose", action="store_true",
                      help="Print more output")

    parser.add_option("-H", dest="host", type="string", default="localhost",
                      help="Host (default: localhost)")
    parser.add_option("-P", dest="port", type="string", default="8080",
                      help="Port (default: 8080)")

    parser.add_option("-p", dest="password_file", type="string", default="pwd",
                      help="File containing *cleartext* password (default: pwd)")
    parser.add_option("-c", dest="cert", type="string",
                      help="TLS certificate file (e.g. ~/.lnd/tls.cert)"),
    parser.add_option("-m", dest="macaroon", type="string",
                      help="Macaroon file (e.g. readonly.macaroon)")
    options, args = parser.parse_args()

    password_file = os.path.abspath(options.password_file)
    if not os.path.exists(password_file):
        print("Password file does not exist - exiting: {}".format(password_file))
        sys.exit(1)

    if options.cert:
        lnd_cert_file = options.cert
    else:
        lnd_cert_file = "/home/bitcoin/.lnd/tls.cert"

    if options.macaroon:
        lnd_macaroon_file = options.macaroon
    else:
        lnd_macaroon_file = "/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon"

    if options.verbose:
        print("Password File: \033[93m{}\033[00m".format(password_file))
        print("TLS CERT File: \033[93m{}\033[00m".format(lnd_cert_file))
        print("Macaroon File: \033[93m{}\033[00m".format(lnd_macaroon_file))
        print("URL: \033[93mhttps://{}:{}\033[00m".format(options.host, options.port))

    if check_locked(password_file, lnd_cert_file, lnd_macaroon_file,
                    host=options.host, port=options.port, verbose=options.verbose):
        if options.verbose:
            print("\033[93m{}\033[00m".format("Locked"))
    else:
        print("\033[92m{}\033[00m".format("Not Locked"))
        sys.exit(1)

    if unlock(password_file, lnd_cert_file, lnd_macaroon_file,
              host=options.host, port=options.port, verbose=options.verbose):
        print("\033[92m{}\033[00m".format("Successfully unlocked."))
    else:
        print("\033[91m{}\033[00m".format("Failed to unlock."))


if __name__ == "__main__":
    main()
