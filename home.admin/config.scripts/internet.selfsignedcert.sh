# script to create a self-signed SSL certificate

echo ""
echo "***"
echo "installing Nginx"
echo "***"
echo ""
sudo apt-get install -y nginx
sudo /etc/init.d/nginx start 2>/dev/null

# Only generate if there is none. Or Electrum will not connect if the cert changed.
if [ -f /etc/ssl/certs/localhost.crt ] ; then
  echo "A self-signed certificate is already present" 
else
  echo ""
  echo "***"
  echo "Create a self signed SSL certificate"
  echo "***"
  echo ""
  
  #https://www.humankode.com/ssl/create-a-selfsigned-certificate-for-nginx-in-5-minutes
  #https://stackoverflow.com/questions/8075274/is-it-possible-making-openssl-skipping-the-country-common-name-prompts
  echo "
[req]
prompt             = no
default_bits       = 2048
default_keyfile    = localhost.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca

[req_distinguished_name]
C = US
ST = California
L = Los Angeles
O = Our Company Llc
#OU = Org Unit Name
CN = Our Company Llc
#emailAddress = info@example.com

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1   = localhost
DNS.2   = 127.0.0.1
" | tee localhost.conf

  openssl req -x509 -nodes -days 1825 -newkey rsa:2048 -keyout localhost.key -out localhost.crt -config localhost.conf
  sudo mv localhost.crt /etc/ssl/certs/localhost.crt
  sudo mv localhost.key /etc/ssl/private/localhost.key
fi