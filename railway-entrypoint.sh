#!/bin/bash
# Boot sequence for New API on Railway.
#
# The public port is opened only by the final exec. Everything before it runs
# against a temporary instance bound to an internal port that Railway's edge does
# not route, so there is no window in which a stranger can reach an unclaimed
# instance and take it over through POST /api/setup.
set -euo pipefail

log() { echo "[railway-entrypoint] $*"; }

ADMIN_USER="${NEW_API_ADMIN_USERNAME:-admin}"

if [ -z "${NEW_API_ADMIN_PASSWORD:-}" ]; then
    log "FATAL: NEW_API_ADMIN_PASSWORD is empty. Refusing to boot an instance that anyone could claim."
    exit 1
fi
if [ "${#NEW_API_ADMIN_PASSWORD}" -lt 8 ] || [ "${#NEW_API_ADMIN_PASSWORD}" -gt 20 ]; then
    log "FATAL: NEW_API_ADMIN_PASSWORD must be 8-20 characters (New API validates min=8,max=20)."
    exit 1
fi
if [ "${#ADMIN_USER}" -gt 12 ]; then
    log "FATAL: NEW_API_ADMIN_USERNAME must be at most 12 characters."
    exit 1
fi

SETUP_PORT="${NEW_API_SETUP_PORT:-13000}"
BASE="http://127.0.0.1:${SETUP_PORT}"

log "starting temporary instance on ${SETUP_PORT} for administrator seeding"
PORT="${SETUP_PORT}" /new-api &
BOOT_PID=$!

ready=0
for _ in $(seq 1 120); do
    if ! kill -0 "${BOOT_PID}" 2>/dev/null; then
        log "FATAL: New API exited during the seeding boot."
        wait "${BOOT_PID}" || true
        exit 1
    fi
    if curl -fsS -m 3 "${BASE}/api/status" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [ "${ready}" -ne 1 ]; then
    log "FATAL: New API did not answer /api/status within 240s during seeding."
    kill "${BOOT_PID}" 2>/dev/null || true
    exit 1
fi

setup_state="$(curl -fsS -m 10 "${BASE}/api/setup" || echo '')"
log "setup state: ${setup_state}"

if echo "${setup_state}" | grep -q '"status":false'; then
    log "no administrator yet; seeding ${ADMIN_USER} through the loopback setup endpoint"
    body="$(ADMIN_USER="${ADMIN_USER}" python3 - <<'PY'
import json, os
print(json.dumps({
    "username": os.environ["ADMIN_USER"],
    "password": os.environ["NEW_API_ADMIN_PASSWORD"],
    "confirmPassword": os.environ["NEW_API_ADMIN_PASSWORD"],
    "SelfUseModeEnabled": os.environ.get("NEW_API_SELF_USE_MODE", "false").lower() == "true",
    "DemoSiteEnabled": False,
}))
PY
)"
    resp="$(curl -fsS -m 30 -X POST "${BASE}/api/setup" -H 'Content-Type: application/json' -d "${body}" || echo '')"
    log "setup response: ${resp}"
    if ! echo "${resp}" | grep -q '"success":true'; then
        log "FATAL: administrator seeding failed."
        kill "${BOOT_PID}" 2>/dev/null || true
        exit 1
    fi
else
    log "instance already initialised; re-applying the administrator credential"
    if [ -z "${SQL_DSN:-}" ]; then
        log "WARNING: SQL_DSN is unset, cannot re-apply the administrator credential on this boot."
    else
        stored="$(python3 - <<'PY'
import bcrypt, os
print(bcrypt.hashpw(os.environ["NEW_API_ADMIN_PASSWORD"].encode(), bcrypt.gensalt()).decode())
PY
)"
        # Role 100 is New API's root administrator (common.RoleRootUser). The
        # column holds a bcrypt digest, never a plaintext value.
        PGCONNECT_TIMEOUT=10 psql "${SQL_DSN}" -v ON_ERROR_STOP=1 -q \
            -c "UPDATE users SET password = '${stored}', username = '${ADMIN_USER}' WHERE role >= 100;"
        log "administrator credential re-applied (a redeploy is therefore an account recovery)"
    fi
fi

log "stopping the temporary instance"
kill "${BOOT_PID}" 2>/dev/null || true
wait "${BOOT_PID}" 2>/dev/null || true

log "starting New API on the Railway port ${PORT:-3000}"
exec /new-api "$@"
