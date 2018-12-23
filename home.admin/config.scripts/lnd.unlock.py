# parameter #1: password c to unlock wallet
import base64, codecs, json, requests, sys
url = 'https://localhost:8080/v1/unlockwallet'
cert_path = '/mnt/hdd/lnd/tls.cert'
data = {
    'wallet_password': base64.b64encode(sys.argv[1]).decode()
}
r = requests.post(url, verify=cert_path, data=json.dumps(data))
print(r.json())