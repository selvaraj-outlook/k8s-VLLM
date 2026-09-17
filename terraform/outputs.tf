output "cluster_name" {
  description = "Set this as the EKS_CLUSTER_NAME GitHub secret."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Running control plane version."
  value       = aws_eks_cluster.this.version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer for IRSA-based service accounts."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN GitHub secret."
  value       = aws_iam_role.github_actions.arn
}

output "ecr_repository_url" {
  description = "Image repository URL. Must match the `images.newName` values in the kustomize overlays."
  value       = var.create_ecr_repository ? aws_ecr_repository.this[0].repository_url : "${local.ecr_registry}/${var.ecr_repository_name}"
}

output "ecr_registry" {
  description = "Registry host, matching ECR_REGISTRY in the workflow."
  value       = local.ecr_registry
}

output "node_role_arn" {
  description = "IAM role shared by both managed node groups."
  value       = aws_iam_role.node.arn
}

output "gpu_node_group_subnet_id" {
  description = "Single AZ the GPU node group runs in. The zonal model-cache EBS volume is bound to this AZ."
  value       = aws_subnet.private[0].id
}

output "vpc_id" {
  description = "VPC hosting the cluster."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnets used by the control plane ENIs and node groups."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnets reserved for NAT and internet-facing load balancers."
  value       = aws_subnet.public[*].id
}

output "configure_kubectl" {
  description = "Command to point your local kubeconfig at the new cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}

output "post_apply_steps" {
  description = "What to do after apply. The cluster prerequisites are applied by the pipeline's bootstrap-cluster job, so this is mostly verification."
  value = [
    "1. Set GitHub secrets: AWS_ROLE_ARN=${aws_iam_role.github_actions.arn} and EKS_CLUSTER_NAME=${aws_eks_cluster.this.name}",
    "2. aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}",
    "3. Confirm the GPU node registered its device: kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu'",
    "4. If that column is empty or <none>, check the G-instance vCPU quota and the gpu node group: aws eks describe-nodegroup --cluster-name ${aws_eks_cluster.this.name} --nodegroup-name gpu",
    "5. Push to main, or run the workflow manually. The bootstrap-cluster job applies cluster-bootstrap/ (gp3 StorageClass + NVIDIA device plugin) before the workload.",
  ]
}

output "gpu_capacity_summary" {
  description = "GPU vCPU footprint, to compare against the 'Running On-Demand G and VT instances' quota (L-DB2E81BA), which is 0 by default on new accounts."
  value = {
    instance_type            = var.gpu_instance_types[0]
    desired_nodes            = var.gpu_desired_size
    max_nodes                = var.gpu_max_size
    availability_zone        = local.azs[0]
    capacity_type            = var.gpu_capacity_type
    required_quota_code      = var.gpu_capacity_type == "SPOT" ? "L-3819A6DF" : "L-DB2E81BA"
    vcpus_needed_at_max      = "${var.gpu_max_size} nodes x vCPU per ${var.gpu_instance_types[0]}"
    concurrent_environments  = "Each namespace runs 1 replica requesting 1 whole GPU, so N environments need N GPU nodes."
    check_current_quota_with = "aws service-quotas get-service-quota --service-code ec2 --quota-code ${var.gpu_capacity_type == "SPOT" ? "L-3819A6DF" : "L-DB2E81BA"} --region ${var.aws_region}"
  }
}

output "model_cache_kms_key_arn" {
  description = "Customer-managed key for model-cache EBS volumes. Reference it as kmsKeyId in manifests/storageclass-gp3.yaml."
  value       = aws_kms_key.ebs.arn
}

output "secrets_kms_key_arn" {
  description = "Customer-managed key used for etcd envelope encryption of Kubernetes Secrets."
  value       = aws_kms_key.eks.arn
}
