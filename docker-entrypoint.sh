#!/bin/bash
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009
set -e
# [ENV->ENV_DEBUG]
ENV_DEBUG=${1}
if [[ ${ENV_DEBUG} -eq 1 ]]; then
set -x
fi

# noninteractive
DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND=noninteractive

# Return netmask for a given network and CIDR.
cidr2netmask () {
  set -- $(( 5 - (${1} / 8) )) 255 255 255 255 $(( (255 << (8 - (${1} % 8))) & 255 )) 0 0 0
  [ ${1} -gt 1 ] && shift ${1} || shift; echo ${1-0}.${2-0}.${3-0}.${4-0}
}

# Create tun-device
if [ ! -e /dev/net/tun ]; then
  if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod -m 666 /dev/net/tun c 10 200
  fi
fi

# Set TimeZone [ENV->TZ]
if [ "$(cat /etc/timezone)" != "${TZ}" ]; then
  if [ -d "/usr/share/zoneinfo/${TZ}" ] || \
     [ ! -e "/usr/share/zoneinfo/${TZ}" ] || \
     [ -z "${TZ}" ]; then
       TZ="Etc/UTC"
  fi
  ln -fs "/usr/share/zoneinfo/${TZ}" /etc/localtime
  exec dpkg-reconfigure -f noninteractive tzdata
fi

if [[ -f /etc/openvpn/.env ]]; then
  source /etc/openvpn/.env
else
  CREATEDATE=$(date +%Y%m%d)
  echo "# environment file for openvpn-nas" > /etc/openvpn/.env
  echo "# created on ${CREATEDATE}" >> /etc/openvpn/.env
  echo "# please enter dyndns if not set" >> /etc/openvpn/.env
  echo "DYNDNS=${DYNDNS}" >> /etc/openvpn/.env
  echo "DOCKER_NETWORK=${LAN_NETWORK}" >> /etc/openvpn/.env

  echo ""
  echo "Getting local IP..."
  echo ""
  # Detect public IPv4 address and pre-fill for the user
  LOCAL_IPV4=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
  echo 'LOCAL_IPV4="'${LOCAL_IPV4}'"'
  LOCAL_IPV6=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
  if [[ ! -z ${LOCAL_IPV6} ]]; then
    echo 'LOCAL_IPV6="'${LOCAL_IPV6}'"'
  fi

  echo ""
  echo "Getting public IP..."
  echo ""
  PUBLIC_IPV4=$(curl -sfL4 icanhazip.com 2>/dev/null)
  echo 'PUBLIC_IPV4="'${PUBLIC_IPV4}'"   # last updated: '${CREATEDATE}'' >> /etc/openvpn/.env

  echo ""
  echo "Checking for IPv6 connectivity..."
  echo ""
  if curl -sfL6 icanhazip.com > /dev/null 2>&1; then
    echo "Your host appears to have IPv6 connectivity."
    PUBLIC_IPV6=$(curl -sfL6 icanhazip.com 2>/dev/null)
    echo 'PUBLIC_IPV6="'${PUBLIC_IPV6}'"   # last updated: '${CREATEDATE}'' >> /etc/openvpn/.env
  fi

  # set protcol to "udp" -> change in .env file by yourself if you need it
  echo 'PROTOCOL="'${PROTOCOL:-udp}'"' >> /etc/openvpn/.env

  # set DNS to "10.123.231.1,9.9.9.9" -> change in .env file by yourself if you need other ones
  echo 'DNS="'${DNS:-10.123.231.1,9.9.9.9}'"' >> /etc/openvpn/.env

  # set compression -> change in .env file -> be noticed that this will be a security issue !!! (VORACLE attack)
  echo 'COMPRESSION_ENABLED="'${COMPRESSION_ENABLED:-n}'"' >> /etc/openvpn/.env # other values: (lz4-v2, lz4, lzo)

  #
  # OpenVPN Encryption
  #
  echo 'CIPHER="AES-256-GCM"' >> /etc/openvpn/.env
  echo 'CERT_TYPE="1"' >> /etc/openvpn/.env # ECDSA, 0 = RSA
  echo 'RSA_KEY_SIZE="4096"' >> /etc/openvpn/.env # other vals: 2048, 3072
  echo 'CERT_CURVE="secp384r1"' >> /etc/openvpn/.env # other values: prime256v1, secp521r1
  echo 'CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384"' >> /etc/openvpn/.env # other val:
  # TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256
  # or with RSA: TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256, TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384
  echo 'DH_TYPE="1"' >> /etc/openvpn/.env # ECDH, 0 = DH
  echo 'DH_CURVE="secp384r1"' >> /etc/openvpn/.env # other values: prime256v1, secp521r1
  echo 'DH_KEY_SIZE="4096"' >> /etc/openvpn/.env # other vals: 2048, 3072
  echo 'HMAC_ALG="SHA256"' >> /etc/openvpn/.env # other vals: SHA384, SHA512
  echo 'TLS_SIG="1"' >> /etc/openvpn/.env # tls-crypt, other vals: tls-auth (only authentication without encryption)

