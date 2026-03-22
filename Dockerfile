# syntax=docker/dockerfile:1

# Dockerfile for AmneziaWG with LinuxServer.io architecture
# Multi-stage build: compile amneziawg-go, awg-tools, then create runtime image

# ============================================================================
# Stage 1: Compile amneziawg-go
# ============================================================================
FROM golang:1.24.4-alpine AS go-builder

RUN apk add --no-cache git build-base

WORKDIR /src
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git .
RUN CGO_ENABLED=1 go build -ldflags '-linkmode external -extldflags "-fno-PIC -static"' -v -o amneziawg-go

# ============================================================================
# Stage 2: Compile awg-tools from source
# ============================================================================
FROM alpine:3.21 AS tools-builder

RUN apk add --no-cache git build-base linux-headers bash

WORKDIR /src
RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git .
WORKDIR /src/src
# Build awg binary and install awg-quick script
RUN make && \
    make install DESTDIR=/tools-install && \
    mkdir -p /tools-install/usr/bin && \
    cp /src/src/wg-quick/linux.bash /tools-install/usr/bin/awg-quick && \
    chmod +x /tools-install/usr/bin/awg-quick

# ============================================================================
# Stage 3: Runtime image using LinuxServer base
# ============================================================================
FROM ghcr.io/linuxserver/baseimage-alpine:3.21

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="AmneziaWG version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="AYastrebov"
LABEL org.opencontainers.image.source="https://github.com/AYastrebov/docker-amneziawg"
LABEL org.opencontainers.image.description="AmneziaWG VPN container with LinuxServer.io architecture"
LABEL org.opencontainers.image.licenses="MIT"

ENV LSIO_FIRST_PARTY="false"

RUN \
  echo "**** install dependencies ****" && \
  apk add --no-cache \
    bc \
    coredns \
    grep \
    iproute2 \
    iptables \
    ip6tables \
    iputils \
    kmod \
    libcap-utils \
    libqrencode-tools \
    net-tools \
    nftables \
    openresolv && \
  echo "wireguard" >> /etc/modules && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# Copy compiled binaries from builder stages
COPY --from=go-builder /src/amneziawg-go /usr/bin/
COPY --from=tools-builder /tools-install/usr/bin/awg /usr/bin/
COPY --from=tools-builder /tools-install/usr/bin/awg-quick /usr/bin/

# Create symlinks for WireGuard compatibility
RUN \
  ln -sf /usr/bin/awg /usr/bin/wg && \
  ln -sf /usr/bin/awg-quick /usr/bin/wg-quick && \
  chmod +x /usr/bin/awg /usr/bin/awg-quick /usr/bin/amneziawg-go

# Apply awg-quick sysctl patch to avoid errors when sysctl is already set
RUN sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/awg-quick

# Create symlink for /etc/wireguard -> /config/wg_confs
RUN \
  rm -rf /etc/wireguard && \
  ln -s /config/wg_confs /etc/wireguard

# add local files
COPY /root /

# ports and volumes
EXPOSE 51820/udp
