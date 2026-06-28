#!/bin/bash
#
# Complete JWT-SVID Authentication Test
#
# This script performs end-to-end JWT-SVID authentication test with Keycloak
#
# Prerequisites:
# - jwt-test-client Pod running (uses custom image with embedded spire-agent binary)
# - Keycloak client configuration correct (automatically configured via GitOps)
#
# Usage:
#   ./test-jwt-svid-complete.sh

set -euo pipefail

# Configuration
CLIENT_NAMESPACE="${CLIENT_NAMESPACE:-rhbk-demo}"
CLIENT_POD_LABEL="${CLIENT_POD_LABEL:-jwt-test-client}"
TRUST_DOMAIN="${TRUST_DOMAIN:-example.org}"
CLIENT_ID="${CLIENT_ID:-myclient}"
REALM="${REALM:-spiffe}"

echo "=== JWT-SVID Authentication Complete Test ==="
echo ""

# Get OpenShift Apps Domain
echo "1. Detecting environment..."
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KEYCLOAK_HOSTNAME="keycloak-${CLIENT_NAMESPACE}.${APPS_DOMAIN}"
AUDIENCE="https://${KEYCLOAK_HOSTNAME}/realms/${REALM}"
TOKEN_ENDPOINT="${AUDIENCE}/protocol/openid-connect/token"

echo "  Apps Domain: $APPS_DOMAIN"
echo "  Keycloak Hostname: $KEYCLOAK_HOSTNAME"
echo "  Audience: $AUDIENCE"

# Get jwt-test-client Pod (Running Deployment pod, not Job pods)
echo ""
echo "2. Finding jwt-test-client Pod..."
CLIENT_POD=$(oc get pod -n "$CLIENT_NAMESPACE" -l app="$CLIENT_POD_LABEL" --field-selector=status.phase=Running \
    -o jsonpath='{.items[?(@.metadata.ownerReferences[0].kind=="ReplicaSet")].metadata.name}' 2>/dev/null | awk '{print $1}')

if [ -z "$CLIENT_POD" ]; then
    echo "✗ jwt-test-client Pod not found or not running"
    exit 1
fi

echo "✓ jwt-test-client Pod: $CLIENT_POD"

# Check if spire-agent binary exists (embedded in custom image)
echo ""
echo "3. Checking spire-agent binary..."
SPIRE_AGENT_PATH="/usr/local/bin/spire-agent"

if ! oc exec "$CLIENT_POD" -n "$CLIENT_NAMESPACE" -c client -- sh -c "test -x $SPIRE_AGENT_PATH" &>/dev/null; then
    echo "✗ spire-agent binary not found at $SPIRE_AGENT_PATH"
    echo ""
    echo "Note: The custom image (quay.io/kamori/jwt-svid-test-client:v1.0) should include spire-agent binary."
    echo "Please verify the Pod is using the correct image:"
    echo "  oc get pod $CLIENT_POD -n $CLIENT_NAMESPACE -o jsonpath='{.spec.containers[0].image}'"
    exit 1
fi

echo "✓ spire-agent binary found at $SPIRE_AGENT_PATH"

# Fetch JWT-SVID
echo ""
echo "4. Fetching JWT-SVID..."
echo "  Audience: $AUDIENCE"

JWT_OUTPUT=$(oc exec "$CLIENT_POD" -n "$CLIENT_NAMESPACE" -c client -- \
  "$SPIRE_AGENT_PATH" api fetch jwt \
  -audience "$AUDIENCE" \
  -socketPath /spiffe-workload-api/spire-agent.sock 2>&1)

JWT_SVID=$(echo "$JWT_OUTPUT" | sed -n '2p' | sed 's/^[[:space:]]*//')

if [ -z "$JWT_SVID" ] || [ ${#JWT_SVID} -lt 100 ]; then
    echo "✗ Failed to fetch JWT-SVID"
    echo ""
    echo "Output:"
    echo "$JWT_OUTPUT"
    exit 1
fi

echo "✓ JWT-SVID fetched successfully"
echo "  Length: ${#JWT_SVID} characters"

# Decode JWT-SVID payload (using Python for cross-platform compatibility)
PAYLOAD_B64=$(echo "$JWT_SVID" | cut -d. -f2)
PAYLOAD=$(python3 -c "import base64, json, sys; print(json.dumps(json.loads(base64.urlsafe_b64decode('$PAYLOAD_B64' + '==='))))" 2>/dev/null || echo "{}")
SUB=$(echo "$PAYLOAD" | jq -r '.sub' 2>/dev/null || echo "")
ISS=$(echo "$PAYLOAD" | jq -r '.iss' 2>/dev/null || echo "")
AUD=$(echo "$PAYLOAD" | jq -r '.aud[0]' 2>/dev/null || echo "")

echo ""
echo "  JWT-SVID Claims:"
echo "    sub: $SUB"
echo "    iss: $ISS"
echo "    aud: $AUD"

# Perform Authentication
echo ""
echo "5. Authenticating with Keycloak..."
echo "  Token Endpoint: $TOKEN_ENDPOINT"
echo "  Client ID: $CLIENT_ID"

RESPONSE=$(curl -k -s -w '\nHTTP_CODE:%{http_code}' -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
  --data-urlencode "client_assertion=$JWT_SVID")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo ""
echo "  HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo ""
    echo "✅ SUCCESS: Keycloak authentication successful!"
    echo ""

    ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token' 2>/dev/null || echo "")
    EXPIRES_IN=$(echo "$RESPONSE_BODY" | jq -r '.expires_in' 2>/dev/null || echo "")
    TOKEN_TYPE=$(echo "$RESPONSE_BODY" | jq -r '.token_type' 2>/dev/null || echo "")

    echo "Response:"
    echo "$RESPONSE_BODY" | jq .

    echo ""
    echo "Summary:"
    echo "  ✓ Access Token: ${ACCESS_TOKEN:0:50}..."
    echo "  ✓ Token Type: $TOKEN_TYPE"
    echo "  ✓ Expires In: ${EXPIRES_IN}s"

    # Save success result
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    LOG_DIR="$(dirname "$0")/../logs"
    mkdir -p "$LOG_DIR"
    echo "$RESPONSE_BODY" | jq . > "$LOG_DIR/SUCCESS-GITOPS-${TIMESTAMP}.json"
    echo ""
    echo "  ✓ Result saved to: logs/SUCCESS-GITOPS-${TIMESTAMP}.json"
else
    echo ""
    echo "✗ FAILED: Keycloak authentication failed"
    echo ""
    echo "Response:"
    echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"

    if echo "$RESPONSE_BODY" | jq -e '.error' >/dev/null 2>&1; then
        ERROR=$(echo "$RESPONSE_BODY" | jq -r '.error')
        ERROR_DESC=$(echo "$RESPONSE_BODY" | jq -r '.error_description')
        echo ""
        echo "Error Details:"
        echo "  Error: $ERROR"
        echo "  Description: $ERROR_DESC"
    fi

    exit 1
fi

echo ""
echo "=== Test Summary ==="
echo "✓ Environment Detection: Success"
echo "✓ Pod Selection: Success"
echo "✓ spire-agent Binary: Available"
echo "✓ JWT-SVID Fetch: Success"
echo "✓ Keycloak Authentication: Success"
echo ""
echo "All tests passed!"
echo ""
