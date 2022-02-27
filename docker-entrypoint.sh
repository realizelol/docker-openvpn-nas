#!/bin/bash
set -x
set -e

# noninteractive
DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND=noninteractive

# upgrade all packages (do not upgrade config files!)
apt-get -qq update
apt-get -yqq -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" full-upgrade

# init easy-rsa pki if not exist
if [[ ! -f /etc/openvpn/tls-crypt.key ]]; then
  cp -pR /usr/share/easy-rsa /etc/easy-rsa && \
  cd /etc/easy-rsa
  ./easyrsa init-pki
  ./easyrsa build-ca
  ./easyrsa gen-dh
  ./easyrsa build-server-full server
  openvpn --genkey secret /etc/easy-rsa/pki/ta.key
  ./easyrsa gen-crl
  cp -rp /etc/easy-rsa/pki/{ca.crt,dh.pem,ta.key,crl.pem,issued,private} /etc/openvpn/server
fi

# install cont-environment
mkdir -p /etc/services.d/openvpn
cat > /etc/services.d/openvpn/run << EOF
#!/usr/bin/with-contenv bash

/usr/sbin/openvpn --nodaemon --umask=0077 --pidfile=/var/run/openvpn.pid --logfile=/var/log/openvpn.log
EOF

echo "$(date +'%Y-%M-%d %H:%M:%S') - Running openvpn"
exec /bin/bash -c "/usr/sbin/openvpn --config /etc/openvpn/server.conf --client-config-dir /etc/openvpn/ccd --crl-verify /etc/openvpn/crl.pem"
