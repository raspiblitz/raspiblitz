#!/usr/bin/python3

import re
import subprocess
import sys

# IDEA: At the momemt its just Reverse-SSh Tunnels thats why [INTERNAL-PORT]<[EXTERNAL-PORT]
# For the future also just local ssh tunnels could be added with [INTERNAL-PORT]-[EXTERNAL-PORT]
# for the use case when a server wants to use a RaspiBlitz behind a NAT as Lightning backend

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("forward ports from another server to raspiblitz with reverse SSH tunnel")
    print("internet.sshtunnel.py on|off|restore USER@SERVER:PORT [--m:MONITORINGPORT] \"INTERNAL-PORT<EXTERNAL-PORT\"")
    print("note that INTERNAL-PORT<EXTERNAL-PORT can one or multiple forwardings")
    sys.exit(1)

#
# CONSTANTS
# sudo journalctl -f -u autossh-tunnel
#

SERVICE_NAME = "autossh-tunnel.service"
SERVICE_FILE = "/etc/systemd/system/" + SERVICE_NAME
SERVICE_TEMPLATE = """# see config script internet.sshtunnel.py
[Unit]
Description=AutoSSH tunnel service
After=network.target

[Service]
User=root
Group=root
Environment="AUTOSSH_GATETIME=0"
ExecStart=/usr/bin/autossh [MONITORING-PORT] -N -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=2 [PLACEHOLDER]
StandardOutput=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
"""

# get LND port form lnd.conf
LND_PORT = subprocess.getoutput("sudo cat /mnt/hdd/lnd/lnd.conf | grep '^listen=*' | cut -f2 -d':'")
if len(LND_PORT) == 0:
    LND_PORT = "9735"