fi

# export all env variables
while IFS="" read -r p || [ -n "$p" ]; do export $p; done < /etc/openvpn/.env

# upgrade all packages (do not upgrade config files!)
apt-get -qq update
apt-get -yqq -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" full-upgrade

#update easy-rsa if not the latest
EASYRSA_LOCAL_VER=$(dpkg -s 'easy-rsa' 2>/dev/null | grep -oP '^Version: \K.*' || true)
EASYRSA_GITHUB_VER=$(curl -fsSL https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest \
                     2>/dev/null | grep -oP '"tag_name": "v\K(.*)(?=",)' || true)
if [[ ! -z $(dpkg -l easy-rsa 2>/dev/null | grep -E '^(r|h|i)i' || true) ]]; then
  if [[ "${EASYRSA_LOCAL_VER//[^[:alnum:]]/}" != "${EASYRSA_GITHUB_VER//[^[:alnum:]]/}" ]] && \
     [[ "${EASYRSA_LOCAL_VER//[^[:alnum:]]/}" <  "${EASYRSA_GITHUB_VER//[^[:alnum:]]/}" ]]; then
    apt-get autoremove --purge -yqq easy-rsa
    mkdir -p /tmp/easyrsadl
    curl -fsSL https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest 2>/dev/null \
      | sed -n 's/.*"browser_download_url": "\(.*\).tgz".*/\1/p' \
      | xargs -n1 -I % curl -fsSL %.tgz -o - \
      | tar -xz --strip-components=1 -C /tmp/easyrsadl
    mv /tmp/easyrsadl/easyrsa /usr/local/bin/easyrsa
    rm -rf /tmp/easyrsadl
  fi
else
  mkdir -p /tmp/easyrsadl
  curl -fsSL https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest 2>/dev/null \
    | sed -n 's/.*"browser_download_url": "\(.*\).tgz".*/\1/p' \
    | xargs -n1 -I % curl -fsSL %.tgz -o - \
    | tar -xz --strip-components=1 -C /tmp/easyrsadl
  mv /tmp/easyrsadl/easyrsa /usr/local/bin/easyrsa
  rm -rf /tmp/easyrsadl
fi

# init easy-rsa pki if not exist
if [[ ! -f /etc/openvpn/tls-crypt.key ]] || [[ ! -f /etc/openvpn/tls-auth.key ]]; then
  if [[ -z ${SERVER_CN} ]]; then
    SERVER_CN_RND="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
    echo 'SERVER_CN="'${SERVER_CN:-${SERVER_CN_RND}}'"' >> /etc/openvpn/.env
    echo 'EASYRSA_REQ_CN="'${SERVER_CN:-${SERVER_CN_RND}}'"' >> /etc/openvpn/.env
  fi
  if [[ -z ${SERVER_CN} ]]; then
    SERVER_NAME_RND="server_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
    echo 'SERVER_NAME="'${SERVER_NAME:-${SERVER_NAME_RND}}'"' >> /etc/openvpn/.env
  fi

  # generate a crl for 10 years
  if ! grep -q "EASYRSA_CRL_DAYS="; then
    echo 'EASYRSA_CRL_DAYS="3650"' >> /etc/openvpn/.env
  fi

  while IFS="" read -r p || [ -n "$p" ]; do export $p; done < /etc/openvpn/.env

  cd /etc/easy-rsa
  easyrsa init-pki
  easyrsa --batch build-ca gen-req "${EASYRSA_REQ_CN}" nopass
  if [[ "${DH_TYPE}" -eq 2 ]]; then
    # ECDH keys are generated on-the-fly so we don't need to generate them beforehand
    openssl dhparam -out dh.pem "${DH_KEY_SIZE}"
  fi
  easyrsa gen-dh
  easyrsa build-server-full server
  if [[ "${TLS_SIG}" -eq 1 ]]; then
    openvpn --genkey --secret /etc/openvpn/tls-crypt.key
  fi
  if [[ "${TLS_SIG}" -eq 2 ]]; then
    openvpn --genkey --secret /etc/openvpn/tls-auth.key
  fi
  easyrsa gen-crl
  cp -pR /etc/easy-rsa/pki/{ca.crt,dh.pem,ta.key,crl.pem,issued,private} /etc/openvpn/server

  # set permissions
  chmod 600 /etc/openvpn/crl.pem #revokation certificate

  # Generate server.conf
  if [[ ! -f /etc/openvpn/server.conf ]]; then
    NETWORK="${DOCKER_NETWORK%%\/*}"
    NETMASK="${DOCKER_NETWORK##*\/}"

    echo "port ${PORT}" >/etc/openvpn/server.conf
    echo "proto ${PROTOCOL}" >>/etc/openvpn/server.conf
    echo "dev tun" >> /etc/openvpn/server.conf
    echo "user nobody" >> /etc/openvpn/server.conf
    echo "group nogroup" >> /etc/openvpn/server.conf
    echo "persist-key" >> /etc/openvpn/server.conf
    echo "persist-tun" >> /etc/openvpn/server.conf
    echo "keepalive 10 120" >> /etc/openvpn/server.conf
    echo "topology subnet" >> /etc/openvpn/server.conf
    echo "server ${NETWORK} ${NETMASK}" >> /etc/openvpn/server.conf
    echo "ifconfig-pool-persist ipp.txt" >> /etc/openvpn/server.conf
    if [[ ! -z ${PUBLIC_IPV6} ]]; then
      echo "proto ${PROTOCOL}6" >> /etc/openvpn/server.conf
      echo "server-ipv6 fd42:42:42:42::/112" >> /etc/openvpn/server.conf
      echo "tun-ipv6" >> /etc/openvpn/server.conf
      echo "push tun-ipv6" >> /etc/openvpn/server.conf
      echo "push \"route-ipv6 2000::/3\"" >> /etc/openvpn/server.conf
      echo "push \"redirect-gateway ipv6\"" >> /etc/openvpn/server.conf
    fi
    if [[ "${COMPRESSION_ENABLED}" == "y" ]]; then
      echo "compress ${COMPRESSION_ALG}" >> /etc/openvpn/server.conf
    fi
    if [[ "${DH_TYPE}" -eq 1 ]]; then
      echo "dh none" >> /etc/openvpn/server.conf
      echo "ecdh-curve ${DH_CURVE}" >> /etc/openvpn/server.conf
    elif [[ "${DH_TYPE}" -eq 2 ]]; then
      echo "dh dh.pem" >> /etc/openvpn/server.conf
    fi
    if [[ "${TLS_SIG}" -eq 1 ]]; then
      echo "tls-crypt tls-crypt.key" >>/etc/openvpn/server.conf
    elif [[ "${TLS_SIG}" -eq 2 ]]; then
      echo "tls-auth tls-auth.key 0" >>/etc/openvpn/server.conf
    fi
    echo "crl-verify crl.pem"
    echo "ca ca.crt"
    echo "cert ${SERVER_NAME}.crt"
    echo "key ${SERVER_NAME}.key"
    echo "auth ${HMAC_ALG}"
    echo "cipher ${CIPHER}"
    echo "ncp-ciphers ${CIPHER}"
    echo "tls-server"
    echo "tls-version-min 1.2"
    echo "tls-cipher ${CC_CIPHER}"
    echo "client-config-dir /etc/openvpn/ccd"
    echo "status /var/log/openvpn/status.log"
    echo "verb 3" >>/etc/openvpn/server.conf
fi

mkdir -p /etc/openvpn/ccd
mkdir -p /var/log/openvpn

# enable routing
echo "net.ipv4.ip_forward=1" >/etc/sysctl.d/99-openvpn.conf
if [[ "${PUBLIC_IPV6}" == "y" ]]; then
  echo "net.ipv6.conf.all.forwarding=1" >>/etc/sysctl.d/99-openvpn.conf
fi
# Apply sysctl rules
sysctl --system

## iptables script file
add-openvpn-rules.sh # add custom rules in it

# chmod private keys?!?!?
#

echo "$(date +'%Y-%m-%d %H:%M:%S') Starting OpenVPN:"
exec /bin/bash -c "/usr/sbin/openvpn --config /etc/openvpn/server.conf --client-config-dir /etc/openvpn/ccd --crl-verify /etc/openvpn/crl.pem"
