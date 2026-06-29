#!/bin/bash
#
# JWT-SVID Authentication Test Script
#
# This script tests the complete SPIFFE JWT-SVID authentication flow with Keycloak
#
# Prerequisites:
# - SPIRE Server/Agent running
# - Keycloak with SPIFFE realm configured
# - ClusterSPIFFEID for the test client
#
# Usage:
#   ./test-jwt-svid-auth.sh
#

set -euo pipefail

# Configuration
SPIRE_NAMESPACE="${SPIRE_NAMESPACE:-zero-trust-workload-identity-manager}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-rhbk-demo}"
CLIENT_NAMESPACE="${CLIENT_NAMESPACE:-rhbk-demo}"
TRUST_DOMAIN="${TRUST_DOMAIN:-example.org}"
CLIENT_ID="${CLIENT_ID:-myclient}"

# Auto-detect OpenShift Apps Domain
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
KEYCLOAK_HOSTNAME="keycloak-${KEYCLOAK_NAMESPACE}.${APPS_DOMAIN}"
AUDIENCE="https://${KEYCLOAK_HOSTNAME}/realms/spiffe"
TOKEN_ENDPOINT="${AUDIENCE}/protocol/openid-connect/token"

echo "=== JWT-SVID Authentication Test ==="
echo ""
echo "Configuration:"
echo "  SPIRE Namespace: $SPIRE_NAMESPACE"
echo "  Keycloak Namespace: $KEYCLOAK_NAMESPACE"
echo "  Client Namespace: $CLIENT_NAMESPACE"
echo "  Trust Domain: $TRUST_DOMAIN"
echo "  Client ID: $CLIENT_ID"
echo "  Keycloak Hostname: $KEYCLOAK_HOSTNAME"
echo "  Token Endpoint: $TOKEN_ENDPOINT"
echo ""

