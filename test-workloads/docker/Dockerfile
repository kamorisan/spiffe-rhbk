# Multi-stage build to extract spire-agent binary from SPIRE Agent image
FROM registry.redhat.io/zero-trust-workload-identity-manager/spiffe-spire-agent-rhel9@sha256:7a5f16d95fa266ba3469ee243c52353d9598d8071bfbddadeadef547f7c3ac01 AS spire

# Final image based on UBI9
FROM registry.redhat.io/ubi9/ubi:latest

# Copy spire-agent binary from SPIRE Agent image
COPY --from=spire /spire-agent /usr/local/bin/spire-agent

# Set executable permission
RUN chmod +x /usr/local/bin/spire-agent

# Verify binary exists
RUN ls -lh /usr/local/bin/spire-agent

# Default command
CMD ["/bin/bash", "-c", "sleep infinity"]
