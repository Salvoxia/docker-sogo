# SOGo for Docker

<div align="center">
  <a href="https://www.sogo.nu">
    <img src="https://www.sogo.nu/img/sogo.svg" alt="Logo" width="200">
  </a>
</div>

[SOGo](https://www.sogo.nu) is a fully supported and trusted groupware server
with a focus on scalability and open standards. SOGo is released under the GNU
GPL/LGPL v2 and above.

This Dockerfile packages SOGo compiled from a defined production source tag, together with Apache 2 and
memcached. 
This means that this image does not rely on the SOGo packages getting updated by any package managers while at the same time using a pinned production tag instead of a nightly release.  
The image is set up in a way to support High Availability (multiple replicas) in a Kubernetes Cluster and provides example files for Docker as well as Kubernetes setups.

## Examples
  - [Running a container from command line](#running-a-container)
  - [Docker Compose Stack](examples/docker/README.md)
  - [Kubernetes Highly Available Setup](examples/kubernetes/README.md)

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
modify the `sogo.conf` file accordingly. The following documentation will expect
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

This image comes with memcached pre-installed and enabled by default. If you do not wish to use memcached or want to use an external instance, the integrated service may be disabled (refer to the [Environment Variables](#environment-variables) section).

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

### Cron-Jobs: Backup, Session Timeout, E-Mail Reminders, ...

SOGo heavily relies on cron jobs for different purposes. The image provides
SOGo's original cron file as `./etc/cron/cron`. Uncomment sections as need.
The backup script is available and made executable at the
predefined location `/srv/sogo-backup.sh`, so backup is fully
functional immediately after uncommenting the respective cron job.

If you intend to run SOGo in Kubernetes using multiple replicas, cron jobs should not run inside the container and thus inside each replica, but a dedicated Kubernetes Cron Job object
should be created, overriding the image's entrypoint for executing the required functionality.
An example can be found in [examples/kubernetes/cronjob-every-minute.yaml](examples/kubernetes/cronjob-every-minute.yaml).  
Refer to the [Environment Variables](#environment-variables) section for documentation how to disable the integrated cron service.

### Further Configuration

Unlike the Debian and probably other SOGo packages, the number of worker
processes is not set in `/etc/default/sogo`, but the normal `sogo.conf`.
Remember to start a reasonable number of worker processes matching to your needs
(8 will not be enough for medium and larger instances):
```
WOWorkersCount = 8;
```

ActiveSync requires one worker per concurrent connection.  

If you start seeing `No child available to handle incoming request` errors in your SOGo log files, it is time to increase the number of workers.

All other configuration options have no special considerations.

### Environment Variables

| Environment varible   |  Mandatory? | Description   |
| :------------------- | :----------- | :------------ |
| DISABLE_MEMCACHED      | no | Disables the integrated `memcached` service |
| DISABLE_CRON            | no | Disables the integrated `cron` service |

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


### Variables

You can also set http_proxy, https_proxy and no_proxy if you are behind a
corporate proxy for example.

### Health and liveness check

For Health Check, you can check "HTTP request returns a successful status (2xx
or 3xx)" with a request path to "/SOGo" on port 80.
For examples refer to the [Docker Compose Example](examples/docker/docker-compose.yml) and [Kubernetes Exmaple](examples/kubernetes/deployment.yaml), respectively.

### Volumes

For Docker, a volume or bind mount should be used and mounted into the container at `/srv`.
The container will initialize the configuration files there as well as place backups in that folder.

For Kubernetes, configuration files should be mounted using a Config Map into `/srv/etc`. When deployed using Kubernetes, backups are likely covered by backups of the external database, so no persistent volumes are necessary.

For both, refer to the [Docker Compose Example](examples/docker/docker-compose.yml) and [Kubernetes Exmaple](examples/kubernetes/deployment.yaml), respectively.

### Configuration Templates

  - [template/apache2/SOGo.conf.template](template/apache2/SOGo.conf.template)
  - [template/cron/cron.template](template/cron/cron.template)
  - [template/sogo/sogo.conf.template](template/sogo/sogo.conf.template)


## SOGo Installation Folder
SOGo is installed in `/usr/local` in this image. Whenever the [Installation and Configuration Guide](https://www.sogo.nu/files/docs/SOGoInstallationGuide.html) refers to a fully qualified path for e.g. `sogo-tool`, it refers to it under `/usr/sbin/sogo-tool`. In this image, `sogo-tool` is located in `/usr/local/sbin/sogo-tool`.  
This applies to virtually everything SOGo-related.

## Image Tag Versioning Scheme

Each image version is based on a specific SOGo release tag version. However, since there is a bit of logic to the image setup itself, this part is versioned as well.  
The versioning scheme of this image consists of two versioning parts:
* Version of this image
* Version of the used Rundeck base image

Example: `1.5.10.0`
* Part 1: __1__.5.10.0 means version 1 of this extended image
* Part 2: 1.__5.10.0__ means this image uses SOGo's 5.10.0 source tag
