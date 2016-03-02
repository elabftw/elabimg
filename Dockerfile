# elabftw in docker, without sql
FROM alpine:3.3
MAINTAINER Nicolas CARPi <nicolas.carpi@curie.fr>

# install nginx and php-fpm
RUN apk add --update nginx openssl php php-pdo php-pdo_mysql php-fpm php-mysql php-gd php-curl git unzip supervisor && rm -rf /var/cache/apk/*

# elabftw
#RUN git clone --depth 1 -b master https://github.com/elabftw/elabftw.git /elabftw
RUN git clone --depth 1 -b hypernext https://github.com/elabftw/elabftw.git /elabftw

# only HTTPS
EXPOSE 443
# debug
EXPOSE 9001

# add files
ADD ./nginx-https-443.conf /etc/nginx/
ADD ./nginx-http-443.conf /etc/nginx/
ADD ./supervisord.conf /etc/supervisord.conf
ADD ./run.sh /run.sh

# start
CMD /run.sh

# define mountable directories.
VOLUME ["/elabftw/uploads"]
