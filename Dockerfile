# elabftw in docker, without sql
FROM ubuntu:14.04
MAINTAINER Nicolas CARPi <nicolas.carpi@curie.fr>

# uncomment for dev build in behind curie proxy
#ADD ./50proxy /etc/apt/apt.conf.d/50proxy
#ENV http_proxy http://www-cache.curie.fr:3128
#ENV https_proxy https://www-cache.curie.fr:3128


# install nginx and php-fpm
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx \
    openssl \
    php5-fpm \
    php5-mysql \
    php-apc \
    php5-gd \
    php5-curl \
    php5-cli \
    curl \
    git \
    unzip \
    supervisor && \
    rm -rf /var/lib/apt/lists/*

# only HTTPS
EXPOSE 443

# add files
ADD ./nginx443.conf /etc/nginx/sites-available/elabftw-ssl
ADD ./nginx80.conf /etc/nginx/sites-available/default
ADD ./supervisord.conf /etc/supervisord.conf
ADD ./start.sh /start.sh

# elabftw
#RUN git clone --depth 1 -b master https://github.com/elabftw/elabftw.git /elabftw
RUN git clone --depth 1 -b hypernext https://github.com/elabftw/elabftw.git /elabftw

# start
CMD ["/start.sh"]

# define mountable directories.
VOLUME ["/var/log/nginx", "/elabftw/uploads"]