#######################
# SWITCHING ON
#######################
def on(restore_on_update=False):
    forwarding_lnd = False

    # check if already running
    is_running = subprocess.getoutput("sudo systemctl --no-pager | grep -c '{}'".format(SERVICE_NAME))
    if int(is_running) > 0:
        print("SSH TUNNEL SERVICE IS RUNNING - run 'internet.sshtunnel.py off' first to set new tunnel")
        sys.exit(1)

    # check server address
    if len(sys.argv) < 3:
        print("[USER]@[SERVER:PORT] missing - use 'internet.sshtunnel.py -h' for help")
        sys.exit(1)
    if sys.argv[2].count("@") != 1:
        print("[USER]@[SERVER:PORT] wrong - use 'internet.sshtunnel.py -h' for help")
        sys.exit(1)
    ssh_server = sys.argv[2]
    if ssh_server.count(":") == 0:
        ssh_server_host = ssh_server
        ssh_server_port = "22"
    elif ssh_server.count(":") == 1:
        ssh_server_split = ssh_server.split(":")
        ssh_server_host = ssh_server_split[0]
        ssh_server_port = ssh_server_split[1]
    else:
        print("[USER]@[SERVER:PORT] wrong - use 'internet.sshtunnel.py -h' for help")
        sys.exit(1)

    # generate additional parameter for autossh (forwarding ports)
    if len(sys.argv) < 4:
        print("missing parameters")
        sys.exit(1)

    # check for optional monitoring port parameter
    i = 3
    monitoringPort="-M 0"
    optionalParameter=""
    if sys.argv[3].count("--m:") > 0:
         # get monitoring port number
         monitoringPort = sys.argv[3][4:]
         optionalParameter= "--m:{} ".format(monitoringPort)
         monitoringPort = "-M {}".format(monitoringPort)
         print("# found optional monitoring port: {}".format(monitoringPort))
         # port forwadings start one parameter later
         i = 4

    ssh_ports = ""
    additional_parameters = ""
    while i < len(sys.argv):

        # check forwarding format
        if sys.argv[i].count("<") != 1:
            print("[INTERNAL-PORT]<[EXTERNAL-PORT] wrong format '%s'" % (sys.argv[i]))
            sys.exit(1)

        # get ports
        sys.argv[i] = re.sub('"', '', sys.argv[i])
        ports = sys.argv[i].split("<")
        port_internal = ports[0]
        port_external = ports[1]
        if not port_internal.isdigit():
            print("[INTERNAL-PORT]<[EXTERNAL-PORT] internal not number '%s'" % (sys.argv[i]))
            sys.exit(1)
        if not port_external.isdigit():
            print("[INTERNAL-PORT]<[EXTERNAL-PORT] external not number '%s'" % (sys.argv[i]))
            sys.exit(1)
        if port_internal == LND_PORT:
            print("Detected LND Port Forwarding")
            forwarding_lnd = True
            if port_internal != port_external:
                print("FAIL: When tunneling your local LND port "
                      "'{}' it needs to be the same on the external server, but is '{}'".format(LND_PORT,
                                                                                                port_external))
                print(
                    "Try again by using the same port. If you cant change the external port, "
                    "change local LND port with: /home/admin/config.scripts/lnd.setport.sh")
                sys.exit(1)

        ssh_ports = ssh_ports + "\"%s\" " % (sys.argv[i])
        additional_parameters = additional_parameters + "-R %s:localhost:%s " % (port_external, port_internal)
        i = i + 1

    # generate additional parameter for autossh (server)
    ssh_ports = ssh_ports.strip()
    additional_parameters = additional_parameters + "-p " + ssh_server_port + " " + ssh_server_host

    # generate custom service config
    service_data = SERVICE_TEMPLATE.replace("[PLACEHOLDER]", additional_parameters)
    service_data = service_data.replace("[MONITORING-PORT]", monitoringPort)
    
    # debug print out service
    print()
    print("*** New systemd service: {}".format(SERVICE_NAME))
    print(service_data)

    # write service file
    service_file = open("/home/admin/temp.service", "w")
    service_file.write(service_data)
    service_file.close()
    subprocess.call("sudo mv /home/admin/temp.service {}".format(SERVICE_FILE), shell=True)

    # check if SSH keys for root user need to be created
    print()
    print("*** Checking root SSH pub keys")
    try:
        ssh_pubkey = subprocess.check_output("sudo cat /root/.ssh/id_rsa.pub", shell=True, universal_newlines=True)
        print("OK - root id_rsa.pub file exists")
    except subprocess.CalledProcessError:
        print("Generating root SSH keys ...")
        subprocess.call("sudo sh -c 'yes y | sudo -u root ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa  -q -N \"\"'",
                        shell=True)
        ssh_pubkey = subprocess.check_output("sudo cat /root/.ssh/id_rsa.pub", shell=True, universal_newlines=True)

    # copy SSH keys for backup (for update with new sd card)
    print("making backup copy of SSH keys")
    subprocess.call("sudo /home/admin/config.scripts/blitz.ssh.sh backup", shell=True)
    print("DONE")

    # write ssh tunnel data to raspiblitz config (for update with new sd card)
    print("*** Updating RaspiBlitz Config")
    with open('/mnt/hdd/raspiblitz.conf') as f:
        file_content = f.read()
    if file_content.count("sshtunnel=") == 0:
        file_content = file_content + "\nsshtunnel=''"
    file_content = re.sub("sshtunnel=.*", "sshtunnel='%s %s%s'" % (ssh_server, optionalParameter, ssh_ports), file_content)

    if not restore_on_update:
        server_domain = ssh_server.split("@")[1]

        ssh_server = server_domain
        if ssh_server.count(":") == 0:
            ssh_server_host = ssh_server
            ssh_server_port = "22"  # ToDo(frennkie) this is not used
        elif ssh_server.count(":") == 1:
            ssh_server_split = ssh_server.split(":")
            ssh_server_host = ssh_server_split[0]
            ssh_server_port = ssh_server_split[1]  # ToDo(frennkie) this is not used
        else:
            print("syntax error!")
            sys.exit(1)

        # make sure server_domain is set as tls alias
        print("Setting server as tls alias")
        old_config_hash = subprocess.getoutput("sudo shasum -a 256 /mnt/hdd/lnd/lnd.conf")
        subprocess.call("sudo sed -i \"s/^#tlsextradomain=.*/tlsextradomain=/g\" /mnt/hdd/lnd/lnd.conf", shell=True)
        subprocess.call(
            "sudo sed -i \"s/^tlsextradomain=.*/tlsextradomain={}/g\" /mnt/hdd/lnd/lnd.conf".format(ssh_server_host),
            shell=True)
        new_config_hash = subprocess.getoutput("sudo shasum -a 256 /mnt/hdd/lnd/lnd.conf")
        if old_config_hash != new_config_hash:
            print("lnd.conf changed ... generating new TLS cert")
            subprocess.call("sudo /home/admin/config.scripts/lnd.tlscert.sh refresh", shell=True)
        else:
            print("lnd.conf unchanged... keep TLS cert")

        if forwarding_lnd:
            # setting server explicitly on LND if LND port is forwarded
            print("Setting fixed address for LND with raspiblitz lndAddress")
            file_content = re.sub("lndAddress=.*", "lndAddress='{}'".format(ssh_server_host), file_content)
        else:
            print("No need to set fixed address for LND with raspiblitz lndAddress")
    file_content = "".join([s for s in file_content.splitlines(True) if s.strip("\r\n")]) + "\n"
    print(file_content)
    with open("/mnt/hdd/raspiblitz.conf", "w") as text_file:
        text_file.write(file_content)
    print("DONE")

    # make sure autossh is installed
    # https://www.everythingcli.org/ssh-tunnelling-for-fun-and-profit-autossh/
    print()
    print("*** Install autossh")
    subprocess.call("sudo apt-get install -y autossh", shell=True)

    # enable service
    print()
    print("*** Enabling systemd service: {}".format(SERVICE_NAME))
    subprocess.call("sudo systemctl daemon-reload", shell=True)
    subprocess.call("sudo systemctl enable {}".format(SERVICE_NAME), shell=True)

    # final info (can be ignored if run by other script)
    print()
    print("**************************************")
    print("*** WIN - SSH TUNNEL SERVICE SETUP ***")
    print("**************************************")
    print("See chapter 'How to setup port-forwarding with a SSH tunnel?' in:")
    print("https://github.com/rootzoll/raspiblitz/blob/dev/FAQ.md")
    print("- Tunnel service needs final reboot to start.")
    print("- After reboot check logs: sudo journalctl -f -u {}".format(SERVICE_NAME))
    print("- Make sure the SSH pub key of this RaspiBlitz is in 'authorized_keys' of {}:".format(ssh_server_host))
    print(ssh_pubkey)
    print()


