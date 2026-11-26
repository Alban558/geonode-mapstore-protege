#!/usr/bin/env bash
set -euo pipefail

GEOSERVER_URL="${GEOSERVER_LOCATION:-http://geoserver:8080/geoserver/}"
GEOSERVER_URL="${GEOSERVER_URL%/}"
GEOSERVER_REST_URL="${GEOSERVER_URL}/rest"
READER_ROLE="MAPSTORE_READ"
READER_WORKSPACE="geonode"
READER_LAYER="COMMUNE-1"
GEOFENCE_RULES_URL="${GEOSERVER_REST_URL}/geofence/rules"

: "${GEOSERVER_ADMIN_USER:?GEOSERVER_ADMIN_USER must be set}"
: "${GEOSERVER_ADMIN_PASSWORD:?GEOSERVER_ADMIN_PASSWORD must be set}"
: "${MAPSTORE_GEOSERVER_READER_USER:?MAPSTORE_GEOSERVER_READER_USER must be set}"
: "${MAPSTORE_GEOSERVER_READER_PASSWORD:?MAPSTORE_GEOSERVER_READER_PASSWORD must be set}"

if [[ ! "${MAPSTORE_GEOSERVER_READER_USER}" =~ ^[A-Za-z0-9._@+-]+$ ]]; then
    echo "MAPSTORE_GEOSERVER_READER_USER contains unsupported characters" >&2
    exit 1
fi

admin_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
    "${GEOSERVER_REST_URL}/about/version.xml")"
if [[ "${admin_status}" != "200" ]]; then
    echo "Configured GeoServer administrator authentication failed (HTTP ${admin_status})" >&2
    exit 1
fi

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    value="${value//\'/&apos;}"
    printf '%s' "${value}"
}

roles_xml="$(curl --silent --show-error --fail \
    --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
    -H 'Accept: application/xml' "${GEOSERVER_REST_URL}/security/roles.xml")"
if ! printf '%s' "${roles_xml}" | grep -Fq "<role>${READER_ROLE}</role>"; then
    role_xml="<role><name>${READER_ROLE}</name></role>"
    role_status="$(printf '%s' "${role_xml}" | curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
        -H 'Content-Type: application/xml' -X POST --data-binary @- \
        "${GEOSERVER_REST_URL}/security/roles/role/${READER_ROLE}")"
    if [[ "${role_status}" != "201" ]]; then
        echo "Creating GeoServer role ${READER_ROLE} failed (HTTP ${role_status})" >&2
        exit 1
    fi
fi

reader_wms_status() {
    curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${MAPSTORE_GEOSERVER_READER_USER}:${MAPSTORE_GEOSERVER_READER_PASSWORD}" \
        "${GEOSERVER_URL}/wms?service=WMS&request=GetCapabilities"
}

reader_status="$(reader_wms_status)"
if [[ "${reader_status}" != "200" ]]; then
    users_xml="$(curl --silent --show-error --fail \
        --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
        -H 'Accept: application/xml' "${GEOSERVER_REST_URL}/security/usergroup/users.xml")"
    if printf '%s' "${users_xml}" | grep -Fq "<userName>${MAPSTORE_GEOSERVER_READER_USER}</userName>"; then
        echo "GeoServer reader ${MAPSTORE_GEOSERVER_READER_USER} exists but its configured password was rejected" >&2
        exit 1
    fi

    user_xml="<user><userName>$(xml_escape "${MAPSTORE_GEOSERVER_READER_USER}")</userName><password>$(xml_escape "${MAPSTORE_GEOSERVER_READER_PASSWORD}")</password><enabled>true</enabled></user>"
    create_status="$(printf '%s' "${user_xml}" | curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
        -H 'Content-Type: application/xml' -X POST --data-binary @- \
        "${GEOSERVER_REST_URL}/security/usergroup/users")"
    if [[ "${create_status}" != "201" ]]; then
        echo "GeoServer reader creation failed (HTTP ${create_status})" >&2
        exit 1
    fi
fi

reader_roles="$(curl --silent --show-error --fail \
    --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
    -H 'Accept: application/xml' \
    "${GEOSERVER_REST_URL}/security/roles/user/${MAPSTORE_GEOSERVER_READER_USER}.xml")"
if printf '%s' "${reader_roles}" | grep -Eq '<role>(ADMIN|GROUP_ADMIN|ROLE_AUTHENTICATED)</role>'; then
    echo "GeoServer reader must not have administrator or write roles" >&2
    exit 1
fi
if ! printf '%s' "${reader_roles}" | grep -Fq "<role>${READER_ROLE}</role>"; then
    role_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" -X POST \
        "${GEOSERVER_REST_URL}/security/roles/role/${READER_ROLE}/user/${MAPSTORE_GEOSERVER_READER_USER}")"
    if [[ "${role_status}" != "200" ]]; then
        echo "Assigning GeoServer role ${READER_ROLE} failed (HTTP ${role_status})" >&2
        exit 1
    fi
fi

reader_geofence_rules="$(curl --silent --show-error --fail \
    --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
    -H 'Accept: application/xml' \
    "${GEOFENCE_RULES_URL}/?roleName=${READER_ROLE}&workspace=${READER_WORKSPACE}&layer=${READER_LAYER}&service=WMS")"
if printf '%s' "${reader_geofence_rules}" | grep -Fq "<roleName>${READER_ROLE}</roleName>"; then
    if ! printf '%s' "${reader_geofence_rules}" | grep -Fq '<access>ALLOW</access>'; then
        echo "An existing GeoFence rule for ${READER_ROLE} denies WMS access to ${READER_WORKSPACE}:${READER_LAYER}" >&2
        exit 1
    fi
