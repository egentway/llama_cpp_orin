# llama-cpp-orin

Nix flake to run llama.cpp with CUDA acceleration on the Jetson Orin Nano.

To run the default server config:

```bash
nix run
```

To run `llama-server` in router mode:

```bash
nix run .#llama-server-router
```
