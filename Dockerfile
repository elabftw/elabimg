# Note: no need to chain the RUN commands here as it's a builder image and nothing will be kept
# build nginx with only the bare minimum of features or modules
FROM alpine:3.13 as builder

ENV NGINX_VERSION=1.21.1

# install dependencies
RUN apk add --no-cache git libc-dev pcre-dev make gcc zlib-dev openssl-dev brotli-dev binutils

# create a builder user and group
RUN addgroup -S -g 3148 builder && adduser -D -S -G builder -u 3148 builder
RUN mkdir /build && chown builder:builder /build
WORKDIR /build

# clone the nginx modules
RUN git clone --depth 1 https://github.com/google/ngx_brotli
RUN git clone --depth 1 https://github.com/openresty/headers-more-nginx-module

# now start the build
USER builder
ADD --chown=builder:builder https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz nginx.tgz
RUN tar xf nginx.tgz \
    && cd nginx-$NGINX_VERSION \
    && ./configure \
        --prefix=/var/lib/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx/nginx.pid \
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
        --add-module=/build/ngx_brotli \
        --add-module=/build/headers-more-nginx-module \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && strip objs/nginx

USER root
WORKDIR /build/nginx-$NGINX_VERSION
RUN make install

# elabftw + nginx + php-fpm in a container
FROM alpine:3.13

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx/mime.types /etc/nginx/mime.types
COPY --from=builder /etc/nginx/fastcgi.conf /etc/nginx/fastcgi.conf

RUN addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u 101 nginx \
    && mkdir -pv /var/lib/nginx/tmp/{client_body,fastcgi} /var/log/nginx/{access.log,error.log} \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

# select version or branch here
ARG ELABFTW_VERSION=hypernext
ENV ELABFTW_VERSION $ELABFTW_VERSION

# this is versioning for the container image
ARG ELABIMG_VERSION=2.6.1
ENV ELABIMG_VERSION $ELABIMG_VERSION

ARG S6_OVERLAY_VERSION=2.2.0.1
ENV S6_OVERLAY_VERSION $S6_OVERLAY_VERSION

LABEL org.label-schema.name="elabftw" \
    org.label-schema.description="Run nginx and php-fpm to serve elabftw" \
    org.label-schema.url="https://www.elabftw.net" \
    org.label-schema.vcs-url="https://github.com/elabftw/elabimg" \
    org.label-schema.version=$ELABFTW_VERSION \
    org.label-schema.maintainer="nicolas.carpi@curie.fr" \
    org.label-schema.schema-version="1.0"

# install nginx and php-fpm
# php8-gd is required by mpdf for transparent png
# coreutils has sha384sum
# php8-tokenizer and php8-xmlwriter are for dev only
# don't put line comments inside this instruction
RUN apk upgrade -U -a && apk add --no-cache \
    bash \
    brotli \
    coreutils \
    curl \
    freetype \
    ghostscript \
    git \
    openssl \
    openjdk11-jre \
    php8 \
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
    php8-pear \
    php8-pecl-imagick \
    php8-phar \
    php8-redis \
    php8-session \
    php8-zip \
    php8-zlib \
    tzdata \
    unzip \
    yarn \
    zopfli

# install s6-overlay, our init system. Workaround for different versions using TARGETPLATFORM
# platform see https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG TARGETPLATFORM
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCHITECTURE=amd64; elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then ARCHITECTURE=arm; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE=aarch64; else ARCHITECTURE=amd64; fi \
    && curl -sS -L -O --output-dir /tmp/ --create-dirs "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCHITECTURE}.tar.gz" \
    && tar xzf "/tmp/s6-overlay-${ARCHITECTURE}.tar.gz" -C /

# add a symlink to php8
RUN ln -s /usr/bin/php8 /usr/bin/php

# clone elabftw repository in /elabftw
RUN git clone --depth 1 -b $ELABFTW_VERSION https://github.com/elabftw/elabftw.git /elabftw && chown -R nginx:nginx /elabftw && rm -rf /elabftw/.git

WORKDIR /elabftw

# install composer
RUN echo "$(curl -sS https://composer.github.io/installer.sig) -" > composer-setup.php.sig \
    && curl -sS https://getcomposer.org/installer | tee composer-setup.php | sha384sum -c composer-setup.php.sig \
    && php8 composer-setup.php && rm composer-setup.php*

# install dependencies
RUN /elabftw/composer.phar install --prefer-dist --no-progress --no-dev -a && yarn config set network-timeout 300000 && yarn install --pure-lockfile --prod && yarn run buildall && rm -rf node_modules && yarn cache clean && /elabftw/composer.phar clear-cache

# nginx will run on port 443
EXPOSE 443

# conf.d is now a symlink to http.d and it fails with buildx, so we need to remove it before it can be copied
#RUN rm /etc/nginx/conf.d
# copy configuration and run script
COPY ./src/nginx/ /etc/nginx/
COPY ./src/run.sh /run.sh
COPY ./src/services /etc/services.d

# this script checks if nginx is ok
HEALTHCHECK --interval=2m --timeout=5s --retries=1 CMD sh /etc/nginx/healthcheck.sh

# start
CMD ["/run.sh"]

# define mountable directories
VOLUME /elabftw
VOLUME /ssl
VOLUME /mysql-cert
