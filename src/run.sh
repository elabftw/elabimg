#!/bin/bash
# elabftw-docker start script for Alpine Linux base image

# get env values
# and unset the sensitive ones so they cannot be accessed by a rogue process
getEnv() {
    db_host=${DB_HOST:-localhost}
    unset DB_HOST
    db_port=${DB_PORT:-3306}
    unset DB_PORT
    db_name=${DB_NAME:-elabftw}
    unset DB_NAME
    db_user=${DB_USER:-elabftw}
    unset DB_USER
    # Note: no default value here
    db_password=${DB_PASSWORD}
    unset DB_PASSWORD
    db_cert_path=${DB_CERT_PATH:-}
    unset DB_CERT_PATH
    server_name=${SERVER_NAME:-localhost}
    disable_https=${DISABLE_HTTPS:-false}
    enable_letsencrypt=${ENABLE_LETSENCRYPT:-false}
    secret_key=${SECRET_KEY}
    unset SECRET_KEY
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
    enable_ipv6=${ENABLE_IPV6:-false}
    elabftw_user=${ELABFTW_USER:-nginx}
    elabftw_group=${ELABFTW_GROUP:-nginx}
    elabftw_userid=${ELABFTW_USERID:-101}
    elabftw_groupid=${ELABFTW_GROUPID:-101}
    # value for nginx's worker_processes setting
    nginx_work_proc=${NGINX_WORK_PROC:-auto}
    # allow limiting log pollution on startup
    silent_init=${SILENT_INIT:-false}
    dev_mode=${DEV_MODE:-false}
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
        /bin/sh /etc/nginx/generate-dhparam.sh
        # activate an HTTPS server listening on port 443
        ln -fs /etc/nginx/https.conf /etc/nginx/conf.d/elabftw.conf
        if ($enable_letsencrypt); then
            mkdir -p /ssl
            sed -i -e "s:%CERT_PATH%:/ssl/live/${server_name}/fullchain.pem:" /etc/nginx/conf.d/elabftw.conf
            sed -i -e "s:%KEY_PATH%:/ssl/live/${server_name}/privkey.pem:" /etc/nginx/conf.d/elabftw.conf
        else
            sed -i -e "s:%CERT_PATH%:/etc/nginx/certs/server.crt:" /etc/nginx/conf.d/elabftw.conf
            sed -i -e "s:%KEY_PATH%:/etc/nginx/certs/server.key:" /etc/nginx/conf.d/elabftw.conf
        fi
    fi
    # set the server name in nginx config
    # works also for the ssl config if ssl is enabled
    # here elabftw.conf is a symbolic link to either http.conf or https.conf
    sed -i -e "s/%SERVER_NAME%/${server_name}/" /etc/nginx/conf.d/elabftw.conf
    # make sure nginx user can write this directory for file uploads
    chown -R "${elabftw_user}":"${elabftw_group}" /var/lib/nginx/tmp

    # adjust client_max_body_size
    sed -i -e "s/%CLIENT_MAX_BODY_SIZE%/${max_upload_size}/" /etc/nginx/nginx.conf

    # SET REAL IP CONFIG
    if ($set_real_ip); then
        # read the IP addresses from env
        IFS=', ' read -r -a ip_arr <<< "${set_real_ip_from}"
        conf_string=""
        for element in "${ip_arr[@]}"
        do
            conf_string+="set_real_ip_from ${element};"
        done
        sed -i -e "s/#%REAL_IP_CONF%/${conf_string}/" /etc/nginx/common.conf
        # enable real_ip_header config
        sed -i -e "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/common.conf
    fi

    # IPV6 CONFIG
    if ($enable_ipv6); then
        sed -i -e "s/#listen \[::\]:443;/listen \[::\]:443;/" /etc/nginx/conf.d/elabftw.conf
        sed -i -e "s/#listen \[::\]:443 ssl http2;/listen \[::\]:443 ssl http2;/" /etc/nginx/conf.d/elabftw.conf
    fi

    # CHANGE NGINX USER
    sed -i -e "s/%USER-GROUP%/${elabftw_user} ${elabftw_group}/" /etc/nginx/nginx.conf

    # SET WORKER PROCESSES (default is auto)
    sed -i -e "s/%WORKER_PROCESSES%/${nginx_work_proc}/" /etc/nginx/nginx.conf

    # no unsafe-eval in prod
    unsafe_eval=""
    # DEV MODE
    # we don't want to serve brotli/gzip compressed assets in dev (or we would need to recompress them after every change!)
    if ($dev_mode); then
        rm /etc/nginx/conf.d/brotli.conf /etc/nginx/conf.d/gzip.conf
        # to allow webpack in watch/dev mode we need to allow unsafe-eval for script-src
        unsafe_eval="'unsafe-eval'"
    fi
    # set unsafe-eval in CSP
    sed -i -e "s/%UNSAFE-EVAL4DEV%/${unsafe_eval}/" /etc/nginx/common.conf
}

