#!/bin/bash
set -x
set -e

# noninteractive
DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND=noninteractive

# upgrade all packages (do not upgrade config files!)
apt-get -qq update
apt-get -yqq -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" full-upgrade

# install cont-environment
mkdir -p /etc/services.d/openvpn
cat > /etc/services.d/openvpn/run << EOF
#!/usr/bin/with-contenv bash

/usr/sbin/openvpn --nodaemon --umask=0077 --pidfile=/var/run/openvpn.pid --logfile=/var/log/openvpn.log
EOF

echo "Running openvpn"
exec /bin/bash -c "/usr/sbin/openvpn --config /etc/openvpn/openvpn.conf --client-config-dir /etc/openvpn/ccd --crl-verify /etc/openvpn/crl.pem"
