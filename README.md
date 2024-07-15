# SOGo for Docker

[SOGo](http://www.sogo.nu) is a fully supported and trusted groupware server
with a focus on scalability and open standards. SOGo is released under the GNU
GPL/LGPL v2 and above.

This Dockerfile packages SOGo as packaged by ubuntu, together with Apache 2 and
memcached.

## Setup

The image stores configuration and backups in `/srv`, which you should
persist somewhere. Example configuration is copied during each startup of the
container (if no custom configuration is provided), which you can adjust for your own use. For creating the initial
directory hierarchy and example configuration, simply run the container with the
`/srv` volume already exposed or linked, for example using

```bash
docker run -v /srv/sogo:/srv salvoxia/sogo
```

As soon as the files are created, stop the image again. You will now find
following files:

```
.
├── etc
│   ├── apache-SOGo.conf
|   ├── cron
│   └── sogo.conf
└── lib
    └── sogo
        └── GNUstep
            ├── Defaults
            └── Library
```

`apache-SOGo.conf` contains sensible defaults that should work out of the box.  
Edit `sogo.conf` suit your needs (refer to the[Installation and Configuration Guide](https://www.sogo.nu/files/docs/SOGoInstallationGuide.html)).


### Database

A separate database is required, for example a PostgreSQL container as provided
by the Docker image [`postgres`](https://hub.docker.com/_/postgres), but also
any other database management system SOGo supports can be used. Follow the
_Database Configuration_ chapter of the SOGo documentation on these steps, and
modify the sogo.conf` file accordingly. The following documentation will expect
the database to be available with the SOGo default credentials given by the
official documentation, adjust them as needed. If you link a database container,
remember that it will be automatically added to the hosts file and be available
under the chosen name.

For a container named `sogo-postgresql` linked as `db` using
`--link="sogo-postgresql:db"` with default credentials, you would use following
lines in the `sogo.conf`:

```
SOGoProfileURL = "postgresql://sogo:sogo@db:5432/sogo/sogo_user_profile";
OCSFolderInfoURL = "postgresql://sogo:sogo@db:5432/sogo/sogo_folder_info";
OCSSessionsFolderURL = "postgresql://sogo:sogo@db:5432/sogo/sogo_sessions_folder";
```

SOGo performs schema initialziation lazily on startup, thus no database
initialization scripts must be run.

### memcached

An external container is required for memcached.

### Sending Mail

```
SOGoMailingMechanism = "smtp";
SOGoSMTPServer = "yoursmtpserver.localdomain.local";
```

For further details in MTA configuration including SMTP auth, refer to SOGo's
documentation.

### Apache and HTTPs

As already given above, the default Apache configuration is already available
under `etc/apache2/SOGo.conf`. The container exposes HTTP (80), HTTPS (443)
and 8800, which is used by Apple devices, and 20000, the default port the SOGo
daemon listens on. You can either directly include the certificates within the
container, or use an external proxy for this. Make sure to only map the required
ports to not unnecessarily expose daemons.

You need to adjust the `<Proxy ...>` section and include port, server name and
url to match your setup.

```apache
<Proxy http://127.0.0.1:20000/SOGo>
## adjust the following to your configuration
  RequestHeader set "x-webobjects-server-port" "80"
  RequestHeader set "x-webobjects-server-name" "%{HTTP_HOST}e" env=HTTP_HOST
  RequestHeader set "x-webobjects-server-url" "http://%{HTTP_HOST}e" env=HTTP_HOST
```

If you want to support iOS-devices, add appropriate `.well-known`-rewrites in
either the Apache configuration or an external proxy.

For ActiveSync support, additionally add/uncomment the following lines:

```apache
ProxyPass /Microsoft-Server-ActiveSync \
  http://127.0.0.1:20000/SOGo/Microsoft-Server-ActiveSync \
  retry=60 connectiontimeout=5 timeout=360
```

### Cron-Jobs: Backup, Session Timeout, Sieve

SOGo heavily relies on cron jobs for different purposes. The image provides
SOGo's original cron file as `./etc/cron/cron`. Uncomment sections as need.
The backup script is available and made executable at the
predefined location `./sogo-backup.sh`, so backup is fully
functional immediately after uncommenting the respective cron job.

### Further Configuration

Unlike the Debian and probably other SOGo packages, the number of worker
processes is not set in `/etc/default/sogo`, but the normal `sogo.conf`.
Remember to start a reasonable number of worker processes matching to your needs
(8 will not be enough for medium and larger instances):

```
WOWorkersCount = 8;
```

ActiveSync requires one worker per concurrent connection.

All other configuration options have no special considerations.

## Running a Container

Run the image in a container, expose ports as needed and making `/srv`
permanent. An example run command, which links to a database container named
`db` and as well as a memcached container named `memcached`.

```bash
docker run -d \
  --name='sogo' \
  --publish='127.0.0.1:80:80' \
  --link='sogo-postgresql:db' \
  --volume='/srv/sogo:/srv' \
  salvoxia/sogo:latest
```

Also take a look at the [docker-compose example](examples/docker/README.md).

## Upgrading and Maintenance

Most of the time, no special action must be performed for upgrading SOGo. Read
the _Upgrading_ section of the
[Installation and Configuration Guide](https://www.sogo.nu/files/docs/SOGoInstallationGuide.html)
prior upgrading the container to verify whether anything special needs to be
considered.


## Kubernetes Manifest Exmaples

The [Kubernetes Manifest Examples]() contain an example setup for a SOGo Deployment with Service, ConfigMap. Since the
database credentials are configured in SOGo's `sogo.conf` file, the 

### Variables

You can also set http_proxy, https_proxy and no_proxy if you are behind a
corporate proxy for example.

### Health and liveness check

For Health Check, you can check "HTTP request returns a successful status (2xx
or 3xx)" with a request path to "/SOGo" on port 80

### Volumes

I put all the configuration with Config Map named sogo and Config Map values
(sogo.conf and apache-SOGo.conf, optionnaly cron, **it is case sensitive**).
Then for the volumes, I used :

#### Sogo Config Files

- Volume Name : `sogo-conf`
- Default Mode : `644`
- Config Map Name : `sogo with Items : All keys`
- Mount Point : `/srv/etc/`

#### Cron (if needed)

- Volume Name : `sogo-nfs`
- Persisent Volume Claim : `sogo-nfs` (a new persistent volume claim with nfs as
  default provider with Many Nodes Read-Write)
- Mount Point : `/srv`

### Configuration example

  - [template/apache2/SOGo.conf.template](template/apache2/SOGo.conf.template)
  - [template/cron/cron.template](template/cron/cron.template)
  - [template/sogo/sogo.conf.template](template/sogo/sogo.conf.template)
