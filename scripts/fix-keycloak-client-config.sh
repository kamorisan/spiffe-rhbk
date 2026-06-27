#!/bin/bash
#
# Fix Keycloak Client Configuration for JWT-SVID Authentication
#
# This script updates the myclient configuration to match the actual SPIFFE ID
# issued by the default ClusterSPIFFEID template.
#
# Prerequisites:
# - Keycloak running in rhbk-demo namespace
# - myclient already created in spiffe realm
#
# Usage:
#   ./fix-keycloak-client-config.sh

set -euo pipefail

# Configuration
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-rhbk-demo}"
CLIENT_ID="${CLIENT_ID:-myclient}"
REALM="${REALM:-spiffe}"

# Actual SPIFFE ID from default ClusterSPIFFEID template
# spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}
EXPECTED_SPIFFE_ID="spiffe://example.org/ns/rhbk-demo/sa/myclient"

echo "=== Fix Keycloak Client Configuration ==="
echo ""

# Get Keycloak Pod
echo "1. Finding Keycloak Pod..."
KEYCLOAK_POD=$(oc get pod -n "$KEYCLOAK_NAMESPACE" -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$KEYCLOAK_POD" ]; then
    echo "✗ Keycloak Pod not found in namespace $KEYCLOAK_NAMESPACE"
    exit 1
fi

echo "✓ Keycloak Pod: $KEYCLOAK_POD"

# Get Admin Password
echo ""
echo "2. Retrieving Admin Password..."
ADMIN_PASSWORD=$(oc get secret keycloak-initial-admin -n "$KEYCLOAK_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$ADMIN_PASSWORD" ]; then
    echo "✗ Failed to retrieve admin password"
    exit 1
fi

echo "✓ Admin password retrieved"

# Get Current Client Configuration
echo ""
echo "3. Checking current client configuration..."

CURRENT_CONFIG=$(oc exec "$KEYCLOAK_POD" -n "$KEYCLOAK_NAMESPACE" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user temp-admin \
  --password '$ADMIN_PASSWORD' \
  --config /tmp/kcadm.config >/dev/null 2>&1

CID=\$(/opt/keycloak/bin/kcadm.sh get clients -r $REALM \
  -q clientId=$CLIENT_ID \
  --fields id \
  --format csv \
  --noquotes \
  --config /tmp/kcadm.config | tail -n 1)

/opt/keycloak/bin/kcadm.sh get clients/\$CID -r $REALM \
  --config /tmp/kcadm.config
" 2>/dev/null)

CURRENT_SUB=$(echo "$CURRENT_CONFIG" | jq -r '.attributes."jwt.credential.sub"')
CURRENT_ISSUER=$(echo "$CURRENT_CONFIG" | jq -r '.attributes."jwt.credential.issuer"')

echo "  Current jwt.credential.sub: $CURRENT_SUB"
echo "  Current jwt.credential.issuer: $CURRENT_ISSUER"

if [ "$CURRENT_SUB" = "$EXPECTED_SPIFFE_ID" ]; then
    echo ""
    echo "✓ Client configuration is already correct"
    exit 0
fi

# Update Client Configuration
echo ""
echo "4. Updating client configuration..."
echo "  Setting jwt.credential.sub to: $EXPECTED_SPIFFE_ID"

oc exec "$KEYCLOAK_POD" -n "$KEYCLOAK_NAMESPACE" -- bash -c "
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user temp-admin \
  --password '$ADMIN_PASSWORD' \
  --config /tmp/kcadm.config >/dev/null 2>&1

CID=\$(/opt/keycloak/bin/kcadm.sh get clients -r $REALM \
  -q clientId=$CLIENT_ID \
  --fields id \
  --format csv \
  --noquotes \
  --config /tmp/kcadm.config | tail -n 1)

/opt/keycloak/bin/kcadm.sh update clients/\$CID -r $REALM \
  -s 'attributes.\"jwt.credential.sub\"=$EXPECTED_SPIFFE_ID' \
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

CID=\$(/opt/keycloak/bin/kcadm.sh get clients -r $REALM \
  -q clientId=$CLIENT_ID \
  --fields id \
  --format csv \
  --noquotes \
  --config /tmp/kcadm.config | tail -n 1)

/opt/keycloak/bin/kcadm.sh get clients/\$CID -r $REALM \
  --config /tmp/kcadm.config
" 2>/dev/null)

UPDATED_SUB=$(echo "$UPDATED_CONFIG" | jq -r '.attributes."jwt.credential.sub"')

if [ "$UPDATED_SUB" = "$EXPECTED_SPIFFE_ID" ]; then
    echo "✓ Configuration updated successfully"
    echo "  jwt.credential.sub: $UPDATED_SUB"
else
    echo "✗ Configuration update failed"
    echo "  Expected: $EXPECTED_SPIFFE_ID"
    echo "  Got: $UPDATED_SUB"
    exit 1
fi

echo ""
echo "=== Configuration Fix Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run authentication test: ./scripts/test-jwt-svid-complete.sh"
echo ""
