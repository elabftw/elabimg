# Dockerfile for elabftw web container
# nginx custom + php-fpm + elabftw complete production files
# https://github.com/elabftw/elabimg

FROM golang:1.22-alpine3.21 AS invoker-builder
# using an explicit default argument for TARGETPLATFORM will override the buildx implicit value
ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}
WORKDIR /app
COPY src/invoker .
# allow building for ARM, disable CGO to have full static build, target linux, add -s and -w ldflags to remove debug symbols
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCH=amd64; elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then ARCH=arm; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCH=arm64; else ARCH=amd64; fi \
    && CGO_ENABLED=0 GOOS=linux GOARCH=$ARCH go build -ldflags="-s -w" -o invoker

# build nginx with only the bare minimum of features or modules
# Note: no need to chain the RUN commands here as it's a builder image and nothing will be kept
FROM alpine:3.21 AS nginx-builder

ENV NGINX_VERSION=1.26.2
# pin nginx modules versions
# see https://github.com/google/ngx_brotli/issues/120 for the lack of tags
# BROKEN HASH: ENV NGX_BROTLI_COMMIT_HASH=63ca02abdcf79c9e788d2eedcc388d2335902e52
ENV NGX_BROTLI_COMMIT_HASH=6e975bcb015f62e1f303054897783355e2a877dc
# https://github.com/openresty/headers-more-nginx-module/tags
ENV HEADERS_MORE_VERSION=v0.37
# releases can be signed by any key on this page https://nginx.org/en/pgp_keys.html
# so this might need to be updated for a new release
# available keys: mdounin, maxim, sb, thresh
# the "signing key" is used for linux packages, see https://trac.nginx.org/nginx/ticket/205
# do not use KEY in the env name to avoid warning by getSecretsRegex() from buildkit
ENV PGP_SIGNING_PUBK_OWNER=thresh

# install dependencies: here we use brotli-dev, newer brotli versions we can remove that and build it
RUN apk add --no-cache git libc-dev pcre2-dev make gcc zlib-dev openssl-dev binutils gnupg cmake brotli-dev

# create a builder user and group
RUN addgroup -S -g 3148 builder && adduser -D -S -G builder -u 3148 builder
RUN mkdir /build && chown builder:builder /build
WORKDIR /build
USER builder

# clone the nginx modules
# NEW broken brotli code
#RUN git clone --recurse-submodules  --depth 25 https://github.com/google/ngx_brotli && cd ngx_brotli && git reset --hard $NGX_BROTLI_COMMIT_HASH && cd deps/brotli && mkdir out && cd out && \
#    cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-Ofast -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_CXX_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_INSTALL_PREFIX=./installed .. && \
#    cmake --build . --config Release --target brotlienc
# OLD working brotli stuff
# removed the depth param
RUN git clone https://github.com/google/ngx_brotli && cd ngx_brotli && git reset --hard $NGX_BROTLI_COMMIT_HASH && cd ..
RUN git clone --depth 1 -b $HEADERS_MORE_VERSION https://github.com/openresty/headers-more-nginx-module

