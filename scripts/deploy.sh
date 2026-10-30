#!/usr/bin/env bash
# Usage: scripts/deploy.sh [--dry-run]
set -euo pipefail

fail() { printf 'Deploy error: %s\n' "$*" >&2; exit 1; }
DRY_RUN=false
case "$#:$*" in
    0:) ;;
    1:--dry-run) DRY_RUN=true ;;
    *) fail 'usage: deploy.sh [--dry-run]' ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || fail 'script is not in a Git repository'
LOCAL_DIR="$REPO_ROOT/site/"
REMOTE='devops'
REMOTE_DIR='/var/www/devops-site/'
SITE_URL='https://devops.local/'
CA_CERT="${DEPLOY_CA_CERT:-${HOME}/devops.crt}"

[[ -f "${LOCAL_DIR}index.html" ]] || fail 'site/index.html is missing; nothing was synchronized'
[[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal)" ]] || fail 'uncommitted changes exist, including staged or untracked files; nothing was synchronized'
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

if ! "$DRY_RUN"; then
    [[ -r "$CA_CERT" ]] || fail "trusted certificate is not readable: $CA_CERT"
fi

RSYNC_ARGS=(-avz --delete --chmod=D755,F644 -e 'ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1')
if "$DRY_RUN"; then RSYNC_ARGS+=(--dry-run); fi
# This is the only SSH connection opened by this script.
rsync "${RSYNC_ARGS[@]}" -- "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}" || fail 'rsync failed'
if "$DRY_RUN"; then
    printf 'Dry run for commit %s completed; server content was not changed.\n' "$COMMIT"
    exit 0
fi

CURL_ARGS=(--fail --silent --show-error --connect-timeout 5 --max-time 15 --noproxy '*' --cacert "$CA_CERT" --output /dev/null --write-out '%{http_code}')
# Optional routing for a local NAT lab behind a VPN. Host and TLS SNI stay unchanged.
if [[ -n "${DEPLOY_RESOLVE:-}" ]]; then CURL_ARGS+=(--resolve "$DEPLOY_RESOLVE"); fi
HTTP_CODE="$(curl "${CURL_ARGS[@]}" "$SITE_URL")" || fail 'HTTPS availability or certificate verification failed'
[[ "$HTTP_CODE" == 200 ]] || fail "unexpected HTTP status: $HTTP_CODE"
printf 'Deployed commit %s; verified HTTPS status %s.\n' "$COMMIT" "$HTTP_CODE"
