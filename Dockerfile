# elabftw in docker, without sql
FROM alpine:3.3
MAINTAINER Nicolas CARPi <nicolas.carpi@curie.fr>

# install nginx and php-fpm
RUN apk add --update nginx openssl php php-pdo php-pdo_mysql php-fpm php-mysql php-gd php-curl php-zip php-zlib php-json php-gettext git supervisor && rm -rf /var/cache/apk/*

# elabftw
#RUN git clone --depth 1 -b master https://github.com/elabftw/elabftw.git /elabftw
RUN git clone --depth 1 -b hypernext https://github.com/elabftw/elabftw.git /elabftw

# only HTTPS
EXPOSE 443

# add files
COPY ./nginx.conf /etc/nginx/
COPY ./https.conf /etc/nginx/
COPY ./http.conf /etc/nginx/
COPY ./supervisord.conf /etc/supervisord.conf
COPY ./run.sh /run.sh

# start
ENTRYPOINT /run.sh

# define mountable directories.
VOLUME ["/elabftw/uploads"]
