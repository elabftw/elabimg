#!/bin/bash
#
# @author Nicolas CARPi <nico-git@deltablot.email>
# @copyright 2020 Nicolas CARPi
# @see https://www.elabftw.net Official website
# @license AGPL-3.0
# @package elabftw/elabimg
#
# This script is called by the oneshot service "init"
# It will get config from env and adjust configuration files and system accordingly

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
    db_password=${DB_PASSWORD:-}
    unset DB_PASSWORD
    db_cert_path=${DB_CERT_PATH:-}
    unset DB_CERT_PATH
    site_url=${SITE_URL:-}
    # remove trailing slash for site_url
    site_url=$(echo "${site_url}" | sed 's:/$::')
    server_name=${SERVER_NAME:-localhost}
    disable_https=${DISABLE_HTTPS:-false}
    enable_letsencrypt=${ENABLE_LETSENCRYPT:-false}
    secret_key=${SECRET_KEY:-}
    unset SECRET_KEY
    max_php_memory=${MAX_PHP_MEMORY:-2G}
    max_upload_size=${MAX_UPLOAD_SIZE:-100M}
    max_upload_time=${MAX_UPLOAD_TIME:-900000}
    # CIS benchmark nginx 2.0.0 2.4.3
    keepalive_timeout=${KEEPALIVE_TIMEOUT:-10s}
    php_timezone=${PHP_TIMEZONE:-Europe/Paris}
    set_real_ip=${SET_REAL_IP:-false}
    set_real_ip_from=${SET_REAL_IP_FROM:-192.168.31.48}
    php_max_children=${PHP_MAX_CHILDREN:-50}
    elabimg_version=${ELABIMG_VERSION:-0.0.0}
    php_max_execution_time=${PHP_MAX_EXECUTION_TIME:-120}
    use_redis=${USE_REDIS:-false}
    redis_host=${REDIS_HOST:-redis}
    redis_port=${REDIS_PORT:-6379}
    redis_username=${REDIS_USERNAME:-}
    redis_password=${REDIS_PASSWORD:-}
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
    auto_db_init=${AUTO_DB_INIT:-false}
    auto_db_update=${AUTO_DB_UPDATE:-false}
    aws_ak=${ELAB_AWS_ACCESS_KEY:-}
    unset ELAB_AWS_ACCESS_KEY
    aws_sk=${ELAB_AWS_SECRET_KEY:-}
    unset ELAB_AWS_SECRET_KEY
    ldap_tls_reqcert=${LDAP_TLS_REQCERT:-false}
    allow_origin=${ALLOW_ORIGIN:-}
    allow_methods=${ALLOW_METHODS:-}
    allow_headers=${ALLOW_HEADERS:-}
    status_password=${STATUS_PASSWORD:-}
}

# Create the user that will run nginx/php/cronjobs
createUser() {
    getent group "${elabftw_group}" 2>&1 > /dev/null || /usr/sbin/addgroup -g "${elabftw_groupid}" "${elabftw_group}"
    getent shadow "${elabftw_user}" 2>&1 > /dev/null || /usr/sbin/adduser -u "${elabftw_userid}" -G "${elabftw_group}" "${elabftw_user}"
    # crontab
    /bin/echo "${elabftw_user}" > /etc/cron.d/cron.allow
    if [ -f /etc/elabftw-cronjob ]; then
        /bin/mv /etc/elabftw-cronjob "/etc/crontabs/${elabftw_user}"
    fi
    # run invoker with the specific user
    mkdir -p /run/invoker
    chown "${elabftw_user}":"${elabftw_group}" /run/invoker
    # TODO send logs to stdout
    INVOKER_PSK=$(openssl rand -base64 42)
    export INVOKER_PSK
    # allow php to read it. use | separator as / is in base64
    sed -i -e "s|^env\[INVOKER_PSK\] = .*|env[INVOKER_PSK] = ${INVOKER_PSK}|" /etc/php83/php-fpm.d/elabpool.conf
    su -p -c "/usr/bin/invoker > /run/invoker/log 2>&1 &" -s /bin/sh "${elabftw_user}"
}

