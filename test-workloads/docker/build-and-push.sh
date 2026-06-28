#!/bin/bash
#
# Build and push jwt-svid-test-client image
#

set -euo pipefail

# Configuration
REGISTRY="${REGISTRY:-quay.io}"
REGISTRY_USER="${REGISTRY_USER:-}"
IMAGE_NAME="jwt-svid-test-client"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Detect container runtime
if command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
else
    echo "Error: Neither podman nor docker found"
    exit 1
fi

echo "Using container runtime: $CONTAINER_RUNTIME"

# Check if REGISTRY_USER is set
if [ -z "$REGISTRY_USER" ]; then
    echo "Error: REGISTRY_USER environment variable is not set"
    echo ""
    echo "Usage:"
    echo "  export REGISTRY_USER=<your-username>"
    echo "  $0"
    echo ""
    echo "Example:"
    echo "  export REGISTRY_USER=kamorisan"
    echo "  export REGISTRY=quay.io"
    echo "  $0"
    exit 1
fi

FULL_IMAGE="${REGISTRY}/${REGISTRY_USER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building image: $FULL_IMAGE"
echo ""

# Build image
cd "$(dirname "$0")"
$CONTAINER_RUNTIME build -t "$FULL_IMAGE" -f Dockerfile ..

echo ""
echo "Image built successfully!"
echo ""
echo "To push the image:"
echo "  $CONTAINER_RUNTIME login $REGISTRY"
echo "  $CONTAINER_RUNTIME push $FULL_IMAGE"
echo ""
echo "To use in deployment, update test-workloads/base/jwt-test-client.yaml:"
echo "  image: $FULL_IMAGE"
