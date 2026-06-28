# JWT-SVID Test Client Image

This directory contains a custom container image for JWT-SVID authentication testing.

## Image Details

**Base Image**: `registry.redhat.io/ubi9/ubi:latest`

**Includes**:
- `spire-agent` binary (copied from SPIRE Agent RHEL9 image)
- curl, jq (for testing)

## Why Custom Image?

The custom image solves the following problems:

1. **Binary Compatibility**: Direct binary copy from SPIRE Agent Pod to test client Pod causes segfault
2. **Image Stability**: Upstream base images (wolfi-base) update frequently, breaking compatibility
3. **Reproducibility**: Pod restarts don't require manual spire-agent binary installation
4. **GitOps Ready**: Fully automated deployment without manual intervention

## Build and Push

```bash
# Login to registry
podman login quay.io

# Build image
podman build -t quay.io/<your-username>/jwt-svid-test-client:latest \
  -f test-workloads/docker/Dockerfile .

# Push image
podman push quay.io/<your-username>/jwt-svid-test-client:latest
```

## Update Deployment

After pushing the image, update `test-workloads/base/jwt-test-client.yaml`:

```yaml
containers:
- name: client
  image: quay.io/<your-username>/jwt-svid-test-client:latest
  command: ["/bin/bash", "-c", "sleep infinity"]
```

## Verify

```bash
# Get pod
POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client -o jsonpath='{.items[0].metadata.name}')

# Test spire-agent binary
oc exec $POD -n rhbk-demo -c client -- /usr/local/bin/spire-agent --version

# Test JWT-SVID fetch
oc exec $POD -n rhbk-demo -c client -- \
  /usr/local/bin/spire-agent api fetch jwt \
  -audience "https://keycloak-rhbk-demo.apps.CLUSTER/realms/spiffe" \
  -socketPath /spiffe-workload-api/spire-agent.sock
```

## Image Registry Options

- **Quay.io** (推奨): `quay.io/<username>/jwt-svid-test-client`
- **Docker Hub**: `docker.io/<username>/jwt-svid-test-client`
- **GitHub Container Registry**: `ghcr.io/<username>/jwt-svid-test-client`
- **Internal Registry**: Use OpenShift internal registry if available

## Update Image

To update to a newer SPIRE Agent version, change the digest in Dockerfile:

```dockerfile
FROM registry.redhat.io/zero-trust-workload-identity-manager/spiffe-spire-agent-rhel9@sha256:NEW_DIGEST AS spire
```