checkSiteUrl() {
    if [ -z "${site_url}" ]; then
        echo "=======================================================" >&2
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
        echo "" >&2
        echo "ERROR: environment variable SITE_URL not set!" >&2
        echo "Continuing anyway but you need to set it and restart the container." >&2
        echo "" >&2
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
        echo "=======================================================" >&2
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

    # set the list of php files that can be processed by php-fpm
    php_files_nginx_allowlist=$(find /elabftw/web -type f -name '*.php' | sed 's:/elabftw/web/::' | tr '\n' '|' | sed 's/|$//')
    # use : because of the / in the list of files
    sed -i -e "s:%PHP_FILES_NGINX_ALLOWLIST%:${php_files_nginx_allowlist}:" /etc/nginx/common.conf

    # adjust keepalive_timeout
    sed -i -e "s/%KEEPALIVE_TIMEOUT%/${keepalive_timeout}/" /etc/nginx/nginx.conf

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
        # use pipe for sed separation because CIDR might have a /
        sed -i -e "s|#%REAL_IP_CONF%|${conf_string}|" /etc/nginx/common.conf
        # enable real_ip_header config
        sed -i -e "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/common.conf
        sed -i -e "s/#real_ip_recursive on;/real_ip_recursive on;/" /etc/nginx/common.conf
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
        rm -f /etc/nginx/conf.d/brotli.conf /etc/nginx/conf.d/gzip.conf
        # to allow webpack in watch/dev mode we need to allow unsafe-eval for script-src
        unsafe_eval="'unsafe-eval'"
    fi
    # set unsafe-eval in CSP
    sed -i -e "s/%UNSAFE-EVAL4DEV%/${unsafe_eval}/" /etc/nginx/common.conf
    # put a random short string as the server header to prevent fingerprinting
    server_header=$(echo $RANDOM | md5sum | head -c 3)
    sed -i -e "s/%SERVER_HEADER%/${server_header}/" /etc/nginx/common.conf
    # add Access-Control-Allow-Origin header if enabled
    acao_header=""
    if [ -n "$allow_origin" ]; then
        acao_header="more_set_headers 'Access-Control-Allow-Origin: ${allow_origin}';"
    fi
    sed -i -e "s#%ACAO_HEADER%#${acao_header}#" /etc/nginx/common.conf
    # add Access-Control-Allow-Methods header if enabled
    acam_header=""
    if [ -n "$allow_methods" ]; then
        acam_header="more_set_headers 'Access-Control-Allow-Methods: ${allow_methods}';"
    fi
    sed -i -e "s/%ACAM_HEADER%/${acam_header}/" /etc/nginx/common.conf
    # add Access-Control-Allow-Headers header if enabled
    acah_header=""
    if [ -n "$allow_headers" ]; then
        acah_header="more_set_headers 'Access-Control-Allow-Headers: ${allow_headers}';"
    fi
    sed -i -e "s/%ACAH_HEADER%/${acah_header}/" /etc/nginx/common.conf

    # create a password file for /php-status endpoint
    if [ -z "$status_password" ]; then
        # if no password is provided, instead of hardcoding a default password, we generate one
        status_password=$(echo $RANDOM | sha1sum)
    fi
    # instead of installing htpasswd, use openssl that is already here
    printf "elabftw:%s\n" "$(openssl passwd -apr1 "$status_password")" > /etc/nginx/passwords
    chown "${elabftw_user}":"${elabftw_group}" /etc/nginx/passwords
    chmod 400 /etc/nginx/passwords
}

