# ---------------------------------------------------------------------------
# GitHub Actions OIDC federation
#
# This produces the role ARN that the workflow expects in secrets.AWS_ROLE_ARN.
# No long-lived access keys are involved: GitHub mints a short-lived OIDC token
# and STS exchanges it for credentials scoped to this role.
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints

  # This provider predates the Terraform configuration and is adopted through
  # the import block in imports.tf. It carries no tags today; adding any here
  # would show up as a change on the first apply.
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  github_repo = "${var.github_owner}/${var.github_repository}"

  # The workflow pins each job to a GitHub environment (dev/staging/prod) and
  # triggers on push to main plus workflow_dispatch. Scoping the trust policy to
  # those exact subjects prevents any other repo, branch, or fork from assuming
  # the role.
  #
  # The infra environments are included only while
  # allow_deploy_role_terraform_bootstrap is true, so the terraform-plan job has
  # something to assume before the dedicated Terraform CI role exists.
  deploy_role_environments = concat(
    var.github_environments,
    var.allow_deploy_role_terraform_bootstrap ? var.terraform_ci_environments : [],
  )

  github_subjects = concat(
    [for env in local.deploy_role_environments : "repo:${local.github_repo}:environment:${env}"],
    [for branch in var.github_allowed_branches : "repo:${local.github_repo}:ref:refs/heads/${branch}"],
    var.github_allowed_subjects,
  )
}

data "aws_iam_policy_document" "github_actions_assume_role" {
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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

# Assumed by GitHub Actions to build images and deploy to EKS. This role already
# exists and is actively used by the pipeline, so it is adopted via the import
# block in imports.tf rather than recreated.
#
# `description` is intentionally omitted: the live role has an empty description,
# and setting one would register as a change on the first apply after import.
resource "aws_iam_role" "github_actions" {
  name                 = "GitHubActions-DeploymentRole"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_actions" {
  # `aws ecr get-login-password` / amazon-ecr-login. GetAuthorizationToken is
  # registry-wide and cannot be resource-scoped.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [local.ecr_repository_arn]
  }

  # `aws eks update-kubeconfig` needs DescribeCluster; the in-cluster
  # permissions come from the access entry below, not from IAM.
  statement {
    sid       = "EksKubeconfig"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }

  statement {
    sid       = "EksList"
    effect    = "Allow"
    actions   = ["eks:ListClusters"]
    resources = ["*"]
  }
}

# Additive. The role currently carries AdministratorAccess, which is not managed
# by this configuration and is therefore left in place. Detaching it is a
# deliberate, separate step:
#   aws iam detach-role-policy --role-name GitHubActions-DeploymentRole \
#     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
resource "aws_iam_role_policy" "github_actions" {
  count = var.manage_deploy_role_inline_policy ? 1 : 0

  name   = "deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}

# ---------------------------------------------------------------------------
# Cluster authorization for the deploy role
#
# The cluster runs in API authentication mode, so RBAC for the deploy role is
# granted with an access entry instead of editing the aws-auth ConfigMap.
#
# The workflow runs `kubectl apply -k`, which creates Namespaces and
# cluster-scoped objects, so the entry needs cluster-wide admin. If you split
# namespace creation out of CI, downgrade this to AmazonEKSAdminPolicy scoped to
# var.workload_namespaces.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"
  user_name     = "github-actions"
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}
