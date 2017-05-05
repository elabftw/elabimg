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
    enable_letsencrypt=${ENABLE_LETSENCRYPT:-false}
	secret_key=${SECRET_KEY}
}

# fullchain.pem and privkey.pem should be in a volume linked to /ssl
generateCert() {
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
}

# generate Diffie-Hellman parameter for DHE ciphersuites
generateDh() {
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
        mkdir -p /etc/nginx/certs
        # generate a selfsigned certificate if we don't use Let's Encrypt
        if (! $enable_letsencrypt); then
            generateCert
        fi
        generateDh
		# activate an HTTPS server listening on port 443
		ln -s /etc/nginx/https.conf /etc/nginx/conf.d/elabftw.conf
        if ($enable_letsencrypt); then
            mkdir -p /ssl
            sed -i -e "s:CERT_PATH:/ssl/live/localhost/fullchain.pem:" /etc/nginx/conf.d/elabftw.conf
            sed -i -e "s:KEY_PATH:/ssl/live/localhost/privkey.pem:" /etc/nginx/conf.d/elabftw.conf
        else
            sed -i -e "s:CERT_PATH:/etc/nginx/certs/server.crt:" /etc/nginx/conf.d/elabftw.conf
            sed -i -e "s:KEY_PATH:/etc/nginx/certs/server.key:" /etc/nginx/conf.d/elabftw.conf
        fi
	fi
	# set the server name in nginx config
    # works also for the ssl config if ssl is enabled
	sed -i -e "s/localhost/$server_name/g" /etc/nginx/conf.d/elabftw.conf
    # fix upload permissions
    chown -R nginx:nginx /var/lib/nginx
}

phpfpmConf() {
	# php-fpm config
	sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php7/php-fpm.conf
	sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php7/php-fpm.d/www.conf
    # hide php version
	sed -i -e "s/expose_php = On/expose_php = Off/g" /etc/php7/php.ini
	# use a unix socket
	sed -i -e "s;listen = 127.0.0.1:9000;listen = /var/run/php-fpm.sock;g" /etc/php7/php-fpm.d/www.conf
    # set nginx as user for php-fpm
	sed -i -e "s/;listen.owner = nobody/listen.owner = nginx/g" /etc/php7/php-fpm.d/www.conf
	sed -i -e "s/;listen.group = nobody/listen.group = nginx/g" /etc/php7/php-fpm.d/www.conf
    sed -i -e "s/nobody/nginx/g" /etc/php7/php-fpm.d/www.conf
    # increase max number of simultaneous requests
    sed -i -e "s/pm.max_children = 5/pm.max_children = 50/g" /etc/php7/php-fpm.d/www.conf
    # allow using more memory
    sed -i -e "s/;php_admin_value[memory_limit] = 32M/php_admin_value[memory_limit] = 256M/" /etc/php7/php-fpm.d/www.conf
}

phpConf() {
	# php config
	sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php7/php.ini
	sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php7/php.ini
	sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php7/php.ini
    # we want a safe cookie/session
    sed -i -e "s/session.cookie_httponly\s*=/session.cookie_httponly = true/" /etc/php7/php.ini
    sed -i -e "s/;session.cookie_secure\s*=/session.cookie_secure = true/" /etc/php7/php.ini
    sed -i -e "s/session.use_strict_mode\s*=\s*0/session.use_strict_mode = 1/" /etc/php7/php.ini
	# the sessions are stored in a separate dir
	sed -i -e "s;session.save_path = \"/tmp\";session.save_path = \"/sessions\";g" /etc/php7/php.ini
	mkdir -p /sessions
    # enable opcache
    sed -i -e "s/;opcache.enable=1/opcache.enable=1/" /etc/php7/php.ini
	chown nginx:nginx /sessions
}

elabftwConf() {
	mkdir -p /elabftw/uploads/tmp
	chmod 777 /elabftw/uploads
    chmod 777 /elabftw/uploads/tmp
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
    chown nginx:nginx /elabftw/config.php
    chmod 700 /elabftw/config.php
}

# because a global variable is not the best place for a secret value...
unsetEnv() {
	unset DB_HOST
	unset DB_NAME
	unset DB_USER
	unset DB_PASSWORD
	unset SERVER_NAME
	unset DISABLE_HTTPS
    unset ENABLE_LETSENCRYPT
	unset SECRET_KEY
}

# script start
getEnv
nginxConf
phpfpmConf
phpConf
elabftwConf
writeConfigFile
unsetEnv

# start all the services
/usr/bin/supervisord -c /etc/supervisord.conf -n