# PHP-FPM CONFIG
phpfpmConf() {
    f="/etc/php8/php-fpm.d/elabpool.conf"
    # set nginx as user for php-fpm
    sed -i -e "s/%ELABFTW_USER%/${elabftw_user}/" $f
    sed -i -e "s/%ELABFTW_GROUP%/${elabftw_group}/" $f
    # increase max number of simultaneous requests
    sed -i -e "s/%PHP_MAX_CHILDREN%/${php_max_children}/" $f
    # allow using more memory for php-fpm
    sed -i -e "s/%PHP_MAX_MEMORY%/${max_php_memory}/" $f
    # add container version in env (named env or it will get replaced by Docker build instruction
    sed -i -e "s/%ELABIMG_VERSION_ENV%/${elabimg_version}/" $f
}

# PHP CONFIG
phpConf() {
    f="/etc/php8/php.ini"
    # allow using more memory for php
    sed -i -e "s/%PHP_MEMORY_LIMIT%/${max_php_memory}/" $f
    # change upload_max_filesize and post_max_size
    sed -i -e "s/%PHP_MAX_UPLOAD_SIZE%/${max_upload_size}/" $f

    # PHP SESSIONS
    # default values for sessions (with files)
    sess_save_handler="files"
    sess_save_path="/sessions"
    # if we use redis then sessions are handled differently
    if ($use_redis); then
        sess_save_handler="redis"
        sess_save_path="tcp://${redis_host}:${redis_port}"
    else
        # create the custom session dir
        mkdir -p /sessions
        chown "${elabftw_user}":"${elabftw_group}" /sessions
        chmod 700 /sessions
    fi
    # now set the values
    sed -i -e "s:%SESSION_SAVE_HANDLER%:${sess_save_handler}:" $f
    sed -i -e "s|%SESSION_SAVE_PATH%|${sess_save_path}|" $f

    # config for timezone, use : because timezone will contain /
    sed -i -e "s:%TIMEZONE%:${php_timezone}:" $f
    # allow longer requests execution time
    sed -i -e "s/%PHP_MAX_EXECUTION_TIME%/${php_max_execution_time}/" $f

    # production open_basedir conf value
    open_basedir="/.dockerenv:/elabftw/:/tmp/:/usr/bin/unzip"
    # DEV MODE
    if ($dev_mode); then
        # we don't want to use opcache as we want our changes to be immediatly visible
        sed -i -e "s/opcache\.enable=1/opcache\.enable=0/" $f
        # also allow url_fopen so composer works
        sed -i -e "s/allow_url_fopen = Off/allow_url_fopen = On/" $f
        # /proc/version is for symfony, and the rest for composer
        open_basedir="${open_basedir}:/proc/version:/usr/bin/composer:/composer"
    fi
    # now set value for open_basedir
    sed -i -e "s|%OPEN_BASEDIR%|${open_basedir}|" $f
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

startupMessage() {
    # display a friendly message with running versions
    nginx_version=$(nginx -v 2>&1)
    # IMPORTANT: heredoc EOT must not have spaces before or after, hence the incorrect indent
    cat >&2 <<EOT
INFO: Runtime configuration done. Now starting...
eLabFTW version: %ELABFTW_VERSION%
Docker image version: %ELABIMG_VERSION%
${nginx_version}
s6-overlay version: %S6_OVERLAY_VERSION%
EOT
}

# script start
getEnv
createUser
nginxConf
phpfpmConf
phpConf
elabftwConf
writeConfigFile

if [ "${silent_init}" = false ]; then
    startupMessage
fi

# start all the services
/init
