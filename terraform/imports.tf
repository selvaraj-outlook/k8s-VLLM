# ---------------------------------------------------------------------------
# Adoption of pre-existing AWS resources
#
# Three resources referenced by .github/workflows/aws-deploy.yaml were created
# outside Terraform and are already in use by the pipeline. These blocks bring
# them under management on the next `terraform apply` instead of trying to
# create duplicates, which would fail with AlreadyExists.
#
# Verified present in account 861097501858 / us-east-1 before writing these.
#
# Import blocks are scaffolding. Once the resources are in state you can delete
# this file; leaving it is harmless but it will fail for anyone bootstrapping a
# fresh account where these resources do not exist. In that case delete this
# file so the resources are created normally.
#
# Preview what adoption will do without touching anything:
#   terraform plan
# Expect: "3 to import" and no destroys.
# ---------------------------------------------------------------------------

# Created 2026-09-15. Shared account-wide; not specific to this repository.
import {
  to = aws_iam_openid_connect_provider.github[0]
  id = "arn:aws:iam::861097501858:oidc-provider/token.actions.githubusercontent.com"
}

# Created 2026-09-16. Last used by the pipeline 2026-09-17.
import {
  to = aws_iam_role.github_actions
  id = "GitHubActions-DeploymentRole"
}

# Created 2026-09-16. Referenced by the ECR_REPOSITORY env var in the workflow
# and by the `images.newName` values in all three kustomize overlays.
import {
  to = aws_ecr_repository.this[0]
  id = "dev/k8s-vllm"
}
