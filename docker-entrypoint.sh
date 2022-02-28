#!/bin/bash
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009
set -e
# [ENV->ENV_DEBUG]
ENV_DEBUG=${1}
if [[ ${ENV_DEBUG} -eq 1 ]]; then
set -x
fi

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

# noninteractive
DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND=noninteractive

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
if [[ ! -f /etc/openvpn/tls-crypt.key ]]; then
  cd /etc/easy-rsa
  easyrsa init-pki
  easyrsa build-ca
  easyrsa gen-dh
  easyrsa build-server-full server
  openvpn --genkey secret /etc/easy-rsa/pki/ta.key
  easyrsa gen-crl
  cp -pR /etc/easy-rsa/pki/{ca.crt,dh.pem,ta.key,crl.pem,issued,private} /etc/openvpn/server
fi

# chmod private keys?!?!?
#

echo "$(date +'%Y-%m-%d %H:%M:%S') Starting OpenVPN:"
exec /bin/bash -c "/usr/sbin/openvpn --config /etc/openvpn/server.conf --client-config-dir /etc/openvpn/ccd --crl-verify /etc/openvpn/crl.pem"
