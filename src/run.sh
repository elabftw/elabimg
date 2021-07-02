#!/bin/bash
# elabftw-docker start script for alpine-linux base image

# get env values
getEnv() {
    db_host=${DB_HOST:-localhost}
    db_port=${DB_PORT:-3306}
    db_name=${DB_NAME:-elabftw}
    db_user=${DB_USER:-elabftw}
    db_password=${DB_PASSWORD}
    db_cert_path=${DB_CERT_PATH:-}
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
    elabimg_version=${ELABIMG_VERSION:-0.0.0}
    php_max_execution_time=${PHP_MAX_EXECUTION_TIME:-120}
    use_redis=${USE_REDIS:-false}
    redis_host=${REDIS_HOST:-redis}
    redis_port=${REDIS_PORT:-6379}
    ipv6=${ENABLE_IPV6:-false}
    elabftw_user=${ELABFTW_USER:-nginx}
    elabftw_group=${ELABFTW_GROUP:-nginx}
    elabftw_userid=${ELABFTW_USERID:-101}
    elabftw_groupid=${ELABFTW_GROUPID:-101}
}

# Create user if not default user
createUser() {
    if [ "${elabftw_user}" != "nginx" ]; then
        addgroup -g "${elabftw_groupid}" "${elabftw_group}"
        adduser -S -u "${elabftw_userid}" -G "${elabftw_group}" "${elabftw_user}"
    fi
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
        ln -fs /etc/nginx/http.conf /etc/nginx/conf.d/elabftw.conf
    else
        mkdir -p /etc/nginx/certs
        # generate a selfsigned certificate if we don't use Let's Encrypt
        if (! $enable_letsencrypt); then
            generateCert
        fi
        sh /etc/nginx/generate-dhparam.sh
        # activate an HTTPS server listening on port 443
        ln -fs /etc/nginx/https.conf /etc/nginx/conf.d/elabftw.conf
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
    chown -R "${elabftw_user}":"${elabftw_group}" /var/lib/nginx
    # remove the listen on IPv6 found in the default server conf file
    sed -i -e "s/listen \[::\]:80/#listen \[::\]:80/" /etc/nginx/conf.d/default.conf

    # adjust client_max_body_size
    sed -i -e "s/client_max_body_size 100m;/client_max_body_size ${max_upload_size};/" /etc/nginx/nginx.conf

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

    # IPV6 CONFIG
    if ($ipv6); then
        sed -i -e "s/#listen \[::\]:443;/listen \[::\]:443;/" /etc/nginx/conf.d/elabftw.conf
        sed -i -e "s/#listen \[::\]:443 ssl http2;/listen \[::\]:443 ssl http2;/" /etc/nginx/conf.d/elabftw.conf
    fi

    # CHANGE NGINX USER
    sed -i -e "s/#user-placeholder/user ${elabftw_user} ${elabftw_group};/" /etc/nginx/nginx.conf
}

phpfpmConf() {
    # php-fpm config
    sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php8/php-fpm.conf
    sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php8/php-fpm.d/www.conf
    # hide php version
    sed -i -e "s/expose_php = On/expose_php = Off/g" /etc/php8/php.ini
    # use a unix socket
    sed -i -e "s;listen = 127.0.0.1:9000;listen = /var/run/php-fpm.sock;g" /etc/php8/php-fpm.d/www.conf
    # set nginx as user for php-fpm
    sed -i -e "s/;listen.owner = nobody/listen.owner = ${elabftw_user}/g" /etc/php8/php-fpm.d/www.conf
    sed -i -e "s/;listen.group = nobody/listen.group = ${elabftw_group}/g" /etc/php8/php-fpm.d/www.conf
    sed -i -e "s/user = nobody/user = ${elabftw_user}/g" /etc/php8/php-fpm.d/www.conf
    sed -i -e "s/group = nobody/group = ${elabftw_group}/g" /etc/php8/php-fpm.d/www.conf
    # increase max number of simultaneous requests
    sed -i -e "s/pm.max_children = 5/pm.max_children = ${php_max_children}/g" /etc/php8/php-fpm.d/www.conf
    # allow more idle server processes
    sed -i -e "s/pm.start_servers = 2/pm.start_servers = 5/g" /etc/php8/php-fpm.d/www.conf
    sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 4/g" /etc/php8/php-fpm.d/www.conf
    sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 6/g" /etc/php8/php-fpm.d/www.conf
    # allow using more memory for php-fpm
    sed -i -e "s/;php_admin_value\[memory_limit\] = 32M/php_admin_value\[memory_limit\] = ${max_php_memory}/" /etc/php8/php-fpm.d/www.conf
    # allow using more memory for php
    sed -i -e "s/memory_limit = 128M/memory_limit = ${max_php_memory}/" /etc/php8/php.ini
    # add container version in env
    if ! grep -q ELABIMG_VERSION /etc/php8/php-fpm.d/www.conf; then
        echo "env[ELABIMG_VERSION] = ${elabimg_version}" >> /etc/php8/php-fpm.d/www.conf
    fi
}

