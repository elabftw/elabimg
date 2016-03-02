#!/bin/sh
# elabftw-docker start script

# write config file from env var
db_host=${DB_HOST}
db_name=${DB_NAME:-elabftw}
db_user=${DB_USER:-elabftw}
db_password=${DB_PASSWORD}
server_name=${SERVER_NAME:-localhost}
disable_https=${DISABLE_HTTPS:-false}
new_secret_key=$(php /elabftw/install/generateSecretKey.php)
secret_key=${SECRET_KEY:-$new_secret_key}

cat << EOF > /elabftw/config.php
<?php
define('DB_HOST', '${db_host}');
define('DB_NAME', '${db_name}');
define('DB_USER', '${db_user}');
define('DB_PASSWORD', '${db_password}');
define('ELAB_ROOT', '/elabftw/');
define('SECRET_KEY', '${secret_key}');
EOF

# remove the default config file
rm /etc/nginx/nginx.conf

# Switch http or https
# false by default
if ($disable_https); then
    # activate an HTTP server listening on port 443
    ln -s /etc/nginx/nginx-http-443.conf /etc/nginx/nginx.conf
else
    # generate self-signed certificates for nginx server
    mkdir -p /etc/nginx/certs

    if [ ! -f /etc/nginx/certs/server.crt ]; then
        openssl req \
            -new \
            -newkey rsa:4096 \
            -days 9999 \
            -nodes \
            -x509 \
            -subj "/C=FR/ST=France/L=Paris/O=elabftw/CN=www.example.com" \
            -keyout /etc/nginx/certs/server.key \
            -out /etc/nginx/certs/server.crt
    fi

    # generate Diffie-Hellman parameter for DHE ciphersuites
    if [ ! -f /etc/nginx/certs/dhparam.pem ]; then
        openssl dhparam -outform PEM -out /etc/nginx/certs/dhparam.pem 2048
    fi

    # activate an HTTPS server listening on port 443
    ln -s /etc/nginx/nginx-https-443.conf /etc/nginx/nginx.conf
fi

# nginx config
sed -i -e "s/localhost/$server_name/" /etc/nginx/nginx.conf

# php-fpm config
sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php/php-fpm.conf
sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php/php-fpm.conf
sed -i -e "s;listen = 127.0.0.1:9000;listen = /var/run/php-fpm.sock;g" /etc/php/php-fpm.conf
sed -i -e "s/;listen.owner = nobody/listen.owner = nginx/g" /etc/php/php-fpm.conf
sed -i -e "s/;listen.group = nobody/listen.group = nginx/g" /etc/php/php-fpm.conf

# php config
sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/php.ini
sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php/php.ini
sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php/php.ini

# elabftw
mkdir -p /elabftw/uploads/tmp
chmod -R 755 /elabftw/uploads
chown -R nginx:nginx /elabftw
chmod -R u+x /elabftw/*

# start all the services
/usr/bin/supervisord -c /etc/supervisord.conf -n
