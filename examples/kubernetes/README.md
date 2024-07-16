# SOGo Kubernetes HA Example

The Manifest files in this directory showcase a simple SOGo setup for High Availability in a Kubernetes Cluster with an external database.

## ConfigMap
The [configmap.yaml](configmap.yaml) file contains the Apache2 and SOGo configuration as files `apache-SOGo.conf` and `sogo.conf`. These files must be edited to suit your needs.  
The ConfigMap can also be created with a ConfigMapGenerator from actual files via Kustomize.

## Deployment
The [deployment.yaml](deployment.yaml) file contains the actual SOGo Deployment, specifying two replicas.  
The [ConfigMap](#configmap) is mounted into the container to `/srv/etc`, so that the `apache-SOGo.conf` and `sogo.conf` files in the ConfigMap are available at `/srv/etc/apache-SOGo.conf` and `/srv/etc/sogo.conf`, respectively.  
The internal `cron` service is disabled by setting the environment variable `DISABLE_CRON` to `1`.

## Service
The [service.yaml](service.yaml) file is a straight-forward service, mapping the service port `8080` to the container's `http` port.

## Ingress
The [ingress.yaml](ingress.yaml) file uses `traefik` as `ingressClassName`, the rest is as straight-forward as the [Service](#service).

## CronJob
[cronjob-every-minute.yaml](cronjob-every-minute.yaml) showcases how SOGo cronjobs should be set up in an HA environment. The defined CronJob starts up a normal SOGo container, but overrides the entrypoint by appending calls to `sogo-tool` with user `sogo` (as seen in [cron.template](../../template/cron/cron.template)).  
Create one cronjob defintion for each required schedule.
