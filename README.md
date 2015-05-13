# elabftw docker nosql

Build an elabftw container with nginx + php-fpm but without sql.
You need to link this container to an SQL container.
And you also need to import the [sql structure](https://raw.githubusercontent.com/NicolasCARPi/elabftw/master/install/elabftw.sql) into your sql database.

It expects the certs to be server.key and server.crt.

Look at the fig.yml-EXAMPLE file and adapt it to your use case.
