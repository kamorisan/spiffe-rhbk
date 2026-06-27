#!/bin/bash
#
# Enable TRACE logging for Keycloak SPIFFE authentication
#
# This script enables detailed logging for debugging JWT-SVID authentication issues
#
# Usage:
#   ./enable-keycloak-trace-logging.sh

set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-rhbk-demo}"

echo "=== Enable Keycloak TRACE Logging ==="
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

# Enable TRACE logging for SPIFFE-related components
echo ""
echo "3. Enabling TRACE logging..."

oc exec "$KEYCLOAK_POD" -n "$KEYCLOAK_NAMESPACE" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user temp-admin \
  --password '$ADMIN_PASSWORD' \
  --config /tmp/kcadm.config >/dev/null 2>&1

# Enable TRACE for authentication flows
/opt/keycloak/bin/kcadm.sh set-log-level org.keycloak.authentication TRACE --config /tmp/kcadm.config
/opt/keycloak/bin/kcadm.sh set-log-level org.keycloak.authentication.authenticators TRACE --config /tmp/kcadm.config

# Enable TRACE for federated JWT
/opt/keycloak/bin/kcadm.sh set-log-level org.keycloak.authentication.authenticators.client TRACE --config /tmp/kcadm.config

# Enable TRACE for SPIFFE provider
/opt/keycloak/bin/kcadm.sh set-log-level org.keycloak.broker.spiffe TRACE --config /tmp/kcadm.config

# Enable TRACE for events
/opt/keycloak/bin/kcadm.sh set-log-level org.keycloak.events TRACE --config /tmp/kcadm.config

echo 'TRACE logging enabled'
"

echo "✓ TRACE logging enabled for:"
echo "  - org.keycloak.authentication"
echo "  - org.keycloak.authentication.authenticators"
echo "  - org.keycloak.authentication.authenticators.client"
echo "  - org.keycloak.broker.spiffe"
echo "  - org.keycloak.events"

echo ""
echo "=== Logging Configuration Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run authentication test: ./scripts/test-jwt-svid-complete.sh"
echo "  2. Check logs: oc logs keycloak-0 -n rhbk-demo -f"
echo ""
