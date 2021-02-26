# elabftw + nginx + php-fpm in a container
FROM alpine:3.13

# select version or branch here
ENV ELABFTW_VERSION hypernext

# this is versioning for the container image
ENV ELABIMG_VERSION 2.4.0

ENV S6_OVERLAY_VERSION 2.2.0.1

# the architecture to build for, necessary for S6
ENV ARCHITECTURE=$arch

LABEL org.label-schema.name="elabftw" \
    org.label-schema.description="Run nginx and php-fpm to serve elabftw" \
    org.label-schema.url="https://www.elabftw.net" \
    org.label-schema.vcs-url="https://github.com/elabftw/elabimg" \
    org.label-schema.version=$ELABFTW_VERSION \
    org.label-schema.maintainer="nicolas.carpi@curie.fr" \
    org.label-schema.schema-version="1.0"

# install s6-overlay, our init system
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCHITECTURE}.tar.gz /tmp/
RUN tar xzf /tmp/s6-overlay-${ARCHITECTURE}.tar.gz -C /

# install nginx and php-fpm
# php8-gd is required by mpdf for transparent png
# coreutils has sha384sum
# php8-tokenizer and php8-xmlwriter are for dev only
# don't put line comments inside this instruction
RUN apk upgrade -U -a && apk add --no-cache \
    bash \
    coreutils \
    curl \
    freetype \
    ghostscript \
    git \
    openssl \
    nginx \
    openjdk8-jre \
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
    php8-phar \
    php8-redis \
    php8-session \
    php8-zip \
    php8-zlib \
    tzdata \
    unzip \
    yarn

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
RUN /elabftw/composer.phar install --prefer-dist --no-progress --no-dev -a && yarn config set network-timeout 300000 && yarn install --pure-lockfile && yarn run buildall && rm -rf node_modules && yarn cache clean && /elabftw/composer.phar clear-cache

# redirect nginx logs to stout and stderr
RUN ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log

# nginx will run on port 443
EXPOSE 443

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
