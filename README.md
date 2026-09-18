# GPU inference on Kubernetes

This bundle deploys a single-node GPU inference service using [vLLM](https://docs.vllm.ai/) and the OpenAI-compatible API. The Kubernetes layer is cloud-neutral and expects an NVIDIA GPU node; the `terraform/` and `cluster-bootstrap/` layers target AWS EKS.

### Layout

| Path | Layer | Applied by |
|---|---|---|
| `terraform/` | AWS infrastructure: VPC, EKS, GPU nodes, ECR, CI IAM roles | `terraform apply`, or the `terraform-apply` pipeline job |
| `cluster-bootstrap/` | Cluster-scoped singletons: default gp3 StorageClass, NVIDIA device plugin | `kubectl apply -k cluster-bootstrap` |
| `base/` | The namespaced workload: ConfigMap, Deployment, Service, PVC, PDB, NetworkPolicy, ServiceAccount | via an overlay |
| `overlays/{dev,staging,prod}` | Per-environment namespace and config | `kubectl apply -k overlays/<env>` |
| `docs/gpu-prerequisites.md` | Node and cluster requirements, including AKS notes | — |

The order matters and never varies: infrastructure, then cluster bootstrap, then the workload. The manifests have nowhere to land until the cluster and the EBS CSI driver exist.

## Deploying

The pipeline does all of it, in sequence:

```
terraform-plan -> terraform-apply -> build-and-push -> bootstrap-cluster -> deploy-dev -> deploy-staging -> deploy-prod
```

See [`terraform/README.md`](terraform/README.md) for the first-time setup: the state bucket, the two secrets, and the repository variables that gate apply and the staging/prod deploys. The first `terraform apply` has to run from a workstation, because the role CI assumes is created by that apply.

### Manually

```sh
# Infrastructure
cd terraform && terraform init -backend-config=backend.hcl && terraform apply && cd ..

aws eks update-kubeconfig --name gpu-inference --region us-east-1

# Cluster prerequisites (once per cluster)
kubectl apply -k cluster-bootstrap

# Workload. The image is not pinned in the overlays, so set it explicitly.
cd overlays/dev
kustomize edit set image vllm/vllm-openai=<account>.dkr.ecr.<region>.amazonaws.com/dev/k8s-vllm:<tag>
kubectl apply -k .
kubectl -n gpu-inference-dev rollout status deployment/gpu-inference --timeout=15m
```

Then reach the API:

```sh
kubectl -n gpu-inference-dev port-forward svc/gpu-inference 8000:8000
curl http://127.0.0.1:8000/v1/models
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-1.5B-Instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":32}'
```

Note that `port-forward` reaches the pod through the kubelet and bypasses NetworkPolicy, so a successful curl here does not prove in-cluster networking works.

## Prerequisites

- Kubernetes 1.28+
- G-instance vCPU quota. **New AWS accounts have zero**, so the GPU node group cannot launch anything until an increase is approved. A `g5.2xlarge` is 8 vCPU. `terraform plan` warns if your quota can't cover the configured pool.
- A node advertising `nvidia.com/gpu`. On EKS this comes from the `AL2023_x86_64_NVIDIA` AMI (driver and container toolkit) plus the device plugin in `cluster-bootstrap/`. On other clouds, use the NVIDIA GPU Operator per `docs/gpu-prerequisites.md`.
- A default StorageClass. `cluster-bootstrap/` provides gp3 for EKS.

## GPU capacity and environments

Each environment namespace runs one replica holding one entire GPU, so three concurrent environments need three GPU nodes. `deploy-staging` and `deploy-prod` are therefore opt-in behind the `DEPLOY_STAGING` and `DEPLOY_PROD` repository variables. Enabling them without the capacity leaves the pod `Pending` and fails after the full rollout timeout.

## Configuration

Edit `base/configmap.yaml` to change the model and sizing. The dev overlay patches `GPU_MEMORY_UTILIZATION` and `MAX_MODEL_LEN` on top.

For gated Hugging Face models, create the optional token secret without committing it:

```sh
kubectl -n gpu-inference-dev create secret generic huggingface-token \
  --from-literal=HF_TOKEN="$HF_TOKEN"
```

## Build the image

```sh
docker build -t gpu-inference:latest .
```

The Dockerfile only layers environment defaults and labels onto `vllm/vllm-openai`, and the Deployment overrides the entrypoint anyway, so it carries no application code. If you aren't customising the runtime, using the upstream image directly avoids pushing several gigabytes per commit.

## Production hardening

Before exposing this outside the cluster: add an authenticated gateway or Ingress, configure TLS, pin the vLLM image by digest, and replace the default model with one approved for your workload.

The NetworkPolicy permits ingress only from pods in the same namespace, and deliberately allows all egress so the container can download model weights and resolve DNS. Tighten egress once weights are baked into the image or mirrored inside the VPC.

Namespaces enforce Pod Security `baseline` and audit at `restricted`. The upstream vLLM image runs as root, which is why `restricted` is not enforced; check the audit annotations before tightening it.

`terraform/README.md` lists the remaining infrastructure caveats, including the public API endpoint and the permissions on the deploy role.
