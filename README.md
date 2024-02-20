# Description

This Docker image is for [eLabFTW](https://www.elabftw.net). It runs three services:

* Nginx webserver
* PHP-FPM service
* Cron daemon to execute recurrent tasks (sending notifications)

These services are managed by s6-overlay and are all customized for running eLabFTW.

# Tags

Tags, in the context of Docker images, are what comes after the image name (`elabftw/elabimg`), separated by a colon. If you leave it empty, it defaults to `latest`. But it is recommended to explicitly define the version you wish to run, e.g.: `elabftw/elabimg:5.0.3`.

When defining which image version to use, you can use different tags:

* `x.y.z`: the actual explicit version: recommended
* `stable`: the latest stable version
* `latest`: the latest version, can be a stable version or an alpha or beta, whatever is present on `master` branch of eLabFTW
* `hypernext`: this is the dev version, built on a "push" event as well as on a daily schedule.

# Building this image

Set the `ELABFTW_VERSION` to a tagged release or a branch. The latest stable version can be found [here](https://github.com/elabftw/elabftw/releases/latest).

~~~bash
DOCKER_BUILDKIT=1 docker build --build-arg ELABFTW_VERSION=X.Y.Z -t elabftw/elabimg:X.Y.Z .
~~~

For dev, add `--build-arg BUILD_ALL=0` to skip the installation of dependencies and building of assets, because the folder will be bind-mounted to your host anyway.

# Usage

An example configuration file for docker-compose can be fetched like this:

~~~bash
curl -so docker-compose.yml "https://get.elabftw.net/?config"
~~~

This will download a pre-filled configuration file.

You can then edit this file where all the possible settings are explained in the comments.

For usage of eLabFTW, see [documentation](https://doc.elabftw.net).

## Reloading a service

~~~bash
/package/admin/s6/command/s6-svc -r /run/service/php
/package/admin/s6/command/s6-svc -r /run/service/nginx
~~~

## Deleting cache

If there is a CVE fixed upstream, delete build cache with:

~~~bash
gh cache delete --all
~~~

Requires GitHub CLI: https://cli.github.com/
