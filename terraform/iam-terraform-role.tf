# ---------------------------------------------------------------------------
# Role assumed by the terraform-plan / terraform-apply jobs
#
# Deliberately separate from the deploy role. Applying this configuration means
# creating VPCs, IAM roles, KMS keys and an EKS cluster, which is far more
# authority than deploying a container image needs. Keeping them apart means the
# frequently-run deploy path stays least-privilege while the rarely-run infra
# path holds the broad permissions.
#
# Chicken-and-egg: this role is created by the very Terraform that CI wants to
# run, so the first apply has to happen locally with your own credentials. After
# that, CI takes over.
# ---------------------------------------------------------------------------

variable "create_terraform_ci_role" {
  description = "Create a separate IAM role for the Terraform CI jobs. Set false if you apply Terraform only from a workstation."
  type        = bool
  default     = true
}

variable "terraform_ci_environments" {
  description = <<-EOT
    GitHub Actions environments allowed to assume the Terraform CI role. Two are
    used, and the split is what lets plan run freely while apply stays gated:

      infra-plan  the terraform-plan job. Leave unprotected so plans, including
                  on pull requests, run without waiting for a human.
      infra       the terraform-apply job. Attach required reviewers to this one
                  so infrastructure is never applied unattended.

    An environment name here must match the `environment:` key on the
    corresponding job, because that is what determines the OIDC `sub` claim.
  EOT
  type        = list(string)
  default     = ["infra", "infra-plan"]
}

variable "terraform_ci_policy_arns" {
  description = <<-EOT
    Managed policies for the Terraform CI role. Defaults to AdministratorAccess
    because this configuration creates IAM roles, KMS keys, EKS clusters and VPCs,
    and a meaningfully scoped policy for that is a large exercise in its own right.

    If that is too broad for your account, replace it with PowerUserAccess plus a
    narrow IAM-write policy covering only the role name prefixes this stack uses.
  EOT
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "terraform_state_bucket" {
  description = "S3 bucket holding Terraform state. Used to grant the CI role access to it. Leave empty to skip the grant (for example when state is local)."
  type        = string
  default     = ""
}

data "aws_iam_policy_document" "terraform_ci_assume_role" {
  count = var.create_terraform_ci_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to the infra environments only. The deploy environments (dev,
    # staging, prod) cannot assume this role, so a change to a deploy job cannot
    # reach infrastructure permissions.
    # Both subject prefixes, for the same reason as the deploy role: this repo
    # uses immutable subject claims, so the name-based form alone would never
    # match and this role would be unusable.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for prefix in local.github_subject_prefixes : [
          for env in var.terraform_ci_environments : "${prefix}:environment:${env}"
        ]
      ])
    }
  }
}

resource "aws_iam_role" "terraform_ci" {
  count = var.create_terraform_ci_role ? 1 : 0

  name                 = "${var.cluster_name}-terraform-ci"
  description          = "Assumed by the terraform-plan and terraform-apply jobs in ${local.github_repo}"
  assume_role_policy   = data.aws_iam_policy_document.terraform_ci_assume_role[0].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "terraform_ci" {
  for_each = var.create_terraform_ci_role ? toset(var.terraform_ci_policy_arns) : toset([])

  role       = aws_iam_role.terraform_ci[0].name
  policy_arn = each.value
}

# Explicit state access. Redundant under AdministratorAccess, but it keeps the
# role functional if you swap terraform_ci_policy_arns for something narrower.
resource "aws_iam_role_policy" "terraform_ci_state" {
  count = var.create_terraform_ci_role && var.terraform_state_bucket != "" ? 1 : 0

  name = "tfstate"
  role = aws_iam_role.terraform_ci[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketVersioning"]
        Resource = ["arn:${local.partition}:s3:::${var.terraform_state_bucket}"]
      },
      {
        # DeleteObject is required for S3-native lock release (use_lockfile).
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:${local.partition}:s3:::${var.terraform_state_bucket}/*"]
      },
    ]
  })
}

output "terraform_ci_role_arn" {
  description = "Set this as the AWS_TERRAFORM_ROLE_ARN GitHub secret."
  value       = var.create_terraform_ci_role ? aws_iam_role.terraform_ci[0].arn : null
}
