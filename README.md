# GPU inference on Kubernetes

This bundle deploys a single-node GPU inference service using [vLLM](https://docs.vllm.ai/) and the OpenAI-compatible API. It is cloud-neutral at the Kubernetes layer and expects an NVIDIA GPU node prepared with the NVIDIA GPU Operator or the NVIDIA device plugin.

## What is included

- `base/`: namespace, model configuration, vLLM deployment, service, model-cache PVC, PDB, and network policy.
- `overlays/dev/`: a small development overlay with a local image override point.
- `docs/gpu-prerequisites.md`: cluster and node requirements, including AKS notes.

## Prerequisites

- Kubernetes 1.28+
- An NVIDIA GPU node with the `nvidia.com/gpu` resource exposed
- NVIDIA GPU Operator installed in the cluster
- A default StorageClass with enough capacity for the model cache
- `kubectl` and Kustomize

Install the GPU Operator before the workload:

```sh
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=true
```

For managed Kubernetes services, use the provider's supported NVIDIA driver mode and follow `docs/gpu-prerequisites.md` before enabling the operator driver.

## Build the container image

Build the image locally before deploying:

```sh
docker build -t gpu-inference:latest ./k8s
```

The dev overlay is configured to use this local tag automatically via `overlays/dev/kustomization.yaml`.

## Enterprise stage layout

This bundle is organized into separate environment namespaces for enterprise rollout discipline:

- `gpu-inference-dev`
- `gpu-inference-staging`
- `gpu-inference-prod`

Each stage is isolated in its own namespace and can be deployed independently:

```sh
kubectl apply -k overlays/dev
kubectl apply -k overlays/staging
kubectl apply -k overlays/prod
```

## Configure and deploy

Edit `base/configmap.yaml` to choose a model and sizing, then apply the desired stage overlay:

```sh
kubectl apply -k overlays/dev
kubectl -n gpu-inference-dev get pods -w
kubectl -n gpu-inference-dev port-forward svc/gpu-inference 8000:8000
```

The API is then available at `http://127.0.0.1:8000/v1`. Test it with:

```sh
curl http://127.0.0.1:8000/v1/models
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-1.5B-Instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":32}'
```

For gated Hugging Face models, create the optional token secret without committing it:

```sh
kubectl -n gpu-inference create secret generic huggingface-token \
  --from-literal=HF_TOKEN="$HF_TOKEN"
```

## Production hardening

Before exposing this service outside the cluster, add an authenticated gateway or Ingress, configure TLS, set a real StorageClass, pin the vLLM image digest, and replace the default model with a model approved for your workload. The base NetworkPolicy only permits same-namespace ingress but intentionally allows egress for model downloads and DNS.
