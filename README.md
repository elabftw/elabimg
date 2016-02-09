# eLabFTW in a docker container

Build an elabftw container with nginx + php-fpm + mysql.

Edit `docker-compose.yml-EXAMPLE` and rename it to `docker-compose.yml`.

Then start with `docker-compose up`.

At the first startup, a private key will be generated. You need to get it from the running container to store it in your docker-compose.yml file.

~~~sh

$ docker ps

~~~

Grab the CONTAINER ID of the elabftw container.

Go into it

~~~sh

$ docker exec -t 733d32c1de22 grep KEY /elabftw/config.php
# replace the ID with yours, tab completion should work

~~~

Now put it in your docker-compose.yml for the next time you want to relaunch the container.

~~~yml

    environment:
        - DB_NAME=elabftw
        - DB_USER=elabftw
        - DB_PASSWORD=secr3t
        - SECRET_KEY=ddc467e42f72535636e87029656ab662

~~~

That's it!

