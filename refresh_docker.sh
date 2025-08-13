#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  refresh_docker.sh -n <name> [-b <build_context_dir>]

Arguments:
  -n   Base name to derive container and image names from
  -b   Build context directory for docker build (default: .)
  -d   Docker Compose directory to restart services (default: /mcp-docker/traefik-mcp)

Examples:
  refresh_docker.sh -n my_app
  refresh_docker.sh -n my_app -b ./app -d /mcp-docker/traefik-mcp

EOF
}

NAME=""
BUILD_CONTEXT="."
COMPOSE_DIR="/mcp-docker/traefik-mcp"

while getopts ":n:b:d:h" opt; do
  case "$opt" in
    n) NAME="$OPTARG" ;;
    b) BUILD_CONTEXT="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Error: Invalid option -$OPTARG" >&2; usage; exit 1 ;;
    :) echo "Error: Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

IMAGE="mcp-${NAME}"
CONTAINER="${NAME}-container"

if [[ -z "${NAME}" ]]; then
  echo "Error: -n <name> is required." >&2
  usage
  exit 1
fi

# Preconditions
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker command not found. Please install Docker." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: 'docker compose' plugin not available. Install or enable Docker Compose v2." >&2
  exit 1
fi

echo "=== 1) Prune dangling images ==="
docker image prune -f

echo
echo "=== 2) List images and containers BEFORE cleanup ==="
docker images
echo
docker ps -a

echo
echo "=== 3) Remove old container (if it exists) ==="
if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER}"; then
  echo "Removing container: ${CONTAINER}"
  docker rm -f "${CONTAINER}"
else
  # Also allow removal by ID if name check failed
  if docker ps -a --format '{{.ID}}' | grep -Fxq "${CONTAINER}"; then
    echo "Removing container by ID: ${CONTAINER}"
    docker rm -f "${CONTAINER}"
  else
    echo "Container '${CONTAINER}' not found. Skipping removal."
  fi
fi

echo
echo "=== 4) Remove image (if it exists) ==="
IMAGE_ID="$(docker images -q "${IMAGE}" || true)"
if [[ -n "${IMAGE_ID}" ]]; then
  echo "Removing image: ${IMAGE}"
  docker rmi "${IMAGE}" || {
    echo "Failed to remove image '${IMAGE}'. It may still be in use." >&2
    exit 1
  }
else
  echo "Image '${IMAGE}' not found. Skipping removal."
fi

echo
echo "=== 5) Rebuild image ==="
echo "Build context: ${BUILD_CONTEXT}"
docker build -t "${IMAGE}" "${BUILD_CONTEXT}"

echo
echo "=== 6) Restart services with Docker Compose ==="
if [[ -d "${COMPOSE_DIR}" ]]; then
  pushd "${COMPOSE_DIR}" >/dev/null
  docker compose up -d "${NAME}"
  popd >/dev/null
else
  echo "Warning: Compose directory '${COMPOSE_DIR}' not found. Skipping docker compose up -d."
fi

echo
echo "=== 7) List images and containers AFTER rebuild/restart ==="
docker images
echo
docker ps -a

echo
echo "Done."