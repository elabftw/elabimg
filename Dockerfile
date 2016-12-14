# elabftw in docker, without MySQL
FROM alpine:edge
MAINTAINER Nicolas CARPi <nicolas.carpi@curie.fr>

# select version or branch here
ENV ELABFTW_VERSION hypernext

# install nginx and php-fpm
RUN apk add --update openjdk8-jre nginx openssl php7 php7-openssl php7-pdo_mysql php7-fpm php7-gd php7-curl php7-zip php7-zlib php7-json php7-gettext php7-session php7-mbstring php7-phar git supervisor && rm -rf /var/cache/apk/* && ln -s /usr/bin/php7 /usr/bin/php
# install elabftw
RUN git clone --depth 1 -b $ELABFTW_VERSION https://github.com/elabftw/elabftw.git /elabftw && chown -R nginx:nginx /elabftw

WORKDIR /elabftw

# install composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php -r "if (hash_file('SHA384', 'composer-setup.php') === 'aa96f26c2b67226a324c27919f1eb05f21c248b987e6195cad9690d5c1ff713d53020a02ac8c217dbf90a7eacc9d141d') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
    && php composer-setup.php \
    && php -r "unlink('composer-setup.php');"

# install composer dependencies
RUN /elabftw/composer.phar install --no-dev

# nginx will run on port 443
EXPOSE 443

# copy configuration and run script
COPY ./src/nginx/ /etc/nginx/
COPY ./src/supervisord.conf /etc/supervisord.conf
COPY ./src/run.sh /run.sh

# start
ENTRYPOINT exec /run.sh

# define mountable directories
VOLUME /elabftw/uploads
VOLUME /ssl

LABEL org.label-schema.name="elabftw" \
    org.label-schema.description="Run nginx and php-fpm to serve elabftw" \
    org.label-schema.url="https://www.elabftw.net" \
    org.label-schema.vcs-url="https://github.com/elabftw/elabimg" \
    org.label-schema.version=$ELABFTW_VERSION \
    org.label-schema.schema-version="1.0"