# PHP-FPM CONFIG
phpfpmConf() {
    f="/etc/php83/php-fpm.d/elabpool.conf"
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

getRedisUri() {
    username=""
    password=""
    # the & and ? are escaped because of the sed
    # it's probably a good idea to not have to many weird characters in redis username/password
    query_link="\&"
    if [ -n "$redis_username" ]; then
        username="\?auth[user]=${redis_username}"
    fi
    if [ -n "$redis_password" ]; then
        if [ -z "$redis_username" ]; then
            query_link="\?"
        fi
        password="${query_link}auth[pass]=${redis_password}"
    fi
    # add a set of quotes or the = sign will pose problem in php.ini
    printf "\"tcp://%s:%d%s%s\"" "$redis_host" "$redis_port" "$username" "$password"
}

# PHP CONFIG
phpConf() {
    f="/etc/php83/php.ini"
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
        sess_save_path=$(getRedisUri)
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
    # /etc/ssl/cert.pem is for openssl and timestamp related functions
    # for /run/s6-rc... see elabftw/elabftw#5249
    open_basedir="/.dockerenv:/elabftw/:/tmp/:/usr/bin/unzip:/etc/ssl/cert.pem:/run/s6-rc/servicedirs/s6rc-oneshot-runner"
    # DEV MODE
    if ($dev_mode); then
        # we don't want to use opcache as we want our changes to be immediately visible
        sed -i -e "s/opcache\.enable=1/opcache\.enable=0/" $f
        # extend open_basedir
        # //autoload.php, /root/.cache/ are for psalm
        # /proc/cpuinfo is for phpstan, https://github.com/phpstan/phpstan/issues/4427 https://github.com/phpstan/phpstan/issues/2965
        # /proc/version is for symfony, and the rest for composer
        #open_basedir="${open_basedir}:/proc/version:/usr/bin/composer:/composer://autoload\.php:/root/\.cache/:/proc/cpuinfo:/usr/share"
        # completely remove open_basedir in dev because it's a pita with phpstan for instance
        open_basedir=""
        # rector needs tmpfile, so allow it in dev mode
        sed -i -e "s/tmpfile, //" $f
    fi
    # now set value for open_basedir
    sed -i -e "s|%OPEN_BASEDIR%|${open_basedir}|" $f
}

elabftwConf() {
    mkdir -p /elabftw/uploads /elabftw/cache/elab /elabftw/cache/mpdf /elabftw/cache/twig /elabftw/cache/purifier/CSS /elabftw/cache/purifier/HTML /elabftw/cache/purifier/URI
    chown -R "${elabftw_userid}":"${elabftw_groupid}" /elabftw/cache
    # no recursive flag for uploads
    chown "${elabftw_userid}":"${elabftw_groupid}" /elabftw/uploads
    chmod 700 /elabftw/uploads /elabftw/cache
}

ldapConf() {
    mkdir -p /etc/openldap
    if [ "$ldap_tls_reqcert" != false ]; then
        # remove a possibly existing line or it will append every time container is restarted
        sed -i -e '/^TLS_REQCERT/d' /etc/openldap/ldap.conf
        echo "TLS_REQCERT ${ldap_tls_reqcert}" >> /etc/openldap/ldap.conf
    fi
}

populatePhpEnv() {

    sed -i -e "s/%DB_HOST%/${db_host}/" /etc/php83/php-fpm.d/elabpool.conf
    sed -i -e "s/%DB_PORT%/${db_port}/" /etc/php83/php-fpm.d/elabpool.conf
    sed -i -e "s/%DB_NAME%/${db_name}/" /etc/php83/php-fpm.d/elabpool.conf
    sed -i -e "s/%DB_USER%/${db_user}/" /etc/php83/php-fpm.d/elabpool.conf
    sed -i -e "s/%DB_PASSWORD%/${db_password}/" /etc/php83/php-fpm.d/elabpool.conf
    # don't add empty stuff
    if [ -n "$db_cert_path" ]; then
        # use # as separator instead of slash
        sed -i -e "s#%DB_CERT_PATH%#${db_cert_path}#" /etc/php83/php-fpm.d/elabpool.conf
    else
        # remove this if not in use
        sed -i -e "/%DB_CERT_PATH%/d" /etc/php83/php-fpm.d/elabpool.conf
    fi
    sed -i -e "s/%SECRET_KEY%/${secret_key}/" /etc/php83/php-fpm.d/elabpool.conf
    sed -i -e "s/%MAX_UPLOAD_SIZE%/${max_upload_size}/" /etc/php83/php-fpm.d/elabpool.conf
    sed -i -e "s/%MAX_UPLOAD_TIME%/${max_upload_time}/" /etc/php83/php-fpm.d/elabpool.conf
    # use # as separator instead of slash
    sed -i -e "s#%SITE_URL%#${site_url}#" /etc/php83/php-fpm.d/elabpool.conf
    # assume that if ak is set, then sk is too
    if [ -n "$aws_ak" ]; then
        sed -i -e "s|%ELAB_AWS_ACCESS_KEY%|${aws_ak}|" /etc/php83/php-fpm.d/elabpool.conf
        sed -i -e "s|%ELAB_AWS_SECRET_KEY%|${aws_sk}|" /etc/php83/php-fpm.d/elabpool.conf
    else
        sed -i -e "/%ELAB_AWS_ACCESS_KEY%/d" /etc/php83/php-fpm.d/elabpool.conf
        sed -i -e "/%ELAB_AWS_SECRET_KEY%/d" /etc/php83/php-fpm.d/elabpool.conf
    fi
}

# create a file to hold the env so bash phpwithenv aka php can read it
populateBashEnv() {
    # cron will forget all env, so we use a bash profile to set it for our user
    filepath="/etc/elabftw_env"
    content="export DB_HOST='${db_host}'
    export DB_PORT='${db_port}'
    export DB_NAME='${db_name}'
    export DB_USER='${db_user}'
    export DB_PASSWORD='${db_password}'
    export DB_CERT_PATH='${db_cert_path}'
    export MAX_UPLOAD_SIZE='${max_upload_size}'
    export MAX_UPLOAD_TIME='${max_upload_time}'
    export SECRET_KEY='${secret_key}'
    export SITE_URL='${site_url}'
    export ELAB_AWS_ACCESS_KEY='${aws_ak}'
    export ELAB_AWS_SECRET_KEY='${aws_sk}'"
    echo "$content" > "$filepath"
    chown "${elabftw_user}":"${elabftw_group}" "$filepath"
    chmod 400 "$filepath"
}

# display a friendly message with running versions
startupMessage() {
    nginx_version=$(/usr/sbin/nginx -v 2>&1)
    say "elabimg: info: eLabFTW version: %ELABFTW_VERSION%"
    say "elabimg: info: image version: %ELABIMG_VERSION%"
    say "elabimg: info: ${nginx_version}"
    say "elabimg: info: s6-overlay version: %S6_OVERLAY_VERSION%"
    say "elabimg: info: runtime configuration successfully finished"
}

# Automatically initialize the database structure
dbInit() {
    if ($auto_db_init); then
        say "elabimg: info: initializing database structure"
        /elabftw/bin/init db:install
    fi
}

# Automatically update the database schema
dbUpdate() {
    if ($auto_db_update); then
        say "elabimg: info: updating database structure"
        /elabftw/bin/console db:update
    fi
}

say() {
    if (! $silent_init); then
        echo "$1"
    fi
}

# script start
getEnv
checkSiteUrl
createUser
nginxConf
phpfpmConf
phpConf
elabftwConf
ldapConf
populatePhpEnv
populateBashEnv
dbInit
dbUpdate
startupMessage
