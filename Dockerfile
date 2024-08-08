FROM ubuntu:24.04
ENV SOGO_VERSION=5.11.0
ENV SOPE_VERSION=${SOGO_VERSION}
# Attention when chaning the source URLs!
# The script below assumes the source zip files to contain a 
# top-level folder sogo-SOGo-${SOGO_VERSION} and sope-SOPE-${SOPE_VERSION}, respectively!
ENV SOGO_SOURCE_URL=https://github.com/Alinto/sogo/archive/refs/tags/SOGo-${SOGO_VERSION}.zip
ENV SOPE_SOURCE_URL=https://github.com/Alinto/sope/archive/refs/tags/SOPE-${SOPE_VERSION}.zip


LABEL maintainer="Salvoxia <salvoxia@blindfish.info>"
ENV DEBIAN_FRONTEND=noninteractive
ENV USEWATCHDOG=YES
ENV LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt


# Install build dependencies, download SOGo and SOPE source, compile, install and remove dependencies in a single RUN
# command to prevent the image from bloat up due to too many layers
RUN apt update && \
    apt install -y --no-install-recommends gnustep-make gnustep-base-runtime libgnustep-base-dev gobjc libxml2-dev libssl-dev libldap-dev postgresql-server-dev-all libmemcached-dev libcurl4-openssl-dev libmysqlclient-dev curl unzip pkg-config libsodium-dev libzip-dev libytnef0-dev liblasso3-dev liboath-dev  && \
    echo "Downloading SOGo & SOPE" && \
    curl -L ${SOGO_SOURCE_URL} -o /tmp/sogo.zip && \
    curl -L ${SOPE_SOURCE_URL} -o /tmp/sope.zip && \
    unzip /tmp/sogo.zip -d /tmp && \
    unzip /tmp/sope.zip -d /tmp && \
    echo "Compiling SOPE" && \
    mv /tmp/sope-SOPE-${SOPE_VERSION} /tmp/SOPE  && \
    cd /tmp/SOPE && ./configure --with-gnustep --disable-strip --enable-debug && make && make install && \
    echo "Compiling SOGo" && \
    mv /tmp/sogo-SOGo-${SOGO_VERSION} /tmp/SOGo && \
    cd /tmp/SOGo && ./configure --disable-strip --enable-debug && make && make install && \
    echo "register sogo library" && \
    echo "/usr/local/lib/sogo" > /etc/ld.so.conf.d/sogo.conf && \
    ldconfig && \
    groupadd --system sogo && useradd --system --gid sogo sogo && \
    usermod --home /srv/lib/sogo sogo && \
    echo "create directories and enforce permissions" && \
    install -o sogo -g sogo -m 755 -d /var/run/sogo && \
    install -o sogo -g sogo -m 755 -d /etc/sogo && \
    install -o sogo -g sogo -m 750 -d /var/spool/sogo && \
    install -o sogo -g sogo -m 750 -d /var/log/sogo && \
    apt remove -y libgnustep-base-dev gobjc libxml2-dev libssl-dev libldap-dev postgresql-server-dev-all libmemcached-dev libcurl4-openssl-dev libmysqlclient-dev unzip pkg-config libsodium-dev libzip-dev libytnef0-dev liblasso3-dev liboath-dev && \
    # Install runtime dependencies for SOGo and SOPE
    apt install -y --no-install-recommends gnustep-base-runtime libc6 libcrypt1 libcurl4 libgcc-s1 liblasso3 libmemcached11 liboath0 libobjc4 libsbjson libsodium23 libssl3 libytnef0 libzip4 gnustep-make gettext-base apache2 libmysqlclient21 libpq5 zlib1g libxml2 cron memcached && \
    apt autoremove -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Activate required Apache modules
RUN a2enmod headers proxy proxy_http rewrite ssl

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

ENTRYPOINT ["sh", "-c", "/start.sh && tail -f /var/log/sogo/sogo.log"]
