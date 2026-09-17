data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    # Pull access for the ECR repository the workflow pushes to.
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    # SSM Session Manager instead of SSH keys and a bastion.
    "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# System node group: CoreDNS, EBS CSI controller, GPU operator controllers.
# Kept separate so cluster add-ons never contend with GPU nodes and so the GPU
# pool can scale to zero without taking the control-plane-adjacent pods down.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "system" {
  name_prefix            = "${var.cluster_name}-system-"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-system"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.system_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.system_desired_size
    min_size     = var.system_min_size
    max_size     = var.system_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.system.id
    version = aws_launch_template.system.latest_version
  }

  labels = {
    "workload-type" = "system"
  }

  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle {
    # Leave room for the Cluster Autoscaler or Karpenter to own the count later.
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = {
    Name = "${var.cluster_name}-system"
  }
}

# ---------------------------------------------------------------------------
# GPU node group
#
# The label and taint here are what base/deployment.yaml selects and tolerates:
#   nodeSelector: nvidia.com/gpu.present: "true"
#   tolerations:  key nvidia.com/gpu, operator Exists, effect NoSchedule
#
# Setting the label on the node group means scheduling works even before the
# NVIDIA GPU Operator's feature discovery labels the node. The taint keeps
# non-GPU workloads off these instances.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "gpu" {
  name_prefix            = "${var.cluster_name}-gpu-"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.gpu_node_disk_size
      volume_type           = "gp3"
      throughput            = 250
      iops                  = 4000
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-gpu"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "gpu" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "gpu"
  node_role_arn   = aws_iam_role.node.arn

  # One subnet keeps GPU capacity in a single AZ, which matters because the
  # model-cache PVC is a zonal EBS volume: a pod rescheduled into another AZ
  # cannot attach it.
  subnet_ids = [aws_subnet.private[0].id]

  ami_type       = var.gpu_ami_type
  instance_types = var.gpu_instance_types
  capacity_type  = var.gpu_capacity_type

  scaling_config {
    desired_size = var.gpu_desired_size
    min_size     = var.gpu_min_size
    max_size     = var.gpu_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.gpu.id
    version = aws_launch_template.gpu.latest_version
  }

  labels = {
    "nvidia.com/gpu.present" = "true"
    "workload-type"          = "gpu-inference"
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = var.gpu_node_taint_value
    effect = "NO_SCHEDULE"
  }

  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = {
    Name = "${var.cluster_name}-gpu"
    # Discovery tags for the Cluster Autoscaler, if you add it later.
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }
}