phpConf() {
    # php config
    sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php8/php.ini
    sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = ${max_upload_size}/g" /etc/php8/php.ini
    sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = ${max_upload_size}/g" /etc/php8/php.ini
    # increase this value to allow pdf generation with big body (with base64 encoded images for instance)
    sed -i -e "s/;pcre.backtrack_limit=100000/pcre.backtrack_limit=10000000/" /etc/php8/php.ini
    # we want a safe cookie/session
    sed -i -e "s/session.cookie_httponly.*/session.cookie_httponly = true/" /etc/php8/php.ini
    sed -i -e "s/;session.cookie_secure.*/session.cookie_secure = true/" /etc/php8/php.ini
    sed -i -e "s/session.use_strict_mode.*/session.use_strict_mode = 1/" /etc/php8/php.ini
    sed -i -e "s/session.cookie_samesite.*/session.cookie_samesite = \"Strict\"/" /etc/php8/php.ini
    # set redis as session handler if requested
    if ($use_redis); then
        sed -i -e "s:session.save_handler = files:session.save_handler = redis:" /etc/php8/php.ini
        sed -i -e "s|;session.save_path = \"/tmp\"|session.save_path = \"tcp://${redis_host}:${redis_port}\"|" /etc/php8/php.ini
    else
        # the sessions are stored in a separate dir
        sed -i -e "s:;session.save_path = \"/tmp\":session.save_path = \"/sessions\":" /etc/php8/php.ini
    fi

    # the sessions are stored in a separate dir
    sed -i -e "s:;session.save_path = \"/tmp\":session.save_path = \"/sessions\":" /etc/php8/php.ini
    mkdir -p /sessions
    chown "${elabftw_user}":"${elabftw_group}" /sessions
    chmod 700 /sessions
    # disable url_fopen http://php.net/allow-url-fopen
    sed -i -e "s/allow_url_fopen = On/allow_url_fopen = Off/" /etc/php8/php.ini
    # enable opcache
    sed -i -e "s/;opcache.enable=1/opcache.enable=1/" /etc/php8/php.ini
    # config for timezone, use : because timezone will contain /
    sed -i -e "s:;date.timezone =:date.timezone = $php_timezone:" /etc/php8/php.ini
    # enable open_basedir to restrict PHP's ability to read files
    # use # for separator because we cannot use : ; / or _
    sed -i -e "s#;open_basedir =#open_basedir = /.dockerenv:/elabftw/:/tmp/:/usr/bin/unzip#" /etc/php8/php.ini
    # use longer session id length
    sed -i -e "s/session.sid_length = 26/session.sid_length = 42/" /etc/php8/php.ini
    # disable some dangerous functions that we don't use
    sed -i -e "s/disable_functions =$/disable_functions = php_uname, getmyuid, getmypid, passthru, leak, listen, diskfreespace, tmpfile, link, ignore_user_abort, shell_exec, dl, system, highlight_file, source, show_source, fpaththru, virtual, posix_ctermid, posix_getcwd, posix_getegid, posix_geteuid, posix_getgid, posix_getgrgid, posix_getgrnam, posix_getgroups, posix_getlogin, posix_getpgid, posix_getpgrp, posix_getpid, posix_getppid, posix_getpwnam, posix_getpwuid, posix_getrlimit, posix_getsid, posix_getuid, posix_isatty, posix_kill, posix_mkfifo, posix_setegid, posix_seteuid, posix_setgid, posix_setpgid, posix_setsid, posix_setuid, posix_times, posix_ttyname, posix_uname, phpinfo/" /etc/php8/php.ini
    # allow longer requests execution time
    sed -i -e "s/max_execution_time\s*=\s*30/max_execution_time = ${php_max_execution_time}/" /etc/php8/php.ini

}

elabftwConf() {
    mkdir -p /elabftw/uploads /elabftw/cache
    chown "${elabftw_userid}":"${elabftw_groupid}" /elabftw/uploads /elabftw/cache
    chmod 700 /elabftw/uploads /elabftw/cache
}

writeConfigFile() {
    # write config file from env var
    config_path="/elabftw/config.php"
    config="<?php
    define('DB_HOST', '${db_host}');
    define('DB_PORT', '${db_port}');
    define('DB_NAME', '${db_name}');
    define('DB_USER', '${db_user}');
    define('DB_PASSWORD', '${db_password}');
    define('DB_CERT_PATH', '${db_cert_path}');
    define('SECRET_KEY', '${secret_key}');"
    echo "$config" > "$config_path"
    chown "${elabftw_user}":"${elabftw_group}" "$config_path"
    chmod 600 "$config_path"
}

# because a global variable is not the best place for a secret value...
unsetEnv() {
    unset DB_HOST
    unset DB_PORT
    unset DB_NAME
    unset DB_USER
    unset DB_PASSWORD
    unset DB_CERT_PATH
    unset SERVER_NAME
    unset DISABLE_HTTPS
    unset ENABLE_LETSENCRYPT
    unset SECRET_KEY
}

# script start
getEnv
createUser
nginxConf
phpfpmConf
phpConf
elabftwConf
writeConfigFile
unsetEnv

# start all the services
/init
