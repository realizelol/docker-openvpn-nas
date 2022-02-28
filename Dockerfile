# use latest ubuntu image
FROM ubuntu:latest
## UBUNTU is more up2date @ openvpn:
# Debian: http://build.openvpn.net/debian/openvpn/testing/pool/bullseye/main/o/openvpn/
# Ubuntu: http://build.openvpn.net/debian/openvpn/testing/pool/focal/main/o/openvpn/

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="docker-openvpn-nas" \
      org.label-schema.description="OpenVPN on ubuntu docker for NAS systems" \
      org.label-schema.url="https://github.com/realizelol/docker-openvpn-nas/" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/realizelol/docker-openvpn-nas/" \
      org.label-schema.vendor="realizelol" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

# Set environment
ENV OPENVPN_CONF=/etc/openvpn \
    EASYRSA=/usr/share/easy-rsa \
    EASYRSA_CRL_DAYS=3650 \
    EASYRSA_PKI=${OPENVPN_CONF}/pki \
    ENV_DEBUG=0 \
    DEBIAN_FRONTEND=noninteractive

# escape=

# do an update & a full-upgrade
RUN apt-get -qq update \
 && apt-get full-upgrade -yqq -o=Dpkg::Use-Pty=0
# add prerequirements for openvpn
RUN apt-get install -yqq -o=Dpkg::Use-Pty=0 --no-install-recommends \
    curl ca-certificates gnupg2
RUN echo deb http://build.openvpn.net/debian/openvpn/stable \
    $(grep -oP 'VERSION_CODENAME=\K.*' /etc/os-release) main \
    > /etc/apt/sources.list.d/openvpn.list
RUN (curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg \
    | gpg --dearmor) > /etc/apt/trusted.gpg.d/openvpn.gpg
# reupdate apt-cache with new repository
RUN apt-get -qq update
# install openvpn and it's requirements
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -yqq -o=Dpkg::Use-Pty=0 --no-install-recommends \
    openvpn bridge-utils iproute2 iptables net-tools
# cleanup
RUN apt-get -qqy clean \
 && apt-get -qqy autoclean \
 && apt-get -qqy autoremove \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /tmp/*

# map /etc/openvpn
VOLUME ["/etc/openvpn"]

# always expose 1194/udp - remap using '-p 12345:1194/udp'
EXPOSE 1194/udp

# CD to /etc/openvpn
WORKDIR /etc/openvpn

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod a+x /usr/local/bin/docker-*
ENTRYPOINT /usr/local/bin/docker-entrypoint.sh ${ENV_DEBUG}