# now start the build
# get nginx source
ADD --chown=builder:builder https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz nginx.tgz
# get nginx signature file
ADD --chown=builder:builder https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc nginx.tgz.asc
# get the corresponding public key
ADD --chown=builder:builder https://nginx.org/keys/$PGP_SIGNING_PUBK_OWNER.key nginx-signing.key
# import it and verify the tarball
RUN gpg --import nginx-signing.key
# only run on amd64 because it fails on arm64 for some weird unknown reason
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then gpg --verify nginx.tgz.asc; fi
# all good now untar and build!
RUN tar xzf nginx.tgz
WORKDIR /build/nginx-$NGINX_VERSION
# Compilation flags
# -g0: Disable debugging symbols generation (decreases binary size)
# -O3: Enable aggressive optimization level 3 (improves code execution speed)
# -fstack-protector-strong: Enable stack protection mechanisms (prevents stack-based buffer overflows)
# -flto: Enable Link Time Optimization (LTO) (allows cross-source-file optimization)
# -pie: Generate position-independent executables (PIE) (enhances security)
# --param=ssp-buffer-size=4: Set the size of the stack buffer for stack smashing protection to 4 bytes
# -Wformat -Werror=format-security: Enable warnings for potentially insecure usage of format strings (treats them as errors)
# -D_FORTIFY_SOURCE=2: Enable additional security features provided by fortified library functions
# -Wl,-z,relro,-z,now: Enforce memory protections at runtime:
#    - Mark the Global Offset Table (GOT) as read-only after relocation
#    - Resolve all symbols at load time, making them harder to manipulate
# -Wl,-z,noexecstack: Mark the stack as non-executable (prevents execution of code placed on the stack)
# -fPIC: Generate position-independent code (PIC) (suitable for building shared libraries)
RUN ./configure \
        --prefix=/var/lib/nginx \
        --sbin-path=/usr/sbin/nginx \
        --with-cc-opt='-g0 -O3 -fstack-protector-strong -flto -pie --param=ssp-buffer-size=4 -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2 -Wl,-z,relro,-z,now -Wl,-z,noexecstack -fPIC'\
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx.pid \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --lock-path=/run/nginx.lock \
        --http-client-body-temp-path=/run/nginx-client_body \
        --http-fastcgi-temp-path=/run/nginx-fastcgi \
        --user=nginx \
        --group=nginx \
        --with-threads \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
        --add-module=/build/ngx_brotli \
        --add-module=/build/headers-more-nginx-module \
        --without-http_autoindex_module \
        --without-http_browser_module \
        --without-http_empty_gif_module \
        --without-http_geo_module \
        --without-http_limit_conn_module \
        --without-http_limit_req_module \
        --without-http_map_module \
        --without-http_memcached_module \
        --without-http_referer_module \
        --without-http_scgi_module \
        --without-http_split_clients_module \
        --without-http_ssi_module \
        --without-http_upstream_ip_hash_module \
        --without-http_userid_module \
        --without-http_uwsgi_module \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && strip -s objs/nginx

USER root
RUN make install

