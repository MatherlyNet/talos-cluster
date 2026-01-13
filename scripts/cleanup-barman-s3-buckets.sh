#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# barman-cloud S3 Bucket Cleanup Script
# ==============================================================================
# Cleans stale WAL archive data from RustFS S3 buckets for CloudNativePG clusters
#
# ISSUE: "Expected empty archive" errors occur when clusters are recreated but
#        old WAL files remain in S3 buckets
#
# SOLUTION: Delete all objects in backup buckets and restart PostgreSQL pods
#           to trigger fresh WAL archiving
#
# REF: docs/research/barman-cloud-plugin-wal-archive-remediation-jan-2026.md
# REF: docs/research/oidc-implementation-impact-assessment-jan-2026.md
# ==============================================================================

echo "=== CloudNativePG barman-cloud S3 Bucket Cleanup ==="
echo ""
echo "This script will:"
echo "  1. Clean stale WAL data from RustFS S3 buckets"
echo "  2. Restart PostgreSQL pods to trigger fresh archiving"
echo ""
echo "Affected buckets:"
echo "  - s3://keycloak-backups (identity/keycloak-postgres)"
echo "  - s3://litellm-backups (ai-system/litellm-postgresql)"
echo "  - s3://langfuse-postgres-backups (ai-system/langfuse-postgresql)"
echo "  - s3://obot-postgres-backups (ai-system/obot-postgresql)"
echo ""
read -p "Continue? (yes/no): " confirm
[[ "$confirm" != "yes" ]] && { echo "Aborted."; exit 1; }

# Array of buckets to clean: namespace:secret:bucket:cluster
BUCKETS=(
  "identity:keycloak-backup-credentials:keycloak-backups:keycloak-postgres"
  "ai-system:litellm-backup-credentials:litellm-backups:litellm-postgresql"
  "ai-system:langfuse-backup-credentials:langfuse-postgres-backups:langfuse-postgresql"
  "ai-system:obot-backup-credentials:obot-postgres-backups:obot-postgresql"
)

ENDPOINT="http://rustfs-svc.storage.svc.cluster.local:9000"

for entry in "${BUCKETS[@]}"; do
  IFS=':' read -r namespace secret bucket cluster <<< "$entry"

  echo ""
  echo "=== Processing $namespace/$cluster ==="

  # Get credentials from secret
  echo "Fetching S3 credentials from secret $namespace/$secret..."
  ACCESS_KEY=$(kubectl get secret "$secret" -n "$namespace" -o jsonpath='{.data.ACCESS_KEY_ID}' | base64 -d)
  SECRET_KEY=$(kubectl get secret "$secret" -n "$namespace" -o jsonpath='{.data.SECRET_ACCESS_KEY}' | base64 -d)

  if [[ -z "$ACCESS_KEY" ]] || [[ -z "$SECRET_KEY" ]]; then
    echo "ERROR: Failed to retrieve credentials from secret $namespace/$secret"
    continue
  fi

  # Delete all objects in bucket
  echo "Deleting all objects in s3://$bucket..."
  kubectl run --rm -i "s3-cleanup-$cluster" \
    --image=amazon/aws-cli \
    --restart=Never \
    --namespace="$namespace" \
    --env="AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
    --env="AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
    -- s3 rm "s3://$bucket/" --recursive --endpoint-url="$ENDPOINT" || {
      echo "WARNING: Failed to clean bucket s3://$bucket (may be empty or access denied)"
    }

  # Restart PostgreSQL pod
  echo "Restarting PostgreSQL pod $cluster-1..."
  kubectl delete pod "$cluster-1" -n "$namespace" --ignore-not-found=true

  echo "✓ Completed $namespace/$cluster"
done

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Monitor pod restarts with:"
echo "  kubectl get pods -n identity -l cnpg.io/cluster=keycloak-postgres -w"
echo "  kubectl get pods -n ai-system -l cnpg.io/instanceRole=primary -w"
echo ""
echo "Verify WAL archiving after pods are ready (wait ~2 minutes):"
echo "  kubectl logs -n identity keycloak-postgres-1 -c plugin-barman-cloud --tail=20"
echo "  kubectl logs -n ai-system litellm-postgresql-1 -c plugin-barman-cloud --tail=20"
echo "  kubectl logs -n ai-system langfuse-postgresql-1 -c plugin-barman-cloud --tail=20"
echo "  kubectl logs -n ai-system obot-postgresql-1 -c plugin-barman-cloud --tail=20"
echo ""
echo "Expected: No 'Expected empty archive' errors, successful WAL archiving"