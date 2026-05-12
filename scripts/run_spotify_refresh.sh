#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/jeremymarchandeau/Code/personal/projects/personal_warehouse/personal_warehouse"
VENV_DIR="/Users/jeremymarchandeau/Code/personal/projects/personal_warehouse/.venv"
ENV_FILE="${PROJECT_DIR}/.env"

cd "${PROJECT_DIR}"

"${VENV_DIR}/bin/python" scripts/spotify_to_bq.py
"${VENV_DIR}/bin/dbt" build --select tag:spotify+

netlify_build_hook_url=""
if [[ -f "${ENV_FILE}" ]]; then
    netlify_build_hook_url="$(
        { grep -E '^NETLIFY_BUILD_HOOK_URL=' "${ENV_FILE}" || true; } \
            | tail -n 1 \
            | cut -d '=' -f 2- \
            | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
    )"
fi

if [[ -n "${netlify_build_hook_url}" && "${netlify_build_hook_url}" != "your_netlify_build_hook_url_here" ]]; then
    curl --fail --silent --show-error -X POST "${netlify_build_hook_url}"
else
    echo "NETLIFY_BUILD_HOOK_URL is not set; skipping dashboard rebuild."
fi
