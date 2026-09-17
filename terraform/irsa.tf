# ---------------------------------------------------------------------------
# IRSA trust policy helper
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_assume_role" {
  for_each = {
    vpc_cni        = "system:serviceaccount:kube-system:aws-node"
    ebs_csi_driver = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = [each.value]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# VPC CNI
# ---------------------------------------------------------------------------

resource "aws_iam_role" "vpc_cni" {
  name               = "${var.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role["vpc_cni"].json
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ---------------------------------------------------------------------------
# EBS CSI driver: provisions and attaches the model-cache volume
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role["ebs_csi_driver"].json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# The managed policy above only permits KMS use through the default EBS key, so
# grant the driver explicit access to the customer-managed key used by the gp3
# StorageClass.
resource "aws_iam_role_policy" "ebs_csi_driver_kms" {
  name = "ebs-kms"
  role = aws_iam_role.ebs_csi_driver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant",
        ]
        Resource = [aws_kms_key.ebs.arn]
        Condition = {
          Bool = { "kms:GrantIsForAWSResource" = "true" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = [aws_kms_key.ebs.arn]
      },
    ]
  })
}

resource "aws_kms_key" "ebs" {
  description             = "Encryption key for ${var.cluster_name} model-cache EBS volumes"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-ebs"
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.cluster_name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}
