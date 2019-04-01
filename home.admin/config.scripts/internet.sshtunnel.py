#!/usr/bin/python3

import sys, subprocess

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("forward ports from another server to raspiblitz with reverse SSH tunnel")
    print("internet.sshtunnel.py [on|off] [USER]@[SERVER] [INTERNAL-PORT]:[EXTERNAL-PORT]")
    print("note that [INTERNAL-PORT]:[EXTERNAL-PORT] can one or multiple forwardings")
    sys.exit(1)

#
# SWITCHING ON
#

if sys.argv[1] == "on":

    # check if already running -> systemctl is-enabled autossh-tunnel.service
    alreadyRunning = subprocess.check_output(['systemctl','is-enabled','autossh-tunnel.service'],shell=True)
    if alreadyRunning == "enabled":
        print("already running - run 'internet.sshtunnel.py off' first")
        sys.exit(1)

    print ("TODO: Switch ON")

#
# SWITCHING OFF
#

elif sys.argv[1] == "off":

    print ("TODO: Switch OFF")

#
# UNKOWN PARAMETER
#

else:
    print ("unkown parameter - use 'internet.sshtunnel.py -h' for help")