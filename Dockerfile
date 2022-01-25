# Dockerfile for elabftw web container
# nginx custom + php-fpm + elabftw complete production files
# https://github.com/elabftw/elabimg

# build nginx with only the bare minimum of features or modules
# Note: no need to chain the RUN commands here as it's a builder image and nothing will be kept
FROM alpine:3.14 as nginx-builder

ENV NGINX_VERSION=1.21.3
# releases can be signed by any key on this page https://nginx.org/en/pgp_keys.html
# so this might need to be updated for a new release
# available keys: mdounin, maxim, sb
# the "signing key" is used for linux packages, see https://trac.nginx.org/nginx/ticket/205
ENV PGP_SIGNING_KEY_OWNER=mdounin

# install dependencies
RUN apk add --no-cache git libc-dev pcre-dev make gcc zlib-dev openssl-dev brotli-dev binutils gnupg

# create a builder user and group
RUN addgroup -S -g 3148 builder && adduser -D -S -G builder -u 3148 builder
RUN mkdir /build && chown builder:builder /build
WORKDIR /build
USER builder

# clone the nginx modules
RUN git clone --depth 1 https://github.com/google/ngx_brotli
RUN git clone --depth 1 https://github.com/openresty/headers-more-nginx-module

# now start the build
# get nginx source
ADD --chown=builder:builder https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz nginx.tgz
# get nginx signature file
ADD --chown=builder:builder https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc nginx.tgz.asc
# get the corresponding public key
ADD --chown=builder:builder https://nginx.org/keys/$PGP_SIGNING_KEY_OWNER.key nginx-signing.key
# import it and verify the tarball
RUN gpg --import nginx-signing.key
RUN gpg --verify nginx.tgz.asc
# all good now untar and build!
RUN tar xzf nginx.tgz
WORKDIR /build/nginx-$NGINX_VERSION
RUN ./configure \
        --prefix=/var/lib/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx.pid \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --lock-path=/run/nginx/nginx.lock \
        --http-client-body-temp-path=/var/lib/nginx/tmp/client_body \
        --http-proxy-temp-path=/var/lib/nginx/tmp/proxy \
        --http-fastcgi-temp-path=/var/lib/nginx/tmp/fastcgi \
        --user=nginx \
        --group=nginx \
        --with-threads \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_gzip_static_module \
        --with-cc-opt='-g0 -O3 -fstack-protector -flto --param=ssp-buffer-size=4 -Wformat -Werror=format-security'\
        --add-module=/build/ngx_brotli \
        --add-module=/build/headers-more-nginx-module \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && strip -s objs/nginx

USER root
RUN make install

# elabftw + nginx + php-fpm in a container
FROM alpine:3.14

# this is versioning for the container image
ENV ELABIMG_VERSION 3.0.3

# select elabftw tag
ARG ELABFTW_VERSION=hypernext
ENV ELABFTW_VERSION $ELABFTW_VERSION

LABEL net.elabftw.name="elabftw" \
    net.elabftw.description="Run nginx and php-fpm to serve elabftw" \
    net.elabftw.url="https://www.elabftw.net" \
    net.elabftw.vcs-url="https://github.com/elabftw/elabimg" \
    net.elabftw.elabftw-version=$ELABFTW_VERSION \
    net.elabftw.image-version=$ELABIMG_VERSION

# NGINX
# copy our nginx from the build image
COPY --from=nginx-builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=nginx-builder /etc/nginx/mime.types /etc/nginx/mime.types
COPY --from=nginx-builder /etc/nginx/fastcgi.conf /etc/nginx/fastcgi.conf

# create the nginx group and user (101:101),
# the necessary nginx dirs,
# and redirect logs to stdout/stderr for docker logs to catch
RUN addgroup -S -g 101 nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u 101 nginx \
    && mkdir -pv /var/lib/nginx/tmp/{client_body,fastcgi} /var/log/nginx/{access.log,error.log} \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
# END NGINX

# install required packages
# php8-bcmath is required to send emails via Exchange (NTLM authenticator)
# php8-gd is required by mpdf for transparent png
# php8-tokenizer and php8-xmlwriter are for dev only
# don't put line comments inside this instruction
RUN apk upgrade -U -a && apk add --no-cache \
    bash \
    brotli \
    curl \
    freetype \
    ghostscript \
    openssl \
    php8 \
    php8-bcmath \
    php8-curl \
    php8-ctype \
    php8-dev \
    php8-dom \
    php8-exif \
    php8-gd \
    php8-gettext \
    php8-fileinfo \
    php8-fpm \
    php8-json \
    php8-ldap \
    php8-mbstring \
    php8-opcache \
    php8-openssl \
    php8-pdo_mysql \
    php8-pecl-imagick \
    php8-phar \
    php8-redis \
    php8-session \
    php8-sodium \
    php8-tokenizer \
    php8-xml \
    php8-xmlwriter \
    php8-zip \
    php8-zlib \
    tzdata \
    unzip \
    yarn \
    zopfli

# add a symlink to php8
RUN ln -s /usr/bin/php8 /usr/bin/php

# S6-OVERLAY
# install s6-overlay, our init system. Workaround for different versions using TARGETPLATFORM
# platform see https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG S6_OVERLAY_VERSION=2.2.0.3
ENV S6_OVERLAY_VERSION $S6_OVERLAY_VERSION

ARG TARGETPLATFORM
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCHITECTURE=amd64; elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then ARCHITECTURE=arm; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE=aarch64; else ARCHITECTURE=amd64; fi \
    && curl -sS -L -O --output-dir /tmp/ --create-dirs "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCHITECTURE}.tar.gz" \
    && tar xzf "/tmp/s6-overlay-${ARCHITECTURE}.tar.gz" -C /
COPY ./src/services /etc/services.d
# END S6-OVERLAY

# PHP
COPY ./src/php/php.ini /etc/php8/php.ini
COPY ./src/php/php-fpm.conf /etc/php8/php-fpm.conf
COPY ./src/php/elabpool.conf /etc/php8/php-fpm.d/elabpool.conf
# END PHP

# ELABFTW
# get the tar archive for the tagged version/branch we want
ADD https://github.com/elabftw/elabftw/tarball/$ELABFTW_VERSION src.tgz
# extracted folder will be named elabftw-elabftw-0abcdef
# we only copy the strict necessary
RUN tar xzf src.tgz && mv elabftw-* src \
    && mkdir /elabftw \
    && mv src/bin /elabftw \
    && mv src/builder.js /elabftw \
    && mv src/composer.json /elabftw \
    && mv src/composer.lock /elabftw \
    && mv src/node-builder.js /elabftw \
    && mv src/package.json /elabftw \
    && mv src/src /elabftw \
    && mv src/web /elabftw \
    && mv src/yarn.lock /elabftw \
    && rm -r src src.tgz

WORKDIR /elabftw

# COMPOSER
ENV COMPOSER_HOME=/composer
COPY --from=composer:2.1.5 /usr/bin/composer /usr/bin/composer

# install php and js dependencies and build assets
# some ini settings are set on the command line to override the restrictive production ones already set
# IMPORTANT: the yarn/build step must be done before the composer/install step because a source file (advancedQuery) will be generated by yarn
# so in order for composer to take it into account, it must exist before we call the install command of composer.
RUN yarn config set network-timeout 300000 \
    && yarn install --pure-lockfile --prod \
    && yarn run buildall \
    && php -d memory_limit=256M -d allow_url_fopen=On -d open_basedir='' /usr/bin/composer install --prefer-dist --no-cache --no-progress --no-dev -a \
    && rm -rf node_modules && yarn cache clean
# END ELABFTW

# NGINX PART 2
# copy nginx config files
COPY ./src/nginx/ /etc/nginx/
# the healthcheck.sh script checks if nginx replies to requests
# the HEALTHCHECK instruction allows to show healthy/unhealthy in "docker ps" output next to the container name
HEALTHCHECK --interval=2m --timeout=5s --retries=3 CMD sh /etc/nginx/healthcheck.sh
# nginx will run on port 443
EXPOSE 443
# END NGINX PART 2

# run.sh is our entrypoint script
COPY ./src/run.sh /run.sh
RUN sed -i -e "s/%ELABIMG_VERSION%/$ELABIMG_VERSION/" \
    -e "s/%ELABFTW_VERSION%/$ELABFTW_VERSION/" \
    -e "s/%S6_OVERLAY_VERSION%/$S6_OVERLAY_VERSION/" /run.sh

# launch run.sh on container start
CMD ["/run.sh"]
