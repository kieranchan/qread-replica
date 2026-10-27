#!/bin/sh
# wrapper installed as /usr/local/bin/qread-admin: runs the admin CLI as the service user with the service environment
ENVARGS=$(sudo cat /etc/qread/qread.env | grep -E '^[A-Z_]+=' | tr '\n' ' ')
exec sudo -u qread env $ENVARGS /opt/node/bin/node --disable-warning=ExperimentalWarning /srv/qread/current/src/admin.mjs "$@"
