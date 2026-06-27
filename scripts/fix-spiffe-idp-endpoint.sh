#!/bin/bash
#
# Fix SPIFFE Identity Provider Bundle Endpoint
#
# This script updates the SPIFFE IdP bundle endpoint to use the correct namespace
#
# Usage:
#   ./fix-spiffe-idp-endpoint.sh

set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-rhbk-demo}"
REALM="${REALM:-spiffe}"
IDP_ALIAS="${IDP_ALIAS:-spiffe}"

# Correct namespace for Operator-managed SPIRE Server
CORRECT_BUNDLE_ENDPOINT="https://spire-server.zero-trust-workload-identity-manager.svc.cluster.local:8443"

echo "=== Fix SPIFFE Identity Provider Bundle Endpoint ==="
echo ""

# Get Keycloak Pod
echo "1. Finding Keycloak Pod..."
KEYCLOAK_POD=$(oc get pod -n "$KEYCLOAK_NAMESPACE" -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$KEYCLOAK_POD" ]; then
    echo "✗ Keycloak Pod not found"
    exit 1
fi

echo "✓ Keycloak Pod: $KEYCLOAK_POD"

# Get Admin Password
echo ""
echo "2. Retrieving Admin Password..."
ADMIN_PASSWORD=$(oc get secret keycloak-initial-admin -n "$KEYCLOAK_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

# Get Current IdP Configuration
echo ""
echo "3. Checking current SPIFFE IdP configuration..."

CURRENT_CONFIG=$(oc exec "$KEYCLOAK_POD" -n "$KEYCLOAK_NAMESPACE" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user temp-admin \
  --password '$ADMIN_PASSWORD' \
  --config /tmp/kcadm.config >/dev/null 2>&1

/opt/keycloak/bin/kcadm.sh get identity-provider/instances/$IDP_ALIAS -r $REALM \
  --config /tmp/kcadm.config
" 2>/dev/null)

CURRENT_ENDPOINT=$(echo "$CURRENT_CONFIG" | python3 -m json.tool | grep -A 1 '"bundleEndpoint"' | tail -1 | sed 's/.*"\(.*\)".*/\1/')

echo "  Current bundleEndpoint: $CURRENT_ENDPOINT"
echo "  Correct bundleEndpoint: $CORRECT_BUNDLE_ENDPOINT"

if [ "$CURRENT_ENDPOINT" = "$CORRECT_BUNDLE_ENDPOINT" ]; then
    echo ""
    echo "✓ Bundle endpoint is already correct"
    exit 0
fi

# Update Bundle Endpoint
echo ""
echo "4. Updating bundle endpoint..."

oc exec "$KEYCLOAK_POD" -n "$KEYCLOAK_NAMESPACE" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user temp-admin \
  --password '$ADMIN_PASSWORD' \
  --config /tmp/kcadm.config >/dev/null 2>&1

/opt/keycloak/bin/kcadm.sh update identity-provider/instances/$IDP_ALIAS -r $REALM \
  -s config.bundleEndpoint='$CORRECT_BUNDLE_ENDPOINT' \
  --config /tmp/kcadm.config
"

# Verify Update
echo ""
echo "5. Verifying configuration..."

UPDATED_CONFIG=$(oc exec "$KEYCLOAK_POD" -n "$KEYCLOAK_NAMESPACE" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user temp-admin \
  --password '$ADMIN_PASSWORD' \
  --config /tmp/kcadm.config >/dev/null 2>&1

/opt/keycloak/bin/kcadm.sh get identity-provider/instances/$IDP_ALIAS -r $REALM \
  --config /tmp/kcadm.config
" 2>/dev/null)

UPDATED_ENDPOINT=$(echo "$UPDATED_CONFIG" | python3 -m json.tool | grep -A 1 '"bundleEndpoint"' | tail -1 | sed 's/.*"\(.*\)".*/\1/')

if [ "$UPDATED_ENDPOINT" = "$CORRECT_BUNDLE_ENDPOINT" ]; then
    echo "✓ Bundle endpoint updated successfully"
    echo "  bundleEndpoint: $UPDATED_ENDPOINT"
else
    echo "✗ Bundle endpoint update failed"
    echo "  Expected: $CORRECT_BUNDLE_ENDPOINT"
    echo "  Got: $UPDATED_ENDPOINT"
    exit 1
fi

# Restart Keycloak to clear caches
echo ""
echo "6. Restarting Keycloak pod to clear caches..."
oc delete pod "$KEYCLOAK_POD" -n "$KEYCLOAK_NAMESPACE"
echo "  Waiting for Keycloak to be ready..."
oc wait --for=condition=Ready pod -l app=keycloak -n "$KEYCLOAK_NAMESPACE" --timeout=180s

echo ""
echo "=== Bundle Endpoint Fix Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run authentication test: ./scripts/test-jwt-svid-complete.sh"
echo ""