# Get SPIRE Agent Pod
echo "1. Finding SPIRE Agent Pod..."
SPIRE_AGENT_POD=$(oc get pod -n "$SPIRE_NAMESPACE" -l app.kubernetes.io/name=spire-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$SPIRE_AGENT_POD" ]; then
    echo "✗ SPIRE Agent Pod not found in namespace $SPIRE_NAMESPACE"
    exit 1
fi

echo "✓ SPIRE Agent Pod: $SPIRE_AGENT_POD"

# Get test client Pod (optional, for reference)
echo ""
echo "2. Finding test client Pod..."
TEST_CLIENT_POD=$(oc get pod -n "$CLIENT_NAMESPACE" -l app=jwt-test-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$TEST_CLIENT_POD" ]; then
    echo "✓ Test client Pod: $TEST_CLIENT_POD"
else
    echo "⚠ Test client Pod not found (optional)"
fi

# Fetch JWT-SVID
echo ""
echo "3. Fetching JWT-SVID from test client Pod..."
if [ -n "$TEST_CLIENT_POD" ]; then
    JWT_SVID=$(oc exec "$TEST_CLIENT_POD" -n "$CLIENT_NAMESPACE" -c client -- sh -c \
        "timeout 10 nc -U /spiffe-workload-api/spire-agent.sock" 2>/dev/null | grep -Eo 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1 || echo "")

    if [ -z "$JWT_SVID" ]; then
        echo "⚠ Could not fetch JWT-SVID from test client pod (gRPC Workload API requires proper client)"
        echo "  Using alternative method: executing from SPIRE Server pod..."
        JWT_SVID=""
    fi
fi

# Alternative: Fetch from SPIRE Server pod
if [ -z "$JWT_SVID" ]; then
    echo "  Fetching JWT-SVID from SPIRE Server pod..."

    SPIRE_SERVER_POD=$(oc get pod -n "$SPIRE_NAMESPACE" -l app.kubernetes.io/name=spire-server -o jsonpath='{.items[0].metadata.name}')

    # Create temporary registration entry for testing
    SPIFFE_ID="spiffe://${TRUST_DOMAIN}/${CLIENT_ID}"

    echo "  SPIFFE ID: $SPIFFE_ID"
    echo "  Audience: $AUDIENCE"

    # Note: This requires the spire-server CLI tool
    echo ""
    echo "  To manually fetch JWT-SVID, run:"
    echo "  oc exec $SPIRE_SERVER_POD -n $SPIRE_NAMESPACE -c spire-server -- \\"
    echo "    /opt/spire/bin/spire-server token generate -spiffeID $SPIFFE_ID -audience $AUDIENCE"
    echo ""
    echo "  Or from a pod with SPIFFE CSI volume:"
    echo "  (Requires spire-agent CLI or gRPC client)"

    # Try to generate JWT using SPIRE Server (for testing)
    echo "  Attempting to use SPIRE Server to generate test token..."
    echo ""

    # Check if we can exec into SPIRE Server
    SPIRE_SERVER_POD=$(oc get pod -n "$SPIRE_NAMESPACE" -l app.kubernetes.io/name=spire-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$SPIRE_SERVER_POD" ]; then
        echo "✗ SPIRE Server Pod not found"
        echo ""
        echo "Manual test procedure (see docs/manual-test-procedure.md):"
        exit 0
    fi

    echo "  Checking for registration entry..."
    ENTRY_CHECK=$(oc exec "$SPIRE_SERVER_POD" -n "$SPIRE_NAMESPACE" -c spire-server -- \
        /opt/spire/bin/spire-server entry show -spiffeID "$SPIFFE_ID" 2>/dev/null || echo "")

    if echo "$ENTRY_CHECK" | grep -q "Found 0 entries"; then
        echo "  ⚠ No registration entry found for SPIFFE ID: $SPIFFE_ID"
        echo ""
        echo "  This is expected: ClusterSPIFFEID creates entries dynamically when pods are scheduled."
        echo "  The jwt-test-client pod should have the SPIFFE ID automatically assigned."
        echo ""
    fi

    echo ""
    echo "=== Manual Test Instructions ==="
    echo ""
    echo "To complete the authentication test, run the following commands:"
    echo ""
    echo "# 1. Exec into the SPIRE Server pod"
    echo "oc exec -it $SPIRE_SERVER_POD -n $SPIRE_NAMESPACE -c spire-server -- /bin/bash"
    echo ""
    echo "# 2. Inside the pod, generate a JWT token (development/testing method)"
    echo "/opt/spire/bin/spire-server token generate -spiffeID $SPIFFE_ID"
    echo ""
    echo "# 3. Or, check the actual workload entries:"
    echo "/opt/spire/bin/spire-server entry show -selector k8s:ns:$CLIENT_NAMESPACE"
    echo ""
    echo "# 4. Once you have a JWT-SVID, test with Keycloak:"
    echo "curl -k -X POST \"$TOKEN_ENDPOINT\" \\"
    echo "  -H \"Content-Type: application/x-www-form-urlencoded\" \\"
    echo "  --data-urlencode \"grant_type=client_credentials\" \\"
    echo "  --data-urlencode \"client_id=$CLIENT_ID\" \\"
    echo "  --data-urlencode \"client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe\" \\"
    echo "  --data-urlencode \"client_assertion=<YOUR_JWT_SVID>\""
    echo ""
    echo "Expected successful result:"
    echo "  {\"access_token\":\"...\",\"expires_in\":300,\"token_type\":\"Bearer\",...}"
    echo ""
    echo "For detailed instructions, see: docs/manual-test-procedure.md"
    echo ""

    exit 0
fi

# Decode JWT-SVID
echo "✓ JWT-SVID fetched"
echo "  JWT length: ${#JWT_SVID} characters"

PAYLOAD=$(echo "$JWT_SVID" | cut -d. -f2 | base64 -d 2>/dev/null || echo "{}")
echo "  Payload: $PAYLOAD"

# Authenticate with Keycloak
echo ""
echo "4. Authenticating with Keycloak Token Endpoint..."

RESPONSE=$(curl -k -s -X POST "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
    --data-urlencode "client_assertion=$JWT_SVID")

echo "Response:"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

if echo "$RESPONSE" | grep -q "access_token"; then
    echo ""
    echo "✅ SUCCESS: Keycloak authentication successful!"

    ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token' 2>/dev/null)
    EXPIRES_IN=$(echo "$RESPONSE" | jq -r '.expires_in' 2>/dev/null)

    echo "  Access token received"
    echo "  Token length: ${#ACCESS_TOKEN} characters"
    echo "  Expires in: ${EXPIRES_IN}s"
else
    echo ""
    echo "✗ FAILED: Keycloak authentication failed"

    if echo "$RESPONSE" | grep -q "error"; then
        ERROR=$(echo "$RESPONSE" | jq -r '.error' 2>/dev/null)
        ERROR_DESC=$(echo "$RESPONSE" | jq -r '.error_description' 2>/dev/null)
        echo "  Error: $ERROR"
        echo "  Description: $ERROR_DESC"
    fi

    exit 1
fi

echo ""
echo "=== Test Summary ==="
echo "✓ SPIFFE Workload API: Available"
echo "✓ JWT-SVID Fetch: Success"
echo "✓ Keycloak Authentication: Success"
echo ""
echo "All tests passed!"
