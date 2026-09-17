# ---------------------------------------------------------------------------
# GPU service quota
#
# New AWS accounts get 0 vCPU for "Running On-Demand G and VT instances", which
# means the GPU node group cannot launch a single instance. The node group
# creation then fails partway through the apply, leaving the stack half built.
#
# This is opt-in and defaults to off, because a quota increase is an asynchronous
# request that AWS may take hours to approve or may decline outright, and
# Terraform will wait on it. The usual flow is:
#
#   1. Request the increase (here, or in the Service Quotas console).
#   2. Wait for approval.
#   3. Apply with the GPU node group sized above zero.
#
# Until it is approved, set gpu_min_size = 0 and gpu_desired_size = 0 so
# everything else applies cleanly and the node group is created empty.
# ---------------------------------------------------------------------------

variable "request_gpu_quota_increase" {
  description = "Submit a Service Quotas increase request for G-instance vCPUs. Asynchronous: Terraform will wait for AWS to act on it, which can take hours."
  type        = bool
  default     = false
}

variable "gpu_quota_vcpus" {
  description = "Requested G and VT vCPU quota. A g5.2xlarge is 8 vCPU, so this must be at least 8 x the number of GPU nodes you intend to run concurrently."
  type        = number
  default     = 8
}

resource "aws_servicequotas_service_quota" "gpu_vcpus" {
  count = var.request_gpu_quota_increase ? 1 : 0

  service_code = "ec2"
  # L-DB2E81BA: Running On-Demand G and VT instances (measured in vCPUs).
  # L-3819A6DF: All G and VT Spot Instance Requests.
  quota_code = var.gpu_capacity_type == "SPOT" ? "L-3819A6DF" : "L-DB2E81BA"
  value      = var.gpu_quota_vcpus
}

# Fail early with a clear message rather than 15 minutes into an apply, when the
# GPU pool is sized above zero but the account has no G-instance quota.
data "aws_servicequotas_service_quota" "gpu_vcpus_current" {
  service_code = "ec2"
  quota_code   = var.gpu_capacity_type == "SPOT" ? "L-3819A6DF" : "L-DB2E81BA"
}

check "gpu_quota_is_sufficient" {
  assert {
    condition = var.gpu_desired_size == 0 || data.aws_servicequotas_service_quota.gpu_vcpus_current.value > 0
    error_message = format(
      "GPU quota is %g vCPU in %s but gpu_desired_size is %d. The GPU node group will fail to launch instances. Either wait for the quota increase to be approved, or set gpu_desired_size = 0 and gpu_min_size = 0 to create the node group empty. Check status with: aws service-quotas list-requested-service-quota-change-history --service-code ec2 --region %s",
      data.aws_servicequotas_service_quota.gpu_vcpus_current.value,
      var.aws_region,
      var.gpu_desired_size,
      var.aws_region,
    )
  }
}
