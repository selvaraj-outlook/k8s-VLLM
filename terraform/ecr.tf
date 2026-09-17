# The workflow's "Verify ECR repository" step fails the build if this repository
# is missing, so it is part of the required infrastructure rather than an
# optional extra.
#
# If the repository already exists (commit 57e2c5c switched the pipeline to an
# existing repo), import it instead of recreating it:
#   terraform import 'aws_ecr_repository.this[0]' dev/k8s-vllm

resource "aws_ecr_repository" "this" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = var.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = var.ecr_repository_name
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = var.create_ecr_repository ? 1 : 0

  repository = aws_ecr_repository.this[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Retain a bounded window of commit-tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Restrict pulls to this account's node role and the deploy role. Without this,
# the repository policy is account-wide by default.
resource "aws_ecr_repository_policy" "this" {
  count = var.create_ecr_repository ? 1 : 0

  repository = aws_ecr_repository.this[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowClusterNodesToPull"
        Effect = "Allow"
        Principal = {
          AWS = [aws_iam_role.node.arn]
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
      },
      {
        Sid    = "AllowDeployRoleToPush"
        Effect = "Allow"
        Principal = {
          AWS = [aws_iam_role.github_actions.arn]
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
      },
    ]
  })
}

locals {
  ecr_repository_arn = var.create_ecr_repository ? aws_ecr_repository.this[0].arn : "arn:${local.partition}:ecr:${var.aws_region}:${local.account_id}:repository/${var.ecr_repository_name}"
  ecr_registry       = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
