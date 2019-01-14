# parameter #1: old password c to unlock wallet
# parameter #2: new password c
import base64, codecs, json, requests, sys
url = 'https://localhost:8080/v1/changepassword'
cert_path = '/mnt/hdd/lnd/tls.cert'
data = {
    'current_password': base64.b64encode(sys.argv[1]).decode(),
    'new_password' : base64.b64encode(sys.argv[2]).decode()
}
r = requests.post(url, verify=cert_path, data=json.dumps(data))
print(r.json())