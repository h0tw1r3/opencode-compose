
## Local Gemma LLM

### 48GB unified memory

```sh
llama-server \
    -m unsloth/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \
    --ctx-size 96000 \
    --ctx-checkpoints 2 \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --cache-ram 2048 \
    --n-gpu-layers 99 \
    --flash-attn on \
    --no-mmap \
    --mlock \
    --port 8081 \
    --jinja \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 64
```
