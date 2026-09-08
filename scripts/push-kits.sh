#!/usr/bin/env bash
set -euo pipefail

# Publishes both mixins in this repo as tags of a single OCI image:
#   docker.io/<namespace>/sbx-kits-panw:endpoint-enforcement
#   docker.io/<namespace>/sbx-kits-panw:siem-telemetry
#
# Override the namespace with DOCKERHUB_NAMESPACE (CI sets it to the Docker Hub
# username). Requires an authenticated Docker credential store + `sbx login`
# (see .github/workflows/push-kits.yaml).

namespace="${DOCKERHUB_NAMESPACE:-${DOCKER_NAMESPACE:-ajeetraina777}}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="docker.io/$namespace/sbx-kits-panw"

# publish KIT_DIR IMAGE_TAG [VALIDATE_ARGS...]
# Stages the whole kit (spec.yaml + README + files/ + LICENSE), validates it,
# and pushes one tag. The full directory is copied so kits carrying a files/
# tree (siem-telemetry) publish their bundled files too.
publish() {
  local kit_dir="$1" image_tag="$2"; shift 2
  local stage
  stage="$(mktemp -d /tmp/sbx-kits-panw-push.XXXXXX)"
  cp -R "$kit_dir/." "$stage/kit/"
  cp "$repo_root/LICENSE" "$stage/kit/LICENSE"
  sbx kit validate "$stage/kit" "$@"
  sbx kit push "$stage/kit" "$image:$image_tag"
  rm -rf "$stage"
  echo "Pushed $image:$image_tag"
}

# Where an agent may run.
publish "$repo_root/endpoint-enforcement" "endpoint-enforcement"

# What an agent did. siemCollectorHost is required, so pass a placeholder for
# the pre-push validate (the real value is supplied at `sbx run` time).
publish "$repo_root/siem-telemetry" "siem-telemetry" \
  --kit-arg siemCollectorHost=collector.example.internal
