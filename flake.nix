{
  nixConfig = {
    extra-substituters = [
      "https://cache.flox.dev"
      "https://cuda-maintainers.cachix.org"
    ];

    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
    ];
  };

  inputs = {
    llama-cpp.url = "github:ggml-org/llama.cpp";
    nixpkgs.follows = "llama-cpp/nixpkgs";
  };

  outputs = {
    nixpkgs,
    llama-cpp,
    ...
  }: let
    pkgs = nixpkgs.legacyPackages.${system};
    system = "aarch64-linux";
    llama-jetson = llama-cpp.packages."${system}".jetson-orin.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [pkgs.openssl];
      cmakeFlags = (old.cmakeFlags or []) ++ ["-DLLAMA_OPENSSL=ON"];
    });

    tegra-path = "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/aarch64-linux-gnu/tegra";
    model-flag = "-hf unsloth/Qwen3.5-2B-GGUF:Q4_K_M";

    # --chat-template-kwargs '{"enable_thinking":false}' \
    config-flags = ''
      --reasoning off \
      --ctx-size 16384 \
      --n-gpu-layers 99 \
      --flash-attn on \
      --cache-ram 0 \
      -ctk q8_0 \
      -ctv q8_0 \
      --threads 6'';

    llama-server-default = pkgs.writeShellScriptBin "llama-server-default" ''
      ${tegra-path}
      exec ${llama-jetson}/bin/llama-server \
        ${model-flag} \
        ${config-flags} \
        --host 0.0.0.0 \
        --port 8080 \
        "$@"
    '';

    llama-cli-default = pkgs.writeShellScriptBin "llama-cli-default" ''
      ${tegra-path}
      exec ${llama-jetson}/bin/llama-cli \
        ${model-flag} \
        ${config-flags} \
        "$@"
    '';

    dockerImage = pkgs.dockerTools.buildImage {
      name = "llama-cpp-jetson";
      tag = "latest";
      copyToRoot = pkgs.buildEnv {
        name = "image-root";
        paths = [
          llama-jetson
          pkgs.bash
          pkgs.coreutils
        ];
        pathsToLink = ["/bin"];
      };
      config = {
        Cmd = ["${llama-jetson}/bin/llama-server"];
        Env = [
          "LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu/tegra:${pkgs.llvmPackages_latest.libcxx}/lib"
        ];
        Expose = {
          "8080/tcp" = {};
        };
      };
    };
  in {
    formatter."${system}" = pkgs.alejandra;

    packages.${system}.docker = dockerImage;

    devShells."${system}".default = pkgs.mkShell {
      buildInputs = [
        llama-jetson
        llama-server-default
        llama-cli-default
      ];
      shellHook = ''
        ${tegra-path}
      '';
    };

    apps."${system}".default = {
      type = "app";
      program = "${llama-server-default}/bin/llama-server-default";
    };
  };
}
