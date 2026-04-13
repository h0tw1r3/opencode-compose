# macOS Hybrid Setup Guide (Metal GPU Acceleration)

This guide explains how to run the `opencode` agent in Docker on macOS while leveraging your Mac's Metal GPU for high-speed inference using `llama.cpp`.

## Architecture Overview
Because Docker on macOS runs inside a Linux VM, it cannot access your Mac's GPU directly. We solve this with a **Hybrid Approach**:
1. **Host (macOS)**: Runs `llama-server` to use Metal GPU acceleration.
2. **Container (Docker)**: Runs the `opencode` agent, which communicates with the host via `host.docker.internal`.

---

## Phase 1: Host Setup (Inference Engine)

### 1. Install llama.cpp
The easiest way is via Homebrew:
```bash
brew install llama.cpp
```

### 2. Download the Gemma 4 Model
Download the Unsloth-optimized Gemma 4 GGUF model from Hugging Face and place it in a known directory (e.g., `~/models/`).

### 3. Start the Server
Run the server on your host. The `-ngl 99` flag is **critical**—it tells `llama.cpp` to offload all layers to the GPU (Metal).

```bash
llama-server \
  --model ~/models/gemma-4-unsloth.gguf \
  --port 8081 \
  --ctx-size 32768 \
  --ngl 99
```
*Keep this terminal window open.*

---

## Phase 2: Agent Setup (Docker)

### 1. Configure Environment Variables
To connect the agent to your host, you must point the OpenAI-compatible endpoint to `host.docker.internal`.

Create a `.env` file:
```env
# Point to the llama-server running on your Mac
OPENAI_API_BASE=http://host.docker.internal:8081/v1
OPENAI_API_KEY=not-needed-but-required-by-client
MODEL_NAME=gemma-4
```

### 2. Run the Agent
Launch the container using your preferred method (Docker Compose or `docker run`). Ensure the container can resolve `host.docker.internal`.

**Using Docker Compose:**
```yaml
services:
  opencode:
    image: opencode:latest
    env_file: .env
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

**Using Docker Run:**
```bash
docker run -d \
  --name opencode-agent \
  --env-file .env \
  --add-host=host.docker.internal:host-gateway \
  opencode:latest
```

---

## Phase 3: Verification

To verify the bridge is working, run this command from your terminal:

```bash
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-4",
    "messages": [{"role": "user", "content": "Hello, are you running on Metal?"}]
  }'
```

If you see a JSON response with text, your setup is complete!

## Troubleshooting

| Issue | Cause | Fix |
| :--- | :--- | :--- |
| `Connection Refused` | `llama-server` isn't running or port mismatch | Ensure `llama-server` is active on port `8081`. |
| `Could not resolve host` | Docker cannot find the host | Ensure `--add-host=host.docker.internal:host-gateway` is used. |
| Slow performance | Metal not active | Check `llama-server` logs for `ggml_metal_add_buffer` calls. Ensure `-ngl 99` is present. |
