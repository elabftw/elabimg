#!/bin/bash
# elabftw-docker start script

# generate self-signed certificates for nginx server
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

# write config file from env var
db_host=$(grep mysql /etc/hosts | awk '{print $1}')
if [ -z "$db_host" ]; then
    db_host=${DB_HOST}
fi
db_name=${DB_NAME:-elabftw}
db_user=${DB_USER:-elabftw}
db_password=${DB_PASSWORD}
elab_root='/elabftw/'
server_name=${SERVER_NAME:-localhost}
disable_https=${DISABLE_HTTPS:-false}

cat << EOF > /elabftw/config.php
<?php
define('DB_HOST', '${db_host}');
define('DB_NAME', '${db_name}');
define('DB_USER', '${db_user}');
define('DB_PASSWORD', '${db_password}');
define('ELAB_ROOT', '${elab_root}');
EOF

# nginx config
echo "daemon off;" >> /etc/nginx/nginx.conf
sed -i -e "s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf
sed -i -e "s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf
# remove the default site
#rm /etc/nginx-sites-enabled/default

# false by default
if ($disable_https); then
    # put the right server_name
    sed -i -e "s/localhost/$server_name/" /etc/nginx/sites-available/elabftw-no-ssl
    # activate an HTTP server listening on port 443
    ln -s /etc/nginx/sites-available/elabftw-no-ssl /etc/nginx/sites-enabled/elabftw-no-ssl
    # now we need to disable the checks in elab

else
    # put the right server_name
    sed -i -e "s/localhost/$server_name/" /etc/nginx/sites-available/elabftw-ssl
    # activate an HTTPS server listening on port 443
    ln -s /etc/nginx/sites-available/elabftw-ssl /etc/nginx/sites-enabled/elabftw-ssl
fi

# php-fpm config
sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php5/fpm/php.ini
sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php5/fpm/php-fpm.conf
sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php5/fpm/pool.d/www.conf

# elabftw
mkdir -p /elabftw/uploads/tmp
chmod -R 777 /elabftw/uploads
chown -R www-data:www-data /elabftw
chmod -R u+x /elabftw/*

# start all the services
/usr/bin/supervisord -c /etc/supervisord.conf -n
