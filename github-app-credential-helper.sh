#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

operation="${1:-}"

if [ "$operation" != "get" ]; then
    exit 0
fi

CONFIG_FILE="${GITHUB_APP_CREDENTIAL_CONFIG:-$PWD/config.env}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "git-credential-github-app: config file not found: $CONFIG_FILE" >&2
    echo "quit=true"
    exit 0
fi

# shellcheck disable=SC1090
. "$CONFIG_FILE"

: "${GITHUB_APP_CLIENT_ID:?GITHUB_APP_CLIENT_ID is required}"
: "${PRIVATE_KEY_PATH:?PRIVATE_KEY_PATH is required}"
GITHUB_API_VERSION="${GITHUB_API_VERSION:-2026-03-10}"

protocol=""
host=""
path=""

while IFS='=' read -r key value; do
    case "$key" in
    protocol) protocol="$value" ;;
    host) host="$value" ;;
    path) path="$value" ;;
    esac
done

if [ "$protocol" != "https" ] || [ "$host" != "github.com" ]; then
    exit 0
fi

if [ -z "$path" ]; then
    echo "git-credential-github-app: path is empty. Set credential.https://github.com.useHttpPath=true" >&2
    echo "quit=true"
    exit 0
fi

repo_path="${path%.git}"

owner="$(printf '%s' "$repo_path" | cut -d/ -f1)"
repo="$(printf '%s' "$repo_path" | cut -d/ -f2)"

if [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$repo_path" ]; then
    echo "git-credential-github-app: cannot parse repository path: $path" >&2
    echo "quit=true"
    exit 0
fi

b64url() {
    openssl base64 -A | tr '+/' '-_' | tr -d '='
}

generate_jwt() {
    now="$(date +%s)"
    iat="$((now - 60))"
    exp="$((now + 600))"

    header='{"alg":"RS256","typ":"JWT"}'
    payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
        "$iat" "$exp" "$GITHUB_APP_CLIENT_ID")"

    header_b64="$(printf '%s' "$header" | b64url)"
    payload_b64="$(printf '%s' "$payload" | b64url)"
    unsigned="${header_b64}.${payload_b64}"

    signature_b64="$(
        printf '%s' "$unsigned" |
            openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" -binary |
            b64url
    )"

    printf '%s.%s\n' "$unsigned" "$signature_b64"
}

jwt="$(generate_jwt)"

installation_id="$(
    curl -fsS \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${jwt}" \
        -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" \
        "https://api.github.com/repos/${owner}/${repo}/installation" |
        jq -r '.id'
)"

if [ -z "$installation_id" ] || [ "$installation_id" = "null" ]; then
    echo "git-credential-github-app: installation not found for ${owner}/${repo}" >&2
    echo "quit=true"
    exit 0
fi

token="$(
    curl -fsS -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${jwt}" \
        -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" \
        "https://api.github.com/app/installations/${installation_id}/access_tokens" |
        jq -r '.token'
)"

if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "git-credential-github-app: failed to create installation access token" >&2
    echo "quit=true"
    exit 0
fi

cat <<EOF
username=x-access-token
password=${token}
EOF
