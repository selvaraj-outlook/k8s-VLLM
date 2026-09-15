FROM vllm/vllm-openai:v0.8.5

ENV VLLM_HOST=0.0.0.0 \
    VLLM_PORT=8000 \
    HF_HUB_DISABLE_TELEMETRY=1

LABEL org.opencontainers.image.title="GPU Inference" \
      org.opencontainers.image.description="vLLM OpenAI-compatible inference image for GPU-backed Kubernetes workloads" \
      org.opencontainers.image.source="https://github.com/" \
      org.opencontainers.image.vendor="Kiro"

ENTRYPOINT ["vllm"]
CMD ["serve", "--host", "0.0.0.0", "--port", "8000"]