# CRONIE BUILDER
FROM alpine:3.21 AS cronie-builder
ENV CRONIE_VERSION=1.5.7
# install dependencies
RUN apk add --no-cache build-base libc-dev make gcc autoconf automake abuild musl-obstack-dev
# create a builder user and add it to abuild group so it can build packages
RUN adduser -D -G abuild builder
RUN mkdir /build && chown builder:abuild /build
WORKDIR /build
USER builder
COPY ./src/cron/APKBUILD .
# generate a RSA key, non-interactive and append to config file
RUN abuild-keygen -n -a
# move the key in that folder so it is trusted
USER root
RUN cp /home/builder/.abuild/*.pub /etc/apk/keys
USER builder
# we use find because the package will end up in an arch specific dir (x86_64, arm, ...)
# and this way it'll work every time
# we move it to /build so it's easier to find from the other image
# use cronie-1 to avoid copying cronie-doc
RUN abuild && find /home/builder/packages -type f -name 'cronie-1*.apk' -exec mv {} /build/apk \;
# END CRONIE BUILDER

#############################
# ELABFTW + NGINX + PHP-FPM #
#############################
FROM alpine:3.21

# this is versioning for the container image
ENV ELABIMG_VERSION=5.5.0

# the target elabftw version is passed with --build-arg
# it is a mandatory ARG
ARG ELABFTW_VERSION

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

# create the log folder and make the logfiles links to stdout/stderr so docker logs will catch it
RUN mkdir -p /var/log/nginx \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
# END NGINX

# install required packages
# php8-bcmath is required to send emails via Exchange (NTLM authenticator)
# php8-gd is required by mpdf for transparent png
# php8-tokenizer and php8-xmlwriter are for dev only
# php8-iconv is required by LdapRecord php library
# git is required by yarn
# imagemagick-svg is for mathjax support in pdfs
# don't put line comments inside this instruction
RUN apk upgrade -U -a && apk add --no-cache \
    bash \
    brotli \
    curl \
    freetype \
    ghostscript \
    git \
    imagemagick-svg \
    nodejs-current \
    openssl \
    php84 \
    php84-pecl-apcu \
    php84-bcmath \
    php84-curl \
    php84-ctype \
    php84-dev \
    php84-dom \
    php84-exif \
    php84-gd \
    php84-gettext \
    php84-fileinfo \
    php84-fpm \
    php84-iconv \
    php84-json \
    php84-intl \
    php84-ldap \
    php84-mbstring \
    php84-opcache \
    php84-openssl \
    php84-pdo_mysql \
    php84-pecl-imagick \
    php84-phar \
    php84-redis \
    php84-simplexml \
    php84-session \
    php84-sodium \
    php84-tokenizer \
    php84-xml \
    php84-xmlwriter \
    php84-zip \
    php84-zlib \
    tzdata \
    unzip \
    zopfli

# add a symlink to php8
RUN mv /usr/bin/php84 /usr/bin/php-real
COPY ./src/php/phpwithenv /usr/bin/php84
RUN ln -f /usr/bin/php84 /usr/bin/php

# S6-OVERLAY
# install s6-overlay, our init system. Workaround for different versions using TARGETPLATFORM
# platform see https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG S6_OVERLAY_VERSION=3.2.0.0
ENV S6_OVERLAY_VERSION=$S6_OVERLAY_VERSION

# using an explicit default argument for TARGETPLATFORM will override the buildx implicit value
ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCHITECTURE=x86_64; elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then ARCHITECTURE=arm; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE=aarch64; else ARCHITECTURE=amd64; fi \
    && curl -sS -L -O --output-dir /tmp/ --create-dirs "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCHITECTURE}.tar.xz" \
    && curl -sS -L -O --output-dir /tmp/ --create-dirs "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    && tar xpJf "/tmp/s6-overlay-${ARCHITECTURE}.tar.xz" -C / \
    && tar xpJf "/tmp/s6-overlay-noarch.tar.xz" -C / \
    && rm /tmp/s6-overlay*
# create nginx s6 service
RUN mkdir -p /etc/s6-overlay/s6-rc.d/nginx && echo "longrun" > /etc/s6-overlay/s6-rc.d/nginx/type
COPY ./src/nginx/run /etc/s6-overlay/s6-rc.d/nginx/
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/nginx
# create php s6 service
RUN mkdir -p /etc/s6-overlay/s6-rc.d/php && echo "longrun" > /etc/s6-overlay/s6-rc.d/php/type
COPY ./src/php/run /etc/s6-overlay/s6-rc.d/php/
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/php
# create cron s6 service
RUN mkdir -p /etc/s6-overlay/s6-rc.d/cron && echo "longrun" > /etc/s6-overlay/s6-rc.d/cron/type
COPY ./src/cron/run /etc/s6-overlay/s6-rc.d/cron/
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/cron
# END S6-OVERLAY

# PHP
COPY ./src/php/php.ini /etc/php84/php.ini
COPY ./src/php/php-fpm.conf /etc/php84/php-fpm.conf
COPY ./src/php/elabpool.conf /etc/php84/php-fpm.d/elabpool.conf
# END PHP

# ELABFTW
# get the tar archive for the tagged version/branch we want
ADD https://github.com/elabftw/elabftw/tarball/$ELABFTW_VERSION src.tgz
# extracted folder will be named elabftw-elabftw-0abcdef
# we only copy the strict necessary
RUN tar xzf src.tgz && mv elabftw-* src \
    && mkdir /elabftw \
    && mv src/bin /elabftw \
    && mv src/.babelrc /elabftw \
    && mv src/builder.js /elabftw \
    && mv src/composer.json /elabftw \
    && mv src/composer.lock /elabftw \
    && mv src/node-builder.js /elabftw \
    && mv src/package.json /elabftw \
    && mv src/src /elabftw \
    && mv src/web /elabftw \
    && mv src/yarn.lock /elabftw \
    && mv src/.yarnrc.yml /elabftw \
    && rm -r src src.tgz

WORKDIR /elabftw

# COMPOSER
ENV COMPOSER_HOME=/composer
COPY --from=composer:2.8.3 /usr/bin/composer /usr/bin/composer

# this allows to skip the (long) build in dev mode where /elabftw will be bind-mounted anyway
# pass it to build command with --build-arg BUILD_ALL=0
ARG BUILD_ALL=1
# install php and js dependencies and build assets
# avoid installing cypress
ENV CYPRESS_INSTALL_BINARY=0
# avoid download prompt
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
# enable new yarn
RUN corepack enable
# some ini settings are set on the command line to override the restrictive production ones already set
# IMPORTANT: the yarn/build step must be done before the composer/install step because a source file (advancedQuery) will be generated by yarn
# so in order for composer to take it into account, it must exist before we call the install command of composer.
RUN if [ "$BUILD_ALL" = "1" ]; then yarn install \
    && yarn run buildall:prod \
    && /usr/bin/php84 -d memory_limit=256M -d open_basedir='' /usr/bin/composer install --prefer-dist --no-cache --no-progress --no-dev -a \
    && yarn cache clean && rm -r /root/.cache /root/.yarn; fi
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

# ENTRYPOINT
# create a oneshot service
RUN mkdir -p /etc/s6-overlay/s6-rc.d/entrypoint && echo "oneshot" > /etc/s6-overlay/s6-rc.d/entrypoint/type
COPY ./src/entrypoint/up /etc/s6-overlay/s6-rc.d/entrypoint/
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/entrypoint

# docker-entrypoint.sh must run before nginx, php and cron are started
RUN echo "entrypoint" > /etc/s6-overlay/s6-rc.d/nginx/dependencies
RUN echo "entrypoint" > /etc/s6-overlay/s6-rc.d/php/dependencies
RUN echo "entrypoint" > /etc/s6-overlay/s6-rc.d/cron/dependencies

COPY ./src/entrypoint/docker-entrypoint.sh /usr/sbin/docker-entrypoint.sh
# these values are not in env and cannot be accessed by script so modify them here
RUN sed -i -e "s/%ELABIMG_VERSION%/$ELABIMG_VERSION/" \
    -e "s/%ELABFTW_VERSION%/$ELABFTW_VERSION/" \
    -e "s/%S6_OVERLAY_VERSION%/$S6_OVERLAY_VERSION/" /usr/sbin/docker-entrypoint.sh
# END DOCKER-ENTRYPOINT.SH

# CRONIE
COPY --from=cronie-builder --chown=root:root /build/apk /tmp/cronie.apk
COPY --from=cronie-builder --chown=root:root /home/builder/.abuild/*.pub /etc/apk/keys
RUN apk add /tmp/cronie.apk && rm /tmp/cronie.apk
COPY ./src/cron/cronjob /etc/elabftw-cronjob
COPY ./src/cron/cron.allow /etc/cron.d/cron.allow
# END CRONIE

# INVOKER
COPY --from=invoker-builder /app/invoker /usr/bin/invoker
RUN chmod +x /usr/bin/invoker

# add a helper script to reload services easily
COPY ./src/entrypoint/reload.sh /usr/bin/reload
RUN chmod 700 /usr/bin/reload

# this is unique to the build and is better than the previously used elabftw version for asset cache busting
RUN sed -i -e "s/%ELABIMG_BUILD_ID%/$(openssl rand -hex 4)/" /etc/php84/php-fpm.d/elabpool.conf
# this file contains secrets
RUN chmod 400 /etc/php84/php-fpm.d/elabpool.conf

# start s6
ENTRYPOINT ["/init"]
