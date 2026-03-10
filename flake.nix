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
    lib = nixpkgs.lib;
    system = "aarch64-linux";
    llama-jetson = llama-cpp.packages."${system}".jetson-orin.overrideAttrs (old: {
      cmakeFlags =
        (old.cmakeFlags or [])
        ++ [
          "-DLLAMA_CURL=ON"
          "-DLLAMA_OPENSSL=ON"
        ];
    });

    tegra-path = "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/aarch64-linux-gnu/tegra";
    model-flag = "-hf unsloth/Qwen3.5-2B-GGUF:Q4_K_S";

    llama-server-default = pkgs.writeShellScriptBin "llama-server-default" ''
      ${tegra-path}
      exec ${llama-jetson}/bin/llama-server \
        ${model-flag}
        --host 0.0.0.0 --port 8080 \
        --n-gpu-layer 99 \
        "$@"
    '';

    llama-cli-default = pkgs.writeShellScriptBin "llama-cli-default" ''
      ${tegra-path}
      exec ${llama-jetson}/bin/llama-server \
        ${model-flag}
        --n-gpu-layer 99 \
        "$@"
    '';

    dockerImage = pkgs.dockerTools.buildImage {
      name = "llama-cpp-jetson";
      tag = "latest";
      contents = [
        llama-jetson
        pkgs.bash
        pkgs.coreutils
      ];
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
    contents = [
      llama-jetson
    ];
    config = {
      Cmd = ["${llama-jetson}/bin/llama-server"];
      Env = [
        "LD_LIBRARY_PATH=/usr/local/cuda/compat:${pkgs.llvmPackages_latest.libcxx}/lib"
      ];
      Expose = {
        "8080/tcp" = {};
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
