#!/usr/bin/env bash
# Creates the S3 bucket that holds Terraform state.
#
# This is the one piece that cannot be managed by the Terraform it stores state
# for, so it is a script rather than a resource. Idempotent: safe to re-run.
#
#   ./scripts/bootstrap-state.sh my-k8s-vllm-tfstate us-east-1
#
# Then set the TF_STATE_BUCKET repository variable so CI can find it:
#   gh variable set TF_STATE_BUCKET --body my-k8s-vllm-tfstate

set -euo pipefail

BUCKET="${1:?usage: bootstrap-state.sh <bucket-name> [region]}"
REGION="${2:-us-east-1}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket $BUCKET already exists."
else
  echo "Creating s3://$BUCKET in $REGION"
  # us-east-1 rejects a LocationConstraint; every other region requires it.
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION"
  fi
fi

# Versioning lets you recover from a corrupted or truncated state write, which is
# the difference between an inconvenience and rebuilding a cluster by hand.
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

# State contains cluster CA data and resource identifiers. It must never be
# public.
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-noncurrent-state",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 90}
    }]
  }'

echo
echo "Done. Add to terraform/backend.hcl:"
echo "  bucket = \"$BUCKET\""
echo "  region = \"$REGION\""
