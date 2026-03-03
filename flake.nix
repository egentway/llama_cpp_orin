{
  nixConfig = {
    extra-substituters = [
      "https://cuda-maintainers.cachix.org"
    ];

    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
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
    system = "aarch64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        cudaSupport = true;
        cudaCapabilities = ["8.7"];
        cudaEnableForwardCompat = false;
      };
      overlays = [
        llama-cpp.overlays.default
      ];
    };
    tegra-path = "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/aarch64-linux-gnu/tegra";
    model-flag = "-hf unsloth/Qwen3.5-2B-GGUF:Q4_K_S";
    llama-jetson = pkgs.llamaPackages.llama-cpp;
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
  in {
    packages."${system}".llamaJetsonOrinNano = pkgs.llamaPackages.llama-cpp;

    formatter."${system}" = pkgs.alejandra;

    devShells."${system}".default = pkgs.mkShell {
      buildInputs = [
        pkgs.llamaPackages.llama-cpp
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
