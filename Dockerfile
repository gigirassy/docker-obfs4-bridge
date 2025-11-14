# build lyrebird
FROM golang AS builder

RUN git clone https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird /lyrebird
RUN cd /lyrebird && make build

# Base docker image
FROM debian:stable-slim

# Set to 101 for backward compatibility
ARG UID=101
ARG GID=101

LABEL maintainer="meskio <meskio@torproject.org>"

# Create debian-tor user/group (keep same UID/GID so package install won't re-create them differently)
RUN groupadd -g $GID debian-tor \
 && useradd -m -u $UID -g $GID -s /bin/false -d /var/lib/tor debian-tor

# Install Tor from the Tor Project APT repository when the architecture is supported.
# If the architecture is not supported by the Tor Project repo (only amd64, arm64, i386),
# fall back to Debian stable-backports (as noted in the instructions).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      apt-transport-https \
      ca-certificates \
      wget \
      gnupg \
      dirmngr \
      lsb-release; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "i386" ]; then \
      # Add Tor Project signing key (kept in keyring file)
      wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
        | gpg --dearmor > /usr/share/keyrings/deb.torproject.org-keyring.gpg; \
      CODENAME="$(lsb_release -sc)"; \
      echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org $CODENAME main" \
        > /etc/apt/sources.list.d/tor.list; \
      echo "deb-src [arch=$ARCH signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org $CODENAME main" \
        >> /etc/apt/sources.list.d/tor.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends \
        tor \
        deb.torproject.org-keyring \
        tor-geoipdb; \
    else \
      # Architecture not supported by Tor Project repo -> use Debian backports (armhf, other archs)
      echo "deb http://deb.debian.org/debian stable-backports main" > /etc/apt/sources.list.d/backports.list; \
      apt-get update; \
      apt-get install -y -t stable-backports \
        tor \
        tor-geoipdb; \
    fi; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /lyrebird/lyrebird /usr/bin/lyrebird
# Allow lyrebird to bind to ports < 1024.
RUN setcap cap_net_bind_service=+ep /usr/bin/lyrebird

# Our torrc is generated at run-time by the script start-tor.sh.
RUN rm -f /etc/tor/torrc
RUN chown debian-tor:debian-tor /etc/tor
RUN chown debian-tor:debian-tor /var/log/tor

COPY start-tor.sh /usr/local/bin
RUN chmod 0755 /usr/local/bin/start-tor.sh

COPY get-bridge-line /usr/local/bin
RUN chmod 0755 /usr/local/bin/get-bridge-line

USER debian-tor

CMD [ "/usr/local/bin/start-tor.sh" ]
