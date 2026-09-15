# GPU prerequisites

The workload requests one NVIDIA GPU with:

```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
```

The node must expose that extended resource:

```sh
kubectl describe node <gpu-node> | grep -A5 Allocatable
kubectl get pods -A -l app.kubernetes.io/name=nvidia-device-plugin-daemonset
```

## NVIDIA GPU Operator

The recommended cluster setup is NVIDIA GPU Operator. It installs and manages the device plugin, container toolkit, feature discovery, and (when supported by the provider) drivers. Confirm the operator's driver setting with your cluster provider before installing it.

## AKS notes

For AKS, create a GPU node pool with a supported `Standard_NC*`, `Standard_ND*`, or newer GPU VM SKU in a region with capacity. Apply a GPU taint if the pool should only run GPU workloads, and make sure the AKS NVIDIA device plugin or GPU Operator exposes `nvidia.com/gpu`. The deployment tolerates the conventional `nvidia.com/gpu=present:NoSchedule` taint and selects nodes labeled `nvidia.com/gpu.present=true`.

Do not commit cloud credentials or a Hugging Face token. Supply the optional `huggingface-token` secret at deploy time when the selected model is gated.
