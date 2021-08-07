# Description

This Docker image is for [eLabFTW](https://www.elabftw.net). It runs nginx + php + elabftw.

# Tags and branches

The `hypernext` (dev) and `next` (unstable) branches are rebuilt and pushed to Docker Hub on a "push" event.

The `master` branch is built for the `latest` tag on Docker Hub and contains the stable eLabFTW version.

A tag with the latest released eLabFTW version is also pushed. Example: elabftw/elabimg:4.0.11

# Building this image

~~~bash
docker buildx build -t elabftw/elabimg .
~~~

# Usage

An example configuration file for docker-compose can be fetched like this:

~~~bash
curl -so docker-compose.yml "https://get.elabftw.net/?config"
~~~

This will download a pre-filled configuration file.

You can then edit this file where all the options are explained in the comments.

For usage of eLabFTW, see [documentation](https://doc.elabftw.net).
