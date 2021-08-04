# Nginx configuration files

## Description

This folder is copied into `/etc/nginx` in the image. It contains all the configuration files necessary for `nginx` to run.

Some configuration files contain placeholders (`%EXAMPLE%`) that are replaced by a correct value at runtime (script `/run.sh`).

## Files

- `nginx.conf` is the main entrypoint, it loads files in `conf.d` folder
- `conf.d` folder will also contain a symbolic link to either `http.conf` or `https.conf` depending on what we want to run
- `common.conf` contains common configuration options for elabftw server (http or https)

## Configuration

`Nginx` is configured and compiled with only the bare minimum, see the build step in `Dockerfile`.

Upon starting, an existing `dhparams` file is used while another random new one is generated in the background, once this one is generated, it replaces the pre-generated one and `nginx` is reloaded to take it into account.

Custom error pages are also added.
