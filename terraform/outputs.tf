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
  description = "Cluster-level components that live outside Terraform, in order."
  value = [
    "1. aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}",
    "2. kubectl apply -f manifests/storageclass-gp3.yaml",
    "3. helm upgrade --install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace --set driver.enabled=false",
    "4. Set GitHub secrets AWS_ROLE_ARN=${aws_iam_role.github_actions.arn} and EKS_CLUSTER_NAME=${aws_eks_cluster.this.name}",
  ]
}

output "model_cache_kms_key_arn" {
  description = "Customer-managed key for model-cache EBS volumes. Reference it as kmsKeyId in manifests/storageclass-gp3.yaml."
  value       = aws_kms_key.ebs.arn
}

output "secrets_kms_key_arn" {
  description = "Customer-managed key used for etcd envelope encryption of Kubernetes Secrets."
  value       = aws_kms_key.eks.arn
}
