# parameter #1: password c to unlock wallet
import base64
import codecs
import json
import requests
import sys

pw = sys.argv[1]

url = 'https://localhost:8080/v1/unlockwallet'
cert_path = '/mnt/hdd/lnd/tls.cert'

try:
    pw_b64 = base64.b64encode(pw).decode()
except TypeError:  # for Python3+
    pw_b64 = base64.b64encode(pw.encode()).decode('UTF-8')

data = {'wallet_password': pw_b64}
try:
    r = requests.post(url, verify=cert_path, data=json.dumps(data))
except requests.exceptions.ConnectionError as err:
    print(err)
    print("\nAn Error occurred - is LND running?")
    sys.exit(1)

if r.status_code == 404:
    print("Already unlocked!")
else:
    print(r.json())
