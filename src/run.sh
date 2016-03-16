#!/bin/sh
# elabftw-docker start script for alpine-linux base image

# get env values
getEnv() {
	db_host=${DB_HOST}
	db_name=${DB_NAME:-elabftw}
	db_user=${DB_USER:-elabftw}
	db_password=${DB_PASSWORD}
	server_name=${SERVER_NAME:-localhost}
	disable_https=${DISABLE_HTTPS:-false}
	secret_key=${SECRET_KEY}
}

# generate self-signed certificates for nginx server
generateCerts() {
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
        openssl dhparam -out /etc/nginx/certs/dhparam.pem 2048
    fi
}

nginxConf() {
	# Switch http or https
	# false by default
	if ($disable_https); then
		# activate an HTTP server listening on port 443
		ln -s /etc/nginx/http.conf /etc/nginx/conf.d/elabftw.conf
	else
		generateCerts
		# activate an HTTPS server listening on port 443
		ln -s /etc/nginx/https.conf /etc/nginx/conf.d/elabftw.conf
	fi

	# fix the server name in nginx config
	sed -i -e "s/localhost/$server_name/" /etc/nginx/conf.d/elabftw.conf
    # fix upload permissions
    chown -R nginx:nginx /var/lib/nginx
}

phpfpmConf() {
	# php-fpm config
	sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php7/php-fpm.conf
	sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php7/php-fpm.d/www.conf
	# use a unix socket
	sed -i -e "s;listen = 127.0.0.1:9000;listen = /var/run/php-fpm.sock;g" /etc/php7/php-fpm.d/www.conf
	sed -i -e "s/;listen.owner = nobody/listen.owner = nginx/g" /etc/php7/php-fpm.d/www.conf
	sed -i -e "s/;listen.group = nobody/listen.group = nginx/g" /etc/php7/php-fpm.d/www.conf
}

phpConf() {
	# php config
	sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php7/php.ini
	sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php7/php.ini
	sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php7/php.ini
	# the sessions are stored in a separate dir
	sed -i -e "s;session.save_path = \"/tmp\";session.save_path = \"/sessions\";g" /etc/php7/php.ini
	mkdir -p /sessions
	chown nginx:nginx /sessions
}

elabftwConf() {
	mkdir -p /elabftw/uploads/tmp
	chmod -R 777 /elabftw/uploads
	chown -R nginx:nginx /elabftw
	chmod -R u+x /elabftw/*
}

writeConfigFile() {
	# write config file from env var
	config="<?php
	define('DB_HOST', '${db_host}');
	define('DB_NAME', '${db_name}');
	define('DB_USER', '${db_user}');
	define('DB_PASSWORD', '${db_password}');
	define('ELAB_ROOT', '/elabftw/');
	define('SECRET_KEY', '${secret_key}');"
	echo $config > /elabftw/config.php
}

# script start
getEnv
nginxConf
phpfpmConf
phpConf
elabftwConf
writeConfigFile

# start all the services
/usr/bin/supervisord -c /etc/supervisord.conf -n
