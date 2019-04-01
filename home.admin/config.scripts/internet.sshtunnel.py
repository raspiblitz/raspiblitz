#!/usr/bin/python3

import sys

if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "-help":
    print("forward ports from another server to raspiblitz with reverse SSH tunnel")
    print("internet.sshtunnel.py [on|off] [USER]@[SERVER] [INTERNAL-PORT]:[EXTERNAL-PORT]")
    print("note that [INTERNAL-PORT]:[EXTERNAL-PORT] can one or multiple forwardings")
    sys.exit(1)

print ("TODO: implement")