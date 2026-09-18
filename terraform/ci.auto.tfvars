# Shared, non-secret Terraform settings. Tracked in git on purpose.
#
# The *.auto.tfvars suffix makes Terraform load this automatically, so a local
# `terraform plan` and the terraform-plan CI job see identical values. That
# matters: without it CI falls back to variable defaults and plans different
# infrastructure than you reviewed locally.
#
# Keep secrets out of here. There are none today; everything below is
# configuration that is safe to publish.

aws_region         = "us-east-1"
cluster_name       = "gpu-inference"
kubernetes_version = "1.34"

github_owner      = "selvaraj-outlook"
github_repository = "k8s-VLLM"

ecr_repository_name   = "dev/k8s-vllm"
create_ecr_repository = true

# GPU pool starts empty on purpose.
#
# The "Running On-Demand G and VT instances" quota (L-DB2E81BA) is still 0 in
# this account, with an increase to 8 vCPU pending. Sizing the pool above zero
# would fail the node group partway through an apply and leave a half-built
# stack. Empty gets the cluster, add-ons, IAM and ECR in place.
#
# Once the quota is approved, raise these and re-apply:
#   gpu_min_size = 1, gpu_desired_size = 1
gpu_min_size     = 0
gpu_desired_size = 0
gpu_max_size     = 1

gpu_instance_types = ["g5.2xlarge"]
gpu_capacity_type  = "ON_DEMAND"

# Lets the Terraform CI role read and write state.
terraform_state_bucket = "k8s-vllm-tfstate-861097501858"

# Cost controls for this validation account.
single_nat_gateway = true
az_count           = 2

# Set to false once AWS_TERRAFORM_ROLE_ARN is set, to stop the deploy role from
# also covering the infra environments. See variables.tf for the full rationale.
allow_deploy_role_terraform_bootstrap = true

tags = {
  Project   = "k8s-vllm"
  ManagedBy = "terraform"
}
