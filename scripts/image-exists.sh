#!/usr/bin/env bash
# Exits 0 if the app image ghcr.io/altinn/altinn-profile:<tag> exists, 1 if the tag is missing.
# The image is public, so no login is needed.
#
#   scripts/image-exists.sh 1.4.0
set -euo pipefail

tag="${1:?usage: image-exists.sh <tag>}"
repo="altinn/altinn-profile"

token="$(curl -fsS "https://ghcr.io/token?scope=repository:${repo}:pull" | jq -r .token)"

code="$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${token}" \
  -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/${repo}/manifests/${tag}")"

case "${code}" in
  200) exit 0 ;;
  404) exit 1 ;;
  *)
    echo "::error::Could not check ghcr.io/${repo}:${tag} (HTTP ${code})"
    exit 2
    ;;
esac
