# use latest debian image
FROM debian:stable-slim

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="docker-openvpn-nas" \
      org.label-schema.description="docker container with OpenVPN on debian linux for NAS systems" \
      org.label-schema.url="https://github.com/realizelol/docker-openvpn-nas/" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/realizelol/docker-openvpn-nas/" \
      org.label-schema.vendor="realizelol" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

RUN VERSION_CODENAME=$(grep -oP 'VERSION_CODENAME=\K.*' /etc/os-release)

# Set environment
ENV OPENVPN=/etc/openvpn \
    EASYRSA=/usr/share/easy-rsa \
    EASYRSA_CRL_DAYS=3650 \
    EASYRSA_PKI=$OPENVPN/pki \
    VERSION_CODENAME=${VERSION_CODENAME}

# set default shell: bash
SHELL ["/bin/bash", "-c", "\"$@\""]

# add prerequirements for openvpn
CMD ["/bin/bash", "-c", "echo 'deb http://build.openvpn.net/debian/openvpn/stable '${VERSION_CODENAME}' main' \
    > /etc/apt/sources.list.d/openvpn.list"]
CMD ["/bin/bash", "-c", "curl --connect-timeout 15 --retry 10 --max-time 30 -s \
    'https://swupdate.openvpn.net/repos/repo-public.gpg' \
    | apt-key add -"]
# do an update & a full-upgrade
RUN apt-get -qq update \
 && apt-get full-upgrade -yqq -o=Dpkg::Use-Pty=0
# install openvpn and it's requirements
RUN apt-get install -yqq -o=Dpkg::Use-Pty=0 --no-install-recommends \
    openvpn easy-rsa openvpn-auth-pam \
    google-authenticator pamtester libqrencode \
    bridge-utils iproute2 iptables net-tools
# cleanup
RUN fc-cache \
 && apt-get -qqy clean \
 && apt-get -qqy autoclean \
 && apt-get -qqy autoremove \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /tmp/*
# ?
#RUN ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin

# map /etc/openvpn
VOLUME ["/etc/openvpn"]

# always expose 1194/udp - remap using '-p 12345:1194/udp'
EXPOSE 1194/udp

WORKDIR /etc/openvpn

ADD docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod a+x /usr/local/bin/docker-*
CMD ["/usr/local/bin/docker-entrypoint.sh"]

# Add support for OTP authentication using a PAM module
#ADD ./otp/openvpn /etc/pam.d/
