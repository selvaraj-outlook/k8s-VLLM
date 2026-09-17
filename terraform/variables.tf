variable "aws_region" {
  description = "AWS region for all resources. Must match AWS_REGION in .github/workflows/aws-deploy.yaml."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name. Set the EKS_CLUSTER_NAME GitHub secret to this value."
  type        = string
  default     = "gpu-inference"
}

variable "kubernetes_version" {
  description = "EKS control plane minor version. The workload manifests require 1.28+."
  type        = string
  default     = "1.34"
}

variable "tags" {
  description = "Tags applied to every resource that supports tagging."
  type        = map(string)
  default = {
    Project   = "k8s-vllm"
    ManagedBy = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Needs room for /20 private subnets per AZ."
  type        = string
  default     = "10.60.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 18
    error_message = "vpc_cidr must be a valid IPv4 CIDR of /18 or larger (smaller prefix length)."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, but a single AZ failure domain for egress."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint publicly. Required for GitHub-hosted runners to reach the cluster."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. GitHub-hosted runners use dynamic egress IPs, so narrowing this requires self-hosted runners or a VPN."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Node groups
# ---------------------------------------------------------------------------

variable "system_instance_types" {
  description = "Instance types for the CPU node group that runs CoreDNS, the EBS CSI controller, and the GPU operator control plane."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "system_desired_size" {
  description = "Desired node count for the system node group."
  type        = number
  default     = 2
}

variable "system_min_size" {
  description = "Minimum node count for the system node group."
  type        = number
  default     = 2
}

variable "system_max_size" {
  description = "Maximum node count for the system node group."
  type        = number
  default     = 4
}

variable "gpu_instance_types" {
  description = "GPU instance types. g5.2xlarge is one A10G (24 GB) with 8 vCPU / 32 GiB, which leaves headroom above the 4 vCPU / 16 GiB container limits in base/deployment.yaml."
  type        = list(string)
  default     = ["g5.2xlarge"]
}

variable "gpu_ami_type" {
  description = "EKS AMI type for GPU nodes. AL2023_x86_64_NVIDIA ships the NVIDIA driver and container toolkit preinstalled."
  type        = string
  default     = "AL2023_x86_64_NVIDIA"

  validation {
    condition = contains([
      "AL2023_x86_64_NVIDIA",
      "AL2_x86_64_GPU",
      "BOTTLEROCKET_x86_64_NVIDIA",
    ], var.gpu_ami_type)
    error_message = "gpu_ami_type must be an NVIDIA-accelerated EKS AMI type."
  }
}

variable "gpu_desired_size" {
  description = "Desired GPU node count. Each vLLM replica consumes one whole GPU."
  type        = number
  default     = 1
}

variable "gpu_min_size" {
  description = "Minimum GPU node count. Set to 0 to allow scaling the expensive pool to nothing when idle."
  type        = number
  default     = 1
}

variable "gpu_max_size" {
  description = "Maximum GPU node count. Sized for one node per environment namespace by default."
  type        = number
  default     = 3
}

variable "gpu_node_disk_size" {
  description = "Root EBS volume size in GiB for GPU nodes. The vLLM image plus layers needs well over the 20 GiB default."
  type        = number
  default     = 200
}

variable "gpu_capacity_type" {
  description = "ON_DEMAND or SPOT for the GPU node group. SPOT is far cheaper but interrupts inference mid-request."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.gpu_capacity_type)
    error_message = "gpu_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "gpu_node_taint_value" {
  description = "Value for the nvidia.com/gpu NoSchedule taint. base/deployment.yaml tolerates any value via operator: Exists."
  type        = string
  default     = "present"
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

variable "create_ecr_repository" {
  description = "Create the ECR repository. Set to false and use ecr_repository_name if the repo already exists and you do not want to import it."
  type        = bool
  default     = true
}

variable "ecr_repository_name" {
  description = "ECR repository name. Must match ECR_REPOSITORY in .github/workflows/aws-deploy.yaml."
  type        = string
  default     = "dev/k8s-vllm"
}

variable "ecr_image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. The workflow pushes commit-SHA tags, so IMMUTABLE is safe and prevents tag reuse."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_untagged_expiry_days" {
  description = "Days before untagged ECR images are expired by the lifecycle policy."
  type        = number
  default     = 7
}

variable "ecr_max_tagged_images" {
  description = "Number of SHA-tagged images to retain before the oldest are expired."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC
# ---------------------------------------------------------------------------

variable "github_owner" {
  description = "GitHub org or user that owns the repository."
  type        = string
  default     = "selvaraj-outlook"
}

variable "github_repository" {
  description = "GitHub repository name."
  type        = string
  default     = "k8s-VLLM"
}

variable "github_allowed_subjects" {
  description = <<-EOT
    Extra `sub` claim patterns allowed to assume the deploy role, appended to the
    environment-scoped subjects below.

    The defaults reproduce the trust policy already attached to the existing
    GitHubActions-DeploymentRole so that importing it causes no change. Two things
    here deserve review:
      - `repo:core-projects-factory/*:environment:*` lets every repo in a second
        org assume this role. Remove it if that is not intended.
      - The `owner@id/repo@id` forms are not subjects GitHub actually issues, so
        they never match. They are kept only to make the import a no-op and can be
        dropped once you confirm nothing depends on them.
  EOT
  type        = list(string)
  default = [
    "repo:selvaraj-outlook@261786377/k8s-VLLM@1371954039:environment:dev",
    "repo:selvaraj-outlook@261786377/k8s-VLLM@1371954039:environment:staging",
    "repo:selvaraj-outlook@261786377/k8s-VLLM@1371954039:environment:prod",
    "repo:core-projects-factory/*:environment:*",
  ]
}

variable "github_environments" {
  description = "GitHub Actions environments allowed to assume the deploy role. Must match the `environment:` keys in the workflow."
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "github_allowed_branches" {
  description = <<-EOT
    Branches whose `ref:refs/heads/<branch>` subject may assume the deploy role.
    Empty by default: every job in the workflow pins a GitHub `environment:`, so
    the environment-scoped subjects are sufficient and adding ref subjects would
    widen trust beyond what the existing role grants.
  EOT
  type        = list(string)
  default     = []
}

variable "create_github_oidc_provider" {
  description = "Keep the GitHub OIDC provider in this configuration. The provider already exists in this account and is adopted via the import block in imports.tf."
  type        = bool
  default     = true
}

variable "github_oidc_thumbprints" {
  description = <<-EOT
    Certificate thumbprints for token.actions.githubusercontent.com. The default is
    the value currently registered in this account, so the import is a no-op. STS
    validates GitHub's OIDC tokens against its own trusted CA library rather than
    this list, so the value is effectively vestigial but the API still requires it.
  EOT
  type        = list(string)
  default     = ["ab9d0263244dd0326eb67015705a667e79cfe998"]
}

variable "manage_deploy_role_inline_policy" {
  description = <<-EOT
    Attach a least-privilege inline policy (ECR push + eks:DescribeCluster) to the
    deploy role. This is additive: the AdministratorAccess managed policy currently
    attached to the role is not managed here and is left untouched. Detach it by
    hand once you have confirmed the inline policy is sufficient.
  EOT
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Kubernetes namespaces (must match the kustomize overlays)
# ---------------------------------------------------------------------------

variable "workload_namespaces" {
  description = "Namespaces the deploy role manages. Must match the overlay namespaces."
  type        = list(string)
  default     = ["gpu-inference-dev", "gpu-inference-staging", "gpu-inference-prod"]
}