else
    reader_rule="<Rule><access>ALLOW</access><priority>0</priority><roleName>${READER_ROLE}</roleName><workspace>${READER_WORKSPACE}</workspace><layer>${READER_LAYER}</layer><service>WMS</service></Rule>"
    rule_status="$(printf '%s' "${reader_rule}" | curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
        -H 'Content-Type: application/xml' -X POST --data-binary @- \
        "${GEOFENCE_RULES_URL}/")"
    if [[ "${rule_status}" != "201" ]]; then
        echo "Creating the GeoFence WMS rule for ${READER_ROLE} failed (HTTP ${rule_status})" >&2
        exit 1
    fi
fi

reader_gwc_rules="$(curl --silent --show-error --fail \
    --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
    -H 'Accept: application/xml' \
    "${GEOFENCE_RULES_URL}/?roleName=${READER_ROLE}&workspace=${READER_WORKSPACE}&layer=${READER_LAYER}&service=GWC")"
if printf '%s' "${reader_gwc_rules}" | grep -Fq "<roleName>${READER_ROLE}</roleName>"; then
    if ! printf '%s' "${reader_gwc_rules}" | grep -Fq '<access>ALLOW</access>'; then
        echo "An existing GeoFence rule for ${READER_ROLE} denies GWC access to ${READER_WORKSPACE}:${READER_LAYER}" >&2
        exit 1
    fi
else
    reader_gwc_rule="<Rule><access>ALLOW</access><priority>0</priority><roleName>${READER_ROLE}</roleName><workspace>${READER_WORKSPACE}</workspace><layer>${READER_LAYER}</layer><service>GWC</service></Rule>"
    gwc_rule_status="$(printf '%s' "${reader_gwc_rule}" | curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
        -H 'Content-Type: application/xml' -X POST --data-binary @- \
        "${GEOFENCE_RULES_URL}/")"
    if [[ "${gwc_rule_status}" != "201" ]]; then
        echo "Creating the GeoFence GWC rule for ${READER_ROLE} failed (HTTP ${gwc_rule_status})" >&2
        exit 1
    fi
fi

anonymous_geofence_rules="$(curl --silent --show-error --fail \
    --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
    -H 'Accept: application/xml' \
    "${GEOFENCE_RULES_URL}/?workspace=${READER_WORKSPACE}&layer=${READER_LAYER}&userAny=true&roleAny=true")"
anonymous_rule_ids="$(printf '%s' "${anonymous_geofence_rules}" \
    | grep -oE '<Rule id="[0-9]+">' \
    | sed -E 's/<Rule id="([0-9]+)">/\1/' || true)"
for rule_id in ${anonymous_rule_ids}; do
    delete_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" -X DELETE \
        "${GEOFENCE_RULES_URL}/id/${rule_id}")"
    if [[ "${delete_status}" != "200" ]]; then
        echo "Deleting public GeoFence rule ${rule_id} failed (HTTP ${delete_status})" >&2
        exit 1
    fi
done

reader_capabilities="$(curl --silent --show-error --fail \
    --user "${MAPSTORE_GEOSERVER_READER_USER}:${MAPSTORE_GEOSERVER_READER_PASSWORD}" \
    "${GEOSERVER_URL}/wms?service=WMS&request=GetCapabilities")"
layer_name="${READER_WORKSPACE}:${READER_LAYER}"
if ! printf '%s' "${reader_capabilities}" | grep -Fq "<Name>${layer_name}</Name>"; then
    echo "GeoServer reader is ready, but ${layer_name} is not published yet; rerun mapstore-reader-init after publishing it"
    exit 0
fi

anonymous_capabilities="$(curl --silent --show-error --fail \
    "${GEOSERVER_URL}/wms?service=WMS&request=GetCapabilities")"
if printf '%s' "${anonymous_capabilities}" | grep -Fq "<Name>${layer_name}</Name>"; then
    echo "Anonymous GeoServer access to ${layer_name} is still allowed" >&2
    exit 1
fi

map_url="${GEOSERVER_URL}/wms?service=WMS&version=1.1.1&request=GetMap&layers=${layer_name}&styles=&format=image/png&width=256&height=256&srs=EPSG:4326&bbox=-10,-10,10,10"
reader_map_type="$(curl --silent --show-error --output /dev/null --write-out '%{content_type}' \
    --user "${MAPSTORE_GEOSERVER_READER_USER}:${MAPSTORE_GEOSERVER_READER_PASSWORD}" "${map_url}")"
if [[ "${reader_map_type}" != "image/png" ]]; then
    echo "GeoServer reader GetMap returned ${reader_map_type}, expected image/png" >&2
    exit 1
fi

reader_gwc_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --user "${MAPSTORE_GEOSERVER_READER_USER}:${MAPSTORE_GEOSERVER_READER_PASSWORD}" \
    "${GEOSERVER_URL}/gwc/service/wmts?service=WMTS&REQUEST=DescribeDomains&version=1.0.0&layer=${layer_name}&tileMatrixSet=EPSG:4326&expandLimit=10")"
if [[ "${reader_gwc_status}" != "200" ]]; then
    echo "GeoServer reader WMTS DescribeDomains returned HTTP ${reader_gwc_status}, expected 200" >&2
    exit 1
fi

anonymous_map_type="$(curl --silent --show-error --output /dev/null --write-out '%{content_type}' "${map_url}")"
if [[ "${anonymous_map_type}" == "image/png" ]]; then
    echo "Anonymous GeoServer GetMap access to ${layer_name} is still allowed" >&2
    exit 1
fi

echo "GeoServer reader ${MAPSTORE_GEOSERVER_READER_USER} can view ${layer_name} with ${READER_ROLE}; anonymous access is denied"
