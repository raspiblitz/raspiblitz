#!/usr/bin/python
import requests
import logging
import logging.handlers
import subprocess
import argparse
import sys
from time import sleep

# get an instance of the logger object this module will use
logging.basicConfig(level=logging.DEBUG, format="%(asctime)-15s %(levelname)-8s %(message)s")


def get_price_at(timestamp="now"):
    requests_session = requests.Session()

    currency = "usd"
    if timestamp == "now":
        price = requests_session.get(
            "https://www.bitstamp.net/api/v2/ticker/btc{}".format(currency)
        ).json()["last"]
    else:
        price = requests_session.get(
            "https://www.bitstamp.net/api/v2/ohlc/btc{}/?limit=1&step=86400&start={}".format(
                currency, timestamp
            )
        ).json()["data"]["ohlc"][0]["close"]
    return price


def send_to_node(node, sats, message):
    sats = str(int(sats))
    logging.info("Sending {0} sats to {1}".format(sats, node))
    cmd = ['lncli', 'sendpayment', '--dest='+node, '--amt='+sats, "--keysend"]

    # Add keysend message, if available
    if message is not None:
        logging.warning("Keysend message not yet supported")
        # cmd.append("-n")
        # cmd.append(message)

    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode == 0:
        logging.info("Successfully sent {0} sats".format(sats))
        return True
    else:
        logging.info(p.stdout)
        logging.error(p.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Parse some args')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--sats', type=int, help="Sends AMOUNT sats")
    group.add_argument('--usd', type=float, help="Sends AMOUNT dollars (Fractions allowed)")
    parser.add_argument('--node_id', required=True, help="Node address to send to")
    parser.add_argument('--message', help="Optional, send a message to node")

    args = parser.parse_args()

    for send_attempt in range(0, 10):
        logging.info("Attempting to send.. attempt {0}/{1}".format(send_attempt+1, 10))
        try:
            # Calculate price in dollars
            if args.usd is not None:
                price = get_price_at()
                args.sats = args.usd * 100000000 / float(price)  # Convert to sats

            success = send_to_node(args.node_id, args.sats, args.message)
            if success:
                break

        except Exception as e:
            logging.error(e)
            logging.error("Failed to hit bitstamp api")

        sleep(60 * send_attempt+1)
