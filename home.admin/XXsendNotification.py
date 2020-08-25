#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
import os
import subprocess
from email.message import EmailMessage

try:
    import smime
except ImportError:
    raise ImportError("Please install missing package: python3 -m pip install smime")

SSMTP_BIN = "/usr/sbin/ssmtp"


def main():
    parser = argparse.ArgumentParser(description="Send a notification")
    parser.add_argument("-V", "--version", action="version",
                        help="print version", version="0.1")

    parser.add_argument("-d", "--debug", action="store_true",
                        help="print debug output")

    subparsers = parser.add_subparsers(dest='subparser')

    # ext
    parser_ext = subparsers.add_parser("ext", help="Notify by external command")
    parser_ext.add_argument("cmd", type=str,
                            help="Path to external command")

    parser_ext.add_argument("message", type=str,
                            help="Message to send")

    # e-Mail
    parser_mail = subparsers.add_parser("mail", help="Notify by e-Mail")

    parser_mail.add_argument("recipient", type=str,
                             help="E-Mail address of recipient")

    parser_mail.add_argument("message", type=str,
                             help="Message to send")

    parser_mail.add_argument("-s", "--subject", type=str, default="RB Notification",
                             help="Subject for message")

    parser_mail.add_argument("-c", "--cert", type=str, default="pub.pem",
                             help="Path to public x509 certificate of recipient")

    parser_mail.add_argument("-e", "--encrypt", action="store_true",
                             help="S/MIME encrypt body")

    parser_mail.add_argument("--from-name", type=str, default="From-Name",
                             help="Sender name")

    parser_mail.add_argument("--from-address", type=str, default="from-address@example.com",
                             help="Sender e-Mail address")

    # slack
    parser_slack = subparsers.add_parser("slack", help="Notify by Slack")
    parser_slack.add_argument("message", type=str,
                              help="Message to send")

    # parse args and run selected subparser
    kwargs = vars(parser.parse_args())
    try:
        globals()[kwargs.pop('subparser')](**kwargs)
    except KeyError:
        parser.print_help()


def ext(cmd=None, message=None, debug=False):
    if debug:
        print("calling: {}".format(cmd))
        print("with msg: {}".format(message))

    if not os.path.exists(cmd):
        raise Exception("File not found: {}".format(cmd))

    try:
        subprocess.run([cmd, message], stderr=subprocess.STDOUT)

    except subprocess.CalledProcessError as err:
        print("Running shell command \"{}\" caused "
              "error: {} (RC: {}".format(err.cmd, err.output, err.returncode))
        raise Exception(err)


# e-Mail
def mail(recipient: str = None, message: str = None, subject: str = None, cert: str = None,
         encrypt: bool = False, from_name: str = None, from_address: str = None, debug: bool = False):
    if debug:
        print("send mail")
        print("msg: {}".format(message))
        print("to: {}".format(recipient))
        print("from: {} <{}>".format(from_name, from_address))
        print("subject: {}".format(subject))
        print("cert: {}".format(cert))
        print("encrypt: {}".format(encrypt))

    if encrypt:
        if not os.path.exists(cert):
            raise Exception("File not found: {}".format(cert))

        msg_content = [
            "To: {}".format(recipient),
            'From: {} <{}>'.format(from_name, from_address),
            "Subject: {}".format(subject),
            "",
            "{}".format(message)
        ]

        with open(cert, 'rb') as pem:
            msg = smime.encrypt('\n'.join(msg_content), pem.read())

        msg_to_send = msg.encode()

    else:
        msg = EmailMessage()

        msg['Subject'] = "{}".format(subject)
        msg['From'] = '{} <{}>'.format(from_name, from_address),
        msg['To'] = recipient

        msg.set_payload(message)
        msg_to_send = msg.as_bytes()

    # send message via e-Mail
    if not os.path.exists(SSMTP_BIN):
        raise Exception("File not found: {}".format(SSMTP_BIN))

    try:
        cmd = [SSMTP_BIN, recipient]
        subprocess.run(cmd, input=msg_to_send, stderr=subprocess.STDOUT)

    except subprocess.CalledProcessError as err:
        print("Running shell command \"{}\" caused "
              "error: {} (RC: {}".format(err.cmd, err.output, err.returncode))
        raise Exception(err)


def slack(message: str = None, debug: bool = False):
    if debug:
        print("send slack")
        print("msg: {}".format(message))
    raise NotImplementedError()


if __name__ == "__main__":
    main()
