ARG BASE_IMAGE_VERSION
FROM geonode/geoserver:${BASE_IMAGE_VERSION}

COPY bootstrap-admin.sh /usr/local/tomcat/tmp/bootstrap-admin.sh
RUN chmod +x /usr/local/tomcat/tmp/bootstrap-admin.sh