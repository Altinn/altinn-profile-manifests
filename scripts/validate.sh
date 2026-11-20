#!/usr/bin/env bash
# Checks everything that can be checked before Flux applies it. One environment per directory in
# manifests/image/, and each needs a pre-deploy overlay, a deploy overlay and a syncroot overlay.
#
#   scripts/validate.sh
#   SKIP_IMAGE_CHECK=1 scripts/validate.sh   # offline: do not look for the pinned images
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP_IMAGE=altinncr.azurecr.io/ghcr.io/altinn/altinn-profile
tag_re='^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$'

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

failed=0
err() { echo "::error::$*"; failed=1; }

envs="$(ls manifests/image)"
[ -n "${envs}" ] || { err "No environments found in manifests/image"; exit 1; }

checked_tags=" "
for env in ${envs}; do
  echo "== ${env}"

  # Every overlay has to build.
  for dir in "manifests/pre-deploy/${env}" "manifests/deploy/${env}" "flux/syncroot/${env}"; do
    if [ ! -f "${dir}/kustomization.yaml" ]; then
      err "Missing ${dir}/kustomization.yaml"
      continue
    fi
    out="${tmp}/$(echo "${dir}" | tr '/' '_').yaml"
    if ! kubectl kustomize "${dir}" > "${out}" 2> "${tmp}/stderr"; then
      err "${dir} does not build: $(cat "${tmp}/stderr")"
    fi
  done

  # The syncroot overlay has to point Flux at this environment. A patch aimed at the wrong
  # resource name parses fine but never applies, so assert on the rendered output.
  syncroot="${tmp}/flux_syncroot_${env}.yaml"
  if [ -s "${syncroot}" ]; then
    want_tag="$(yq 'select(.kind == "OCIRepository") | .spec.ref.tag' "${syncroot}")"
    [ "${want_tag}" = "${env}" ] || err "flux/syncroot/${env}: the OCIRepository follows tag '${want_tag}', not '${env}'"

    for pair in "profile-pre-deploy=./pre-deploy/${env}" "profile-deploy=./deploy/${env}"; do
      name="${pair%%=*}"
      expected="${pair#*=}"
      got="$(yq "select(.kind == \"Kustomization\" and .metadata.name == \"${name}\") | .spec.path" "${syncroot}")"
      [ "${got}" = "${expected}" ] || err "flux/syncroot/${env}: ${name} has path '${got}', expected '${expected}'"
    done
  fi

  # The app image of both stages is the one pinned for this environment.
  pin="$(yq '.images[0].newTag' "manifests/image/${env}/kustomization.yaml")"
  if [[ ! "${pin}" =~ ${tag_re} ]]; then
    err "manifests/image/${env}: '${pin}' is not a valid image tag"
    continue
  fi
  for stage in pre-deploy deploy; do
    rendered="${tmp}/manifests_${stage}_${env}.yaml"
    [ -s "${rendered}" ] || continue
    if grep -q '{{' "${rendered}"; then
      err "manifests/${stage}/${env}: unreplaced placeholder in the rendered output"
    fi
    while read -r image; do
      [ "${image}" = "${APP_IMAGE}:${pin}" ] || err "manifests/${stage}/${env}: image '${image}', expected '${APP_IMAGE}:${pin}'"
    done < <(grep -E '^[[:space:]]+image:' "${rendered}" | sed -E 's/^[[:space:]]+image:[[:space:]]*//; s/^["'\'']//; s/["'\'']$//')
  done

  # And that image exists.
  if [ -z "${SKIP_IMAGE_CHECK:-}" ] && [[ "${checked_tags}" != *" ${pin} "* ]]; then
    checked_tags="${checked_tags}${pin} "
    scripts/image-exists.sh "${pin}"
    case $? in
      0) echo "image ${pin} exists" ;;
      1) err "manifests/image/${env} pins ${pin}, but ghcr.io/altinn/altinn-profile:${pin} does not exist" ;;
      *) failed=1 ;;
    esac
  fi
done

exit "${failed}"
