ARG BASE_IMAGE=debian:trixie-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0

#####################################################################
# Build stage: compile SOPE and SOGo into /usr/local
#####################################################################
FROM ${BASE_IMAGE} AS builder
# renovate: datasource=github-tags depName=Alinto/sogo extractVersion=^SOGo-(?<version>.+)$
ENV SOGO_VERSION=5.12.14
ENV SOPE_VERSION=${SOGO_VERSION}
# Attention when chaning the source URLs!
# The script below assumes the source zip files to contain a
# top-level folder sogo-SOGo-${SOGO_VERSION} and sope-SOPE-${SOPE_VERSION}, respectively!
ENV SOGO_SOURCE_URL=https://github.com/Alinto/sogo/archive/refs/tags/SOGo-${SOGO_VERSION}.zip
ENV SOPE_SOURCE_URL=https://github.com/Alinto/sope/archive/refs/tags/SOPE-${SOPE_VERSION}.zip
ENV DEBIAN_FRONTEND=noninteractive

RUN <<EOT
    set -eux
    apt update
    apt install -y --no-install-recommends ca-certificates gnustep-make gnustep-base-runtime libgnustep-base-dev gobjc libxml2-dev libssl-dev libldap-dev libpq-dev libmemcached-dev libcurl4-openssl-dev libmariadb-dev-compat curl unzip pkg-config libsodium-dev libzip-dev libytnef0-dev liblasso3-dev liboath-dev libcrypt-dev python-is-python3
    echo "Downloading SOGo & SOPE"
    curl -fL ${SOGO_SOURCE_URL} -o /tmp/sogo.zip
    curl -fL ${SOPE_SOURCE_URL} -o /tmp/sope.zip
    unzip -q /tmp/sogo.zip -d /tmp
    unzip -q /tmp/sope.zip -d /tmp
    echo "Compiling SOPE"
    mv /tmp/sope-SOPE-${SOPE_VERSION} /tmp/SOPE
    # Separate commands instead of && chains, otherwise "set -e" does not abort on failing steps
    cd /tmp/SOPE
    ./configure --with-gnustep --disable-strip --enable-debug
    make
    make install
    echo "Compiling SOGo"
    mv /tmp/sogo-SOGo-${SOGO_VERSION} /tmp/SOGo
    cd /tmp/SOGo
    ./configure --disable-strip --enable-debug --enable-mfa --enable-sodium --enable-saml2
    make
    make install
    # Headers are only needed for compiling
    rm -rf /usr/local/include
EOT

#####################################################################
# supercronic: cron replacement which runs without root privileges
#####################################################################
FROM golang:1.27.4-trixie@sha256:430985542100b871e108ccc00e8dcc5eef08ca14ee5825e98ebf563d8ffec4ee AS supercronic
# renovate: datasource=go depName=github.com/aptible/supercronic
ARG SUPERCRONIC_VERSION=v0.2.51
RUN CGO_ENABLED=0 go install github.com/aptible/supercronic@${SUPERCRONIC_VERSION}

#####################################################################
# Runtime stage: only runtime libraries and the compiled SOGo
#####################################################################
FROM ${BASE_IMAGE}

LABEL maintainer="Salvoxia <salvoxia@blindfish.info>"
ENV DEBIAN_FRONTEND=noninteractive
ENV USEWATCHDOG=YES
ENV LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt
# Apache runs without root privileges, so it can only listen on ports above 1024
ENV HTTP_PORT=8080
ENV HTTPS_PORT=8443
# The container can run with any UID, which might not exist in /etc/passwd
ENV HOME=/srv/lib/sogo

# Install runtime dependencies for SOGo and SOPE
# Only the GNUstep base library is required, gnustep-base-runtime would pull in graphviz and friends
RUN <<EOT
    set -eux
    apt update
    apt install -y --no-install-recommends ca-certificates libgnustep-base1.31 libobjc4 libxml2 libssl3t64 libldap2 libpq5 libmariadb3 libmemcached11t64 libcurl4t64 libsodium23 libzip5 libytnef0 liboath0t64 liblasso3t64 libcrypt1 zlib1g gettext-base apache2 apache2-utils memcached curl
    apt clean
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/debconf/tmp.ci
    # Created group-writable during package installation, nothing besides the intended locations must be writable
    chmod g-w /usr/share/man/man*
EOT

COPY --from=builder /usr/local /usr/local
COPY --from=supercronic /go/bin/supercronic /usr/local/bin/supercronic

RUN <<EOT
    set -eux
    echo "register sogo library"
    echo "/usr/local/lib/sogo" > /etc/ld.so.conf.d/sogo.conf
    ldconfig
    # Fixed IDs, which match the ones of previous versions, so existing volumes keep working
    groupadd --system --gid 999 sogo
    useradd --system --uid 999 --gid sogo --home-dir /srv/lib/sogo --no-create-home sogo
    echo "create directories and enforce permissions"
    # Writable locations are owned by user sogo and group root (GID 0) and are group-writable,
    # so the container also works with any other UID, as long as its GID is 0
    install -o sogo -g root -m 775 -d /var/run/sogo
    install -o sogo -g root -m 775 -d /etc/sogo
    install -o sogo -g root -m 770 -d /var/spool/sogo
    install -o sogo -g root -m 770 -d /var/log/sogo
    # /srv/etc is included, so Docker does not create it as root when single files are mounted into it
    install -o sogo -g root -m 775 -d /srv /srv/etc
    # Activate required Apache modules
    a2enmod headers proxy proxy_http rewrite ssl
    # Apache runs as user sogo: listen on ports above 1024, make its directories writable
    # and replace the default site, which only serves port 80
    a2dissite 000-default
    sed -i -E 's/^(\s*Listen) 80$/\1 ${HTTP_PORT}/; s/^(\s*Listen) 443$/\1 ${HTTPS_PORT}/' /etc/apache2/ports.conf
    sed -i -E 's/^(export APACHE_RUN_(USER|GROUP))=.*/\1=sogo/' /etc/apache2/envvars
    # apache2ctl creates the socks directory owned by APACHE_RUN_USER, which only works as root or sogo
    install -o sogo -g root -m 775 -d /var/run/apache2 /var/run/apache2/socks /var/lock/apache2
    chown -R sogo:root /var/log/apache2
    chmod -R g=u /var/log/apache2
    install -o sogo -g root -m 664 /dev/null /etc/apache2/conf-enabled/SOGo.conf
EOT

# SOGo daemons
# Explicit permissions, COPY would keep the ones of the build context, which might be writable for the group
COPY --chmod=755 apache2.sh cron.sh cron-legacy-check.sh memcached.sh sogo-tmpwatch.sh sogod.sh start.sh /
COPY template /template
RUN chmod -R go-w /template


# Interface the environment
VOLUME /srv
EXPOSE 8080 8443 8800

# /SOGo is proxied to sogod by Apache, so this fails if either of them is down
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl --fail --silent --output /dev/null "http://localhost:${HTTP_PORT}/SOGo" || exit 1

# Any other UID must run with GID 0 (group root, which has no privileges), as group root
# owns all writable locations
USER 999:999

ENTRYPOINT ["sh", "-c", "/start.sh && tail -f /var/log/sogo/sogo.log"]
