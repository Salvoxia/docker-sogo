# SOGo Docker Example

The [docker-compose.yml](docker-compose.yml) file contains a minimalistic example of a working SOGo stack. It consists of a PostgreSQL database container, along the actual SOGo container.  
The database's data as well as SOGo's `/srv` folder are persistent volume mounts.  
SOGo runs without root privileges as UID `999`, so create its folder with the matching owner before starting the stack:

```bash
mkdir -p sogo/data && sudo chown 999:999 sogo/data
```

SOGo is available on port `8080`.

Refer to to the [README's Setup section](../../README.md#setup) for information how to configure SOGo with database credentials etc.