# Container image version
# Note: the version here is from Dockerfile:ELABIMG_VERSION not the tagged one

# 4.0.0

* Add env vars directly in php, don't create config.php anymore
* Require ELABFTW_VERSION build argument

# 3.9.0

* Use a random string as BUILD_ID to use for the v query string parameter for loading assets

# 3.8.0

* Fix issue with ARM build. Fix #30 via #31 by @nilssta
* Add cronjob for available timestamp tokens left notifications

# 3.7.0

* Allow CORS requests:
* OPTIONS method
* Add ALLOW_ORIGIN configuration option
* Add ALLOW_METHODS configuration option
* Add ALLOW_HEADERS configuration option

# 3.6.2

* Fix issue with api query parameters in nginx config. See elabftw/elabftw#3954.

# 3.6.1

* Set `allow_url_fopen` to `On` because the application needs it.

# 3.6.0

* Add support for redis username and password settings
* Make sure /elabftw/cache/purifier folder is created with correct permissions at init time

# 3.5.1

* Change SameSite attribute of PHP Session cookie to Lax (see elabftw/elabftw#3749)

# 3.5.0

* Use Alpine linux 3.16 (was 3.15)
* Use PHP 8.1 (was 8.0)
* Use nginx 1.23.1 (was 1.21.6)
* Use composer 2.3.10 (was 2.2.7)
* Use s6-overlay 3.1.1.2 (was 3.1.0.1)
* Add LDAP_TLS_REQCERT env variable to control ldap certificate behaviour

# 3.4.1

* Avoid errors when container is restarted and prepare.sh is run again

# 3.4.0

* Add `auto_db_init` and `auto_db_update` to run migrations automatically on container start
* Add `healthcheck`/`depends_on` directive in example docker-compose.yml

# 3.3.0

* Update s6-overlay to 3.1.0.1

# 3.2.2

* Fix cronjob not working when default user/group was used. Now the user is only created at runtime, not at build time too.
* Don't chown the nginx log folder (not necessary/useful)

# 3.2.1

* Fix incorrect cronie install

# 3.2.0

* Make the /run folder empty in image (#27)
* Update MySQL port settings documentation (#26 by @anargam)
* Don't exit with error on SITE_URL absence, go on so a nice error message can be shown on the web app
* Fix incorrect nginx folders creation

# 3.1.0

* Add mandatory environment variable SITE_URL (elabftw/elabftw#3319)
* Customize nginx build a bit more by removing unneeded modules
* Remove dhparams because no DHE ciphersuites are used anyway
* Add a cronjob daemon to send email notifications
* Update the init system (s6) to v3
* Update nginx to 1.21.6
* Use alpine 3.15
* Use composer 2.2.7

# 3.0.3

* Add php8-xml package

# 3.0.2

* Remove php8-pear package

# 3.0.1

* Remove java dependency (not needed any longer)

# 3.0.0

* BREAKING CHANGE FOR DEVELOPERS ONLY: the `dev` branch is no more. Use DEV_MODE=true env var instead and use `hypernext` branch for the dev image.
* Use custom compiled nginx instead of the packaged version (#20)
* Rework placeholders syntax in nginx config files
* Add configurable value for worker_processes setting: NGINX_WORK_PROC (default: auto)
* Change labels org to net.elabftw
* Group steps together where it makes sense
* Remove useless VOLUME instructions
* Add a message on startup with running versions
* Add a config option to have less messages on startup (SILENT_INIT)

# 2.6.1
* Modify also the memory_limit value in php.ini

# 2.6.0
* Add Vary header
* Add zopfli for gzip asset compression
* Remove unnecessary headers for assets
* Use nginx module to better handle headers

# 2.5.1
* Add long caching for assets

# 2.5.0
* Add brotli compression to nginx for assets

# 2.4.1
* Set X-XSS-Protection to 0 as per OWASP recommendation
* Remove X-Frame-Options header as it is obsolete with the frame-ancestor CSP directive

# 2.4.0
* Alpine 3.13
* PHP8
* Add TLSv1.3 support in https mode
* Add healthcheck for nginx

# 2.3.1
* Fix configuration option PHP_MAX_CHILDREN not taken into account
* Increase number of server threads for php-fpm
* Increase fastcgi_read_timeout in nginx config

# 2.3.0
* Use s6-overlay instead of supervisor to launch services

## 2.2.1
* Add DB_CERT env variable to point to MySQL cert file path

## 2.2.0
* Use Alpine 3.12
* Remove deprecated composer option --no-suggest

## 2.1.0

* Add php7-ldap
* Add Strict SameSite cookie

## 2.0.1

* Fix supervisord waring on start about user root
* Fix ELABIMG_VERSION getting added at each restart
* Fix ln command producing warning on restart

## 2.0.0

* Use stdout and stderr for logging: logs can now be accessed via the docker logs command
* Allow change of user/group for nginx/php-fpm (#10)

## 1.5.1

* Fix nginx pid path

## 1.5.0

* Use Alpine 3.11 as base image

## 1.4.1

* Disable not found logs for assets and php files

## 1.4.0

* add gzip compression for javascript and css
* add php7-exif
* improve disable_function sed

## 1.3.1

* Fix the client_max_body_size parameter
* Remove ./dockerenv file

## 1.3.0

* Add an option to define the MySQL port

## 1.2.0

* Fix nginx configuration for max file size allowed for upload
* Add ENABLE_IPV6 option for ipv6 in nginx

## 1.1.0

* Add redis support for session handling
* Use Alpine linux version 3.10
* Fix bug in DH params generation
* Use Gmagick 2.0.5RC1

## 1.0.6

* Remove form-action in CSP
* Update the example docker-compose file to version 3

## 1.0.5

* Add more restrictions in CSP
* Add circleci image vulnerability checks

## 1.0.4

* Add Feature-Policy header
* Disable access log for assets in nginx config

## 1.0.3

* Add unzip to open_basedir so composer can use it
* Whitelist allowed http methods in nginx
* Remove .git folder
* Use --no-cache instead of --update for apk
* Increase pcre.backtrack_limit value to prevent pdf issue
* Install unzip for composer

## 1.0.2

* Remove mcrypt dependency
* Replace google.com by gstatic.com in CSP header whitelist
* Add PHP_MAX_EXECUTION_TIME env var

## 1.0.1

* Start CHANGELOG
