#!/usr/bin/env bash
set -euo pipefail

GEOSERVER_URL="${GEOSERVER_LOCATION:-http://geoserver:8080/geoserver/}"
GEOSERVER_URL="${GEOSERVER_URL%/}"
GEOSERVER_REST_URL="${GEOSERVER_URL}/rest"
GEOSERVER_BOOTSTRAP_USER="${GEOSERVER_BOOTSTRAP_USER:-admin}"
GEOSERVER_BOOTSTRAP_PASSWORD="${GEOSERVER_BOOTSTRAP_PASSWORD:-geoserver}"

: "${GEOSERVER_ADMIN_USER:?GEOSERVER_ADMIN_USER must be set}"
: "${GEOSERVER_ADMIN_PASSWORD:?GEOSERVER_ADMIN_PASSWORD must be set}"

if [[ ! "${GEOSERVER_ADMIN_USER}" =~ ^[A-Za-z0-9._@+-]+$ ]]; then
    echo "GEOSERVER_ADMIN_USER contains unsupported characters" >&2
    exit 1
fi

auth_status() {
    curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "$1:$2" "${GEOSERVER_REST_URL}/about/version.xml"
}

echo "Waiting for GeoServer"
for _ in $(seq 1 60); do
    if curl --silent --fail --output /dev/null \
        "${GEOSERVER_URL}/web/wicket/resource/org.geoserver.web.GeoServerBasePage/img/logo.png"; then
        break
    fi
    sleep 5
done

target_status="$(auth_status "${GEOSERVER_ADMIN_USER}" "${GEOSERVER_ADMIN_PASSWORD}")"
if [[ "${target_status}" == "200" ]]; then
    auth_user="${GEOSERVER_ADMIN_USER}"
    auth_password="${GEOSERVER_ADMIN_PASSWORD}"
else
    if [[ "${GEOSERVER_ADMIN_USER}" == "${GEOSERVER_BOOTSTRAP_USER}" ]]; then
        echo "Configured GeoServer admin username matches the bootstrap username, but its password was rejected" >&2
        exit 1
    fi

    bootstrap_status="$(auth_status "${GEOSERVER_BOOTSTRAP_USER}" "${GEOSERVER_BOOTSTRAP_PASSWORD}")"
    if [[ "${bootstrap_status}" != "200" ]]; then
        echo "Cannot authenticate with the configured admin or bootstrap credentials (HTTP ${target_status}/${bootstrap_status})" >&2
        exit 1
    fi

    users_xml="$(curl --silent --show-error --fail \
        --user "${GEOSERVER_BOOTSTRAP_USER}:${GEOSERVER_BOOTSTRAP_PASSWORD}" \
        -H 'Accept: application/xml' "${GEOSERVER_REST_URL}/security/usergroup/users.xml")"
    if printf '%s' "${users_xml}" | grep -Fq "<userName>${GEOSERVER_ADMIN_USER}</userName>"; then
        echo "GeoServer user ${GEOSERVER_ADMIN_USER} already exists but its configured password was rejected; refusing to overwrite it" >&2
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

    user_xml="<user><userName>$(xml_escape "${GEOSERVER_ADMIN_USER}")</userName><password>$(xml_escape "${GEOSERVER_ADMIN_PASSWORD}")</password><enabled>true</enabled></user>"
    create_status="$(printf '%s' "${user_xml}" | curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --user "${GEOSERVER_BOOTSTRAP_USER}:${GEOSERVER_BOOTSTRAP_PASSWORD}" \
        -H 'Content-Type: application/xml' -X POST --data-binary @- \
        "${GEOSERVER_REST_URL}/security/usergroup/users")"
    if [[ "${create_status}" != "201" ]]; then
        echo "GeoServer user creation failed (HTTP ${create_status})" >&2
        exit 1
    fi

    auth_user="${GEOSERVER_BOOTSTRAP_USER}"
    auth_password="${GEOSERVER_BOOTSTRAP_PASSWORD}"
fi

for role in ADMIN GROUP_ADMIN; do
    roles_xml="$(curl --silent --show-error --fail \
        --user "${auth_user}:${auth_password}" \
        -H 'Accept: application/xml' \
        "${GEOSERVER_REST_URL}/security/roles/user/${GEOSERVER_ADMIN_USER}.xml")"
    if ! printf '%s' "${roles_xml}" | grep -Fq "<role>${role}</role>"; then
        role_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
            --user "${auth_user}:${auth_password}" -X POST \
            "${GEOSERVER_REST_URL}/security/roles/role/${role}/user/${GEOSERVER_ADMIN_USER}")"
        if [[ "${role_status}" != "200" ]]; then
            echo "Granting GeoServer role ${role} failed (HTTP ${role_status})" >&2
            exit 1
        fi
    fi
done

if [[ "$(auth_status "${GEOSERVER_ADMIN_USER}" "${GEOSERVER_ADMIN_PASSWORD}")" != "200" ]]; then
    echo "GeoServer administrator authentication verification failed" >&2
    exit 1
fi

verified_roles="$(curl --silent --show-error --fail \
    --user "${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}" \
    -H 'Accept: application/xml' \
    "${GEOSERVER_REST_URL}/security/roles/user/${GEOSERVER_ADMIN_USER}.xml")"
for role in ADMIN GROUP_ADMIN; do
    if ! printf '%s' "${verified_roles}" | grep -Fq "<role>${role}</role>"; then
        echo "GeoServer administrator is missing role ${role}" >&2
        exit 1
    fi
done

echo "GeoServer administrator ${GEOSERVER_ADMIN_USER} is ready with ADMIN and GROUP_ADMIN roles"
