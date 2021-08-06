[![build status](https://github.com/elabftw/elabimg/actions/workflows/push_next_hypernext_image.yaml/badge.svg)](https://github.com/elabftw/elabimg/actions/workflows/push_next_hypernext_image.yaml)
[![vuln scan](https://github.com/elabftw/elabimg/actions/workflows/push_next_hypernext_image.yaml/badge.svg)](https://github.com/elabftw/elabimg/actions/workflows/push_next_hypernext_image.yaml)

# Description

This Docker image is for [eLabFTW](https://www.elabftw.net). It runs nginx + php + elabftw.

# Building this image

~~~bash
DOCKER_BUILDKIT=1 docker build -t elabftw/elabimg .
~~~

# Usage

An example configuration file for docker-compose can be fetched like this:

~~~bash
curl -so docker-compose.yml "https://get.elabftw.net/?config"
~~~

This will download a pre-filled configuration file.

You can then edit this file where all the options are explained in the comments.

For usage of eLabFTW, see [documentation](https://doc.elabftw.net).
