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

# Install prerequisites to add the Tor Project APT repository and GPG key,
# then add the upstream Tor Project repository and install tor from there.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        dirmngr \
        lsb-release; \
    \
    # Fetch and install the Tor Project archive keyring (dearmor to keyring file)
    curl -fsSL https://deb.torproject.org/torproject.org/gpgkey | gpg --dearmor > /usr/share/keyrings/tor-archive-keyring.gpg; \
    \
    # Add Tor Project APT repository (use 'stable' so it remains compatible with Debian stable)
    echo "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/torproject.list; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        tor \
        tor-geoipdb; \
    \
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
