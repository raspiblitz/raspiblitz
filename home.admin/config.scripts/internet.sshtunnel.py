#!/usr/bin/python3

import sys, subprocess
from pathlib import Path

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("forward ports from another server to raspiblitz with reverse SSH tunnel")
    print("internet.sshtunnel.py [on|off] [USER]@[SERVER] [INTERNAL-PORT]:[EXTERNAL-PORT]")
    print("note that [INTERNAL-PORT]:[EXTERNAL-PORT] can one or multiple forwardings")
    sys.exit(1)

#
# CONSTANTS
#

SERVICENAME="autossh-tunnel.service"
SERVICEFILE="/etc/systemd/system/"+SERVICENAME
SERVICETEMPLATE="""# see config script internet.sshtunnel.py
[Unit]
Description=AutoSSH tunnel service
After=network.target

[Service]
User=root
Group=root
Environment="AUTOSSH_GATETIME=0"
ExecStart=/usr/bin/autossh -M 0 -N -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" [PLACEHOLDER]
StandardOutput=journal

[Install]
WantedBy=multi-user.target
"""

#
# SWITCHING ON
#

if sys.argv[1] == "on":

    # check if already running
    #already_running = subprocess.check_output("systemctl is-enabled %s" % (SERVICENAME) ,shell=True, universal_newlines=True)
    #if str(already_running).count("enabled") > 0:
    #    print("already ON - run 'internet.sshtunnel.py off' first")
    #    sys.exit(1)

    # check server address
    ssh_server = sys.argv[2]
    if ssh_server.count("@") != 1:
        print("[USER]@[SERVER] wrong - use 'internet.sshtunnel.py -h' for help")
        sys.exit(1)

    # check minimal forwardings
    if len(sys.argv) < 4:
        print("[INTERNAL-PORT]:[EXTERNAL-PORT] missing - run 'internet.sshtunnel.py off' first")
        sys.exit(1)

    # genenate additional parameter for autossh (forwarding ports)
    additional_parameters=""
    i = 3
    while i < len(sys.argv):

        # check forwarding format
        if sys.argv[i].count(":") != 1:
            print("[INTERNAL-PORT]:[EXTERNAL-PORT] wrong format '%s'" % (sys.argv[i]))
            sys.exit(1)

        # get ports
        ports = sys.argv[i].split(":")
        port_internal = ports[0]
        port_external = ports[1]
        if port_internal.isdigit() == False:
            print("[INTERNAL-PORT]:[EXTERNAL-PORT] internal not number '%s'" % (sys.argv[i]))
            sys.exit(1)
        if port_external.isdigit() == False:
            print("[INTERNAL-PORT]:[EXTERNAL-PORT] external not number '%s'" % (sys.argv[i]))
            sys.exit(1) 

        additional_parameters= additional_parameters + "-R %s:localhost:%s " % (port_external,port_internal)
        i=i+1

    # genenate additional parameter for autossh (server)
    additional_parameters= additional_parameters + ssh_server

    # generate custom service config
    service_data = SERVICETEMPLATE.replace("[PLACEHOLDER]", additional_parameters)

    # DEBUG exit
    print("****** SERVICE ******")
    print(service_data)
    sys.exit(0)

    # write service file
    service_file = open(SERVICEFILE, "w")
    service_file.write(service_data)
    service_file.close()

    # enable service
    print("*** Enabling systemd service: SERVICENAME")
    subprocess.call("systemctl daemon-reload", shell=True)
    #subprocess.call(f"systemctl enable {SERVICENAME}", shell=True)
    print()

    # final info (can be ignored if run by other script)
    print("*** OK - SSH TUNNEL SERVICE STARTED ***")
    #print("- Make sure the SSH pub key of this RaspiBlitz is in 'authorized_keys' of {} ")
    print("- Tunnel service needs final reboot to start.")
    #print("- After reboot check logs: sudo journalctl -f -u {SERVICENAME}")

#
# SWITCHING OFF
#

elif sys.argv[1] == "off":

    # check if already disabled
    #alreadyRunning = subprocess.check_output(f"systemctl is-enabled {SERVICENAME}" ,shell=True, universal_newlines=True)
    #if str(alreadyRunning).count("enabled") == 0:
    #    print("Was already OFF")
    #    sys.exit(0)

    print ("TODO: Switch OFF")

#
# UNKOWN PARAMETER
#

else:
    print ("unkown parameter - use 'internet.sshtunnel.py -h' for help")