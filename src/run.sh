#!/bin/bash
# elabftw-docker start script for alpine-linux base image

# get env values
getEnv() {
	db_host=${DB_HOST:-localhost}
	db_name=${DB_NAME:-elabftw}
	db_user=${DB_USER:-elabftw}
	db_password=${DB_PASSWORD}
	server_name=${SERVER_NAME:-localhost}
	disable_https=${DISABLE_HTTPS:-false}
    enable_letsencrypt=${ENABLE_LETSENCRYPT:-false}
	secret_key=${SECRET_KEY}
    max_php_memory=${MAX_PHP_MEMORY:-256M}
    max_upload_size=${MAX_UPLOAD_SIZE:-100M}
    php_timezone=${PHP_TIMEZONE:-Europe/Paris}
    set_real_ip=${SET_REAL_IP:-false}
    set_real_ip_from=${SET_REAL_IP_FROM:-192.168.31.48}
    php_max_children=${PHP_MAX_CHILDREN:-50}
}

# fullchain.pem and privkey.pem should be in a volume linked to /ssl
generateCert() {
    if [ ! -f /etc/nginx/certs/server.crt ]; then

        # here we generate a random CN because of this bug:
        # https://bugzilla.redhat.com/show_bug.cgi?id=1204670
        # https://bugzilla.mozilla.org/show_bug.cgi?id=1056341
        # this way there is no more hangs
        randcn=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
        openssl req \
            -new \
            -newkey rsa:4096 \
            -days 9999 \
            -nodes \
            -x509 \
            -subj "/C=FR/ST=France/L=Paris/O=elabftw/CN=$randcn" \
            -keyout /etc/nginx/certs/server.key \
            -out /etc/nginx/certs/server.crt
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
        sh /etc/nginx/generate-dhparam.sh
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
    # remove the listen on IPv6 found in the default server conf file
    sed -i -e "s/listen \[::\]:80/#listen \[::\]:80/" /etc/nginx/conf.d/default.conf

    # SET REAL IP CONFIG
    if ($set_real_ip); then
        # read the IP addresses from env
        IFS=', ' read -r -a ip_arr <<< "${set_real_ip_from}"
        conf_string=""
        for element in "${ip_arr[@]}"
        do
            conf_string+="set_real_ip_from ${element};"
        done
        sed -i -e "s/#REAL_IP_CONF/${conf_string}/" /etc/nginx/common.conf
        # enable real_ip_header config
        sed -i -e "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/common.conf
    fi
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
    sed -i -e "s/pm.max_children = 5/pm.max_children = ${php_max_children}/g" /etc/php7/php-fpm.d/www.conf
    # allow using more memory
    sed -i -e "s/;php_admin_value\[memory_limit\] = 32M/php_admin_value\[memory_limit\] = ${max_php_memory}/" /etc/php7/php-fpm.d/www.conf
}

phpConf() {
	# php config
	sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php7/php.ini
	sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = ${max_upload_size}/g" /etc/php7/php.ini
	sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php7/php.ini
    # we want a safe cookie/session
    sed -i -e "s/session.cookie_httponly =/session.cookie_httponly = true/" /etc/php7/php.ini
    sed -i -e "s/;session.cookie_secure\s*=/session.cookie_secure = true/" /etc/php7/php.ini
    sed -i -e "s/session.use_strict_mode\s*=\s*0/session.use_strict_mode = 1/" /etc/php7/php.ini
	# the sessions are stored in a separate dir
	sed -i -e "s:;session.save_path = \"/tmp\":session.save_path = \"/sessions\":" /etc/php7/php.ini
	mkdir -p /sessions
	chown nginx:nginx /sessions
    chmod 700 /sessions
    # disable url_fopen http://php.net/allow-url-fopen
    sed -i -e "s/allow_url_fopen = On/allow_url_fopen = Off/" /etc/php7/php.ini
    # enable opcache
    sed -i -e "s/;opcache.enable=1/opcache.enable=1/" /etc/php7/php.ini
    # config for timezone, use : because timezone will contain /
    sed -i -e "s:;date.timezone =:date.timezone = $php_timezone:" /etc/php7/php.ini
    # enable open_basedir to restrict PHP's ability to read files
    # use # for separator because we cannot use : ; / or _
    sed -i -e "s#;open_basedir =#open_basedir = /elabftw/:/tmp/#" /etc/php7/php.ini
    # use longer session id length
    sed -i -e "s/session.sid_length = 26/session.sid_length = 42/" /etc/php7/php.ini
    # disable some dangerous functions that we don't use
    sed -i -e "s/disable_functions =/disable_functions = php_uname, getmyuid, getmypid, passthru, leak, listen, diskfreespace, tmpfile, link, ignore_user_abord, shell_exec, dl, set_time_limit, system, highlight_file, source, show_source, fpaththru, virtual, posix_ctermid, posix_getcwd, posix_getegid, posix_geteuid, posix_getgid, posix_getgrgid, posix_getgrnam, posix_getgroups, posix_getlogin, posix_getpgid, posix_getpgrp, posix_getpid, posix_getppid, posix_getpwnam, posix_getpwuid, posix_getrlimit, posix_getsid, posix_getuid, posix_isatty, posix_kill, posix_mkfifo, posix_setegid, posix_seteuid, posix_setgid, posix_setpgid, posix_setsid, posix_setuid, posix_times, posix_ttyname, posix_uname, proc_open, proc_close, proc_get_status, proc_nice, proc_terminate, phpinfo/" /etc/php7/php.ini

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
	echo "$config" > /elabftw/config.php
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
