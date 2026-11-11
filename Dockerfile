ARG BASE_IMAGE=ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

#####################################################################
# Build stage: compile SOPE and SOGo into /usr/local
#####################################################################
FROM ${BASE_IMAGE} AS builder
ENV SOGO_VERSION=5.12.13
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
    apt install -y --no-install-recommends ca-certificates gnustep-make gnustep-base-runtime libgnustep-base-dev gobjc libxml2-dev libssl-dev libldap-dev postgresql-server-dev-all libmemcached-dev libcurl4-openssl-dev libmysqlclient-dev curl unzip pkg-config libsodium-dev libzip-dev libytnef0-dev liblasso3-dev liboath-dev libcrypt-dev
    echo "Downloading SOGo & SOPE"
    curl -fL ${SOGO_SOURCE_URL} -o /tmp/sogo.zip
    curl -fL ${SOPE_SOURCE_URL} -o /tmp/sope.zip
    unzip -q /tmp/sogo.zip -d /tmp
    unzip -q /tmp/sope.zip -d /tmp
    echo "Compiling SOPE"
    mv /tmp/sope-SOPE-${SOPE_VERSION} /tmp/SOPE
    cd /tmp/SOPE && ./configure --with-gnustep --disable-strip --enable-debug && make && make install
    echo "Compiling SOGo"
    mv /tmp/sogo-SOGo-${SOGO_VERSION} /tmp/SOGo
    cd /tmp/SOGo && ./configure --disable-strip --enable-debug && make && make install
    # Headers are only needed for compiling
    rm -rf /usr/local/include
EOT

#####################################################################
# Runtime stage: only runtime libraries and the compiled SOGo
#####################################################################
FROM ${BASE_IMAGE}

LABEL maintainer="Salvoxia <salvoxia@blindfish.info>"
ENV DEBIAN_FRONTEND=noninteractive
ENV USEWATCHDOG=YES
ENV LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt

# Install runtime dependencies for SOGo and SOPE
# Only the GNUstep base library is required, gnustep-base-runtime would pull in graphviz and friends
RUN <<EOT
    set -eux
    apt update
    apt install -y --no-install-recommends ca-certificates libgnustep-base1.31 libobjc4 libxml2-16 libssl3t64 libldap2 libpq5 libmysqlclient24 libmemcached11t64 libcurl4t64 libsodium23 libzip5 libytnef0 libcrypt1 zlib1g gettext-base apache2 apache2-utils cron memcached curl
    apt clean
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

COPY --from=builder /usr/local /usr/local

RUN <<EOT
    set -eux
    echo "register sogo library"
    echo "/usr/local/lib/sogo" > /etc/ld.so.conf.d/sogo.conf
    ldconfig
    groupadd --system sogo && useradd --system --gid sogo sogo
    usermod --home /srv/lib/sogo sogo
    echo "create directories and enforce permissions"
    install -o sogo -g sogo -m 755 -d /var/run/sogo
    install -o sogo -g sogo -m 755 -d /etc/sogo
    install -o sogo -g sogo -m 750 -d /var/spool/sogo
    install -o sogo -g sogo -m 750 -d /var/log/sogo
    # Activate required Apache modules
    a2enmod headers proxy proxy_http rewrite ssl
EOT

# SOGo daemons
COPY template /template
COPY apache2.sh /
COPY cron.sh /
COPY memcached.sh /
COPY sogod.sh /
COPY start.sh /
RUN chmod +x apache2.sh cron.sh memcached.sh sogod.sh start.sh


# Interface the environment
VOLUME /srv
EXPOSE 80 443 8800

# /SOGo is proxied to sogod by Apache, so this fails if either of them is down
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl --fail --silent --output /dev/null http://localhost/SOGo || exit 1

ENTRYPOINT ["sh", "-c", "/start.sh && tail -f /var/log/sogo/sogo.log"]
