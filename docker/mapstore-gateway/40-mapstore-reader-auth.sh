#!/bin/sh
set -eu

: "${MAPSTORE_GEOSERVER_READER_USER:?MAPSTORE_GEOSERVER_READER_USER must be set}"
: "${MAPSTORE_GEOSERVER_READER_PASSWORD:?MAPSTORE_GEOSERVER_READER_PASSWORD must be set}"

printf '%s' "${MAPSTORE_GEOSERVER_READER_PASSWORD}" \
    | htpasswd -i -cB -C 12 /etc/nginx/.htpasswd "${MAPSTORE_GEOSERVER_READER_USER}"
chown nginx:nginx /etc/nginx/.htpasswd
chmod 600 /etc/nginx/.htpasswd
