# elabftw in docker, without sql
FROM alpine:latest
MAINTAINER Nicolas CARPi <nicolas.carpi@curie.fr>

# install nginx and php-fpm
RUN apk add --update nginx openssl php php-fpm php-mysql php-gd php-curl git unzip supervisor && rm -rf /var/cache/apk/*

# only HTTPS
EXPOSE 443

# add files
ADD ./nginx443.conf /etc/nginx/sites-available/elabftw-ssl
ADD ./nginx80.conf /etc/nginx/sites-available/default
ADD ./supervisord.conf /etc/supervisord.conf
ADD ./run.sh /run.sh

RUN chmod +x /run.sh

# elabftw
#RUN git clone --depth 1 -b master https://github.com/elabftw/elabftw.git /elabftw
RUN git clone --depth 1 -b hypernext https://github.com/elabftw/elabftw.git /elabftw

# start
CMD /run.sh && exec /usr/bin/supervisord -c /etc/supervisord.conf -n

# define mountable directories.
VOLUME ["/elabftw/uploads"]
