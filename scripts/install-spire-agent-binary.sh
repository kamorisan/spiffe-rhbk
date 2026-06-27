#!/bin/bash
#
# Install spire-agent binary into jwt-test-client pod
#
# This script copies the spire-agent binary from a running SPIRE Agent pod
# to the jwt-test-client pod, enabling JWT-SVID authentication testing.
#
# Prerequisites:
# - SPIRE Agent pods running
# - jwt-test-client pod running
#
# Usage:
#   ./install-spire-agent-binary.sh

set -euo pipefail

# Configuration
SPIRE_NAMESPACE="${SPIRE_NAMESPACE:-zero-trust-workload-identity-manager}"
CLIENT_NAMESPACE="${CLIENT_NAMESPACE:-rhbk-demo}"
CLIENT_POD_LABEL="${CLIENT_POD_LABEL:-jwt-test-client}"

echo "=== Install spire-agent Binary into jwt-test-client Pod ==="
echo ""

# Get SPIRE Agent Pod
echo "1. Finding SPIRE Agent Pod..."
SPIRE_AGENT_POD=$(oc get pod -n "$SPIRE_NAMESPACE" -l app.kubernetes.io/name=spire-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$SPIRE_AGENT_POD" ]; then
    echo "✗ SPIRE Agent Pod not found in namespace $SPIRE_NAMESPACE"
    exit 1
fi

echo "✓ SPIRE Agent Pod: $SPIRE_AGENT_POD"

# Get jwt-test-client Pod (Running Deployment pod, not Job pods)
echo ""
echo "2. Finding jwt-test-client Pod..."
CLIENT_POD=$(oc get pod -n "$CLIENT_NAMESPACE" -l app="$CLIENT_POD_LABEL" --field-selector=status.phase=Running -o jsonpath='{.items[?(@.metadata.ownerReferences[0].kind=="ReplicaSet")].metadata.name}' 2>/dev/null | awk '{print $1}' || echo "")

if [ -z "$CLIENT_POD" ]; then
    echo "✗ jwt-test-client Pod not found in namespace $CLIENT_NAMESPACE"
    exit 1
fi

echo "✓ jwt-test-client Pod: $CLIENT_POD"

# Check if spire-agent binary already exists in client pod
echo ""
echo "3. Checking if spire-agent binary already exists..."
if oc exec "$CLIENT_POD" -n "$CLIENT_NAMESPACE" -c client -- sh -c "command -v /usr/local/bin/spire-agent" &>/dev/null; then
    echo "✓ spire-agent binary already exists"
    echo ""
    read -p "Overwrite existing binary? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
fi

# Copy spire-agent binary from SPIRE Agent pod to local temp file
echo ""
echo "4. Extracting spire-agent binary from SPIRE Agent pod..."
TEMP_FILE="/tmp/spire-agent-binary-$$"

# Try different possible locations (RHBK Operator image uses /spire-agent)
if oc exec "$SPIRE_AGENT_POD" -n "$SPIRE_NAMESPACE" -c spire-agent -- cat /spire-agent > "$TEMP_FILE" 2>/dev/null; then
    echo "✓ Extracted from /spire-agent"
elif oc exec "$SPIRE_AGENT_POD" -n "$SPIRE_NAMESPACE" -c spire-agent -- cat /opt/spire/bin/spire-agent > "$TEMP_FILE" 2>/dev/null; then
    echo "✓ Extracted from /opt/spire/bin/spire-agent"
elif oc exec "$SPIRE_AGENT_POD" -n "$SPIRE_NAMESPACE" -c spire-agent -- cat /usr/bin/spire-agent > "$TEMP_FILE" 2>/dev/null; then
    echo "✓ Extracted from /usr/bin/spire-agent"
elif oc exec "$SPIRE_AGENT_POD" -n "$SPIRE_NAMESPACE" -c spire-agent -- cat /usr/local/bin/spire-agent > "$TEMP_FILE" 2>/dev/null; then
    echo "✓ Extracted from /usr/local/bin/spire-agent"
else
    echo "✗ Failed to extract spire-agent binary"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Verify extracted file is not empty
if [ ! -s "$TEMP_FILE" ]; then
    echo "✗ Extracted file is empty"
    rm -f "$TEMP_FILE"
    exit 1
fi

FILE_SIZE=$(wc -c < "$TEMP_FILE")
echo "✓ Extracted binary size: $FILE_SIZE bytes"

# Copy binary to jwt-test-client pod
echo ""
echo "5. Copying spire-agent binary to jwt-test-client pod..."
oc cp "$TEMP_FILE" "$CLIENT_NAMESPACE/$CLIENT_POD:/tmp/spire-agent" -c client

# Set executable permission
echo ""
echo "6. Setting executable permission..."
oc exec "$CLIENT_POD" -n "$CLIENT_NAMESPACE" -c client -- chmod +x /tmp/spire-agent

# Verify installation
echo ""
echo "7. Verifying installation..."
if oc exec "$CLIENT_POD" -n "$CLIENT_NAMESPACE" -c client -- /tmp/spire-agent --version &>/dev/null; then
    VERSION=$(oc exec "$CLIENT_POD" -n "$CLIENT_NAMESPACE" -c client -- /tmp/spire-agent --version 2>&1 || echo "unknown")
    echo "✓ spire-agent installed successfully"
    echo "  Version: $VERSION"
else
    echo "⚠ spire-agent binary installed but version check failed"
fi

# Clean up
rm -f "$TEMP_FILE"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Test JWT-SVID fetch: ./scripts/test-jwt-svid-auth.sh"
echo "  2. Or manually test:"
echo "     oc exec $CLIENT_POD -n $CLIENT_NAMESPACE -c client -- \\"
echo "       /usr/local/bin/spire-agent api fetch jwt -audience test -socketPath /spiffe-workload-api/spire-agent.sock"
echo ""
