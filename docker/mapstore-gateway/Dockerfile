FROM nginx:1.31.8-alpine

RUN apk add --no-cache apache2-utils

COPY 40-mapstore-reader-auth.sh /docker-entrypoint.d/40-mapstore-reader-auth.sh
RUN chmod +x /docker-entrypoint.d/40-mapstore-reader-auth.sh