#######################
# SWITCHING OFF
#######################
def off():
    print("*** Disabling systemd service: {}".format(SERVICE_NAME))
    subprocess.call("sudo systemctl stop {}".format(SERVICE_NAME), shell=True)
    subprocess.call("sudo systemctl disable {}".format(SERVICE_NAME), shell=True)
    subprocess.call("sudo systemctl reset-failed", shell=True)
    subprocess.call("sudo rm {}".format(SERVICE_FILE), shell=True)
    subprocess.call("sudo systemctl daemon-reload", shell=True)
    print("OK Done")
    print()

    print("*** Removing LND Address")
    subprocess.call("sudo /home/admin/config.scripts/lnd.setaddress.sh off", shell=True)
    print()

    print("*** Removing SSH Tunnel data from RaspiBlitz config")
    with open('/mnt/hdd/raspiblitz.conf') as f:
        file_content = f.read()
    file_content = re.sub("sshtunnel=.*", "", file_content)
    file_content = re.sub("\n\n", "\n", file_content)
    print(file_content)
    with open("/mnt/hdd/raspiblitz.conf", "w") as text_file:
        text_file.write(file_content)
    print("OK Done")


def main():
    if sys.argv[1] == "restore":
        print("internet.sshtunnel.py -> running with restore flag")
        on(restore_on_update=True)

    elif sys.argv[1] == "on":
        on()

    elif sys.argv[1] == "off":
        off()

    else:
        # UNKNOWN PARAMETER
        print("unknown parameter - use 'internet.sshtunnel.py -h' for help")


if __name__ == '__main__':
    main()
