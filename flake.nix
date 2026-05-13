{
  description = "wart - High-performance WebAssembly runtime written in Zig";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = { zig2nix, ... }: let
    flake-utils = zig2nix.inputs.flake-utils;
  in (flake-utils.lib.eachDefaultSystem (system: let
      zig = zig2nix.outputs.packages.${system}.zig-master;
      env = zig2nix.outputs.zig-env.${system} { zig = zig2nix.outputs.packages.${system}.zig-master; };
      mkWartPackage = { releaseFlag ? null, extraArgs ? [ ] }: env.pkgs.stdenv.mkDerivation {
        pname = "wart";
        version = "0.1.0-alpha";
        src = ./.;
        nativeBuildInputs = with env.pkgs; [ zig wabt wasm-tools ];
        dontConfigure = true;
        dontInstall = true;
        buildPhase = let
          releaseArgs = if releaseFlag == null then "" else "--release=${releaseFlag}";
          extraArgsString = env.pkgs.lib.concatStringsSep " " extraArgs;
        in ''
          runHook preBuild
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
          zig version
          zig build ${releaseArgs} ${extraArgsString} \
            --cache-dir .zig-cache \
            --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" \
            --prefix "$out" \
            -j''${NIX_BUILD_CORES:-1}
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          test -x "$out/bin/wart"
          runHook postInstall
        '';
      };
    in with builtins; with env.pkgs.lib; rec {

      # Release build optimized for distribution
      packages.foreign = mkWartPackage {
        releaseFlag = "fast";
        extraArgs = [ "-Duse-llvm=true" ];
      };

      # Debug build for development
      packages.debug = mkWartPackage { };

      # Small build for embedded/minimal deployments
      packages.small = mkWartPackage {
        releaseFlag = "small";
      };

      # Default build
      packages.default = mkWartPackage {
        releaseFlag = "fast";
      };

      # Container image using nix
      packages.container = env.pkgs.dockerTools.buildImage {
        name = "wart";
        tag = "latest";
        copyToRoot = env.pkgs.buildEnv {
          name = "wart-container-root";
          paths = [ packages.foreign ];
        };
        config = {
          Cmd = [ "${packages.foreign}/bin/wart" "--help" ];
          WorkingDir = "/workspace";
          Volumes = { "/workspace" = {}; };
          User = "1000:1000";
          Env = [
            "PATH=${packages.foreign}/bin"
          ];
        };
      };

      # Development container
      packages.container-dev = env.pkgs.dockerTools.buildImage {
        name = "wart-dev";
        tag = "latest";
        copyToRoot = env.pkgs.buildEnv {
          name = "wart-dev-root";
          paths = with env.pkgs; [
            packages.default
            wabt wasm-tools binaryen
            hyperfine wasmer wasmtime
            bash coreutils
          ];
        };
        config = {
          Cmd = [ "${env.pkgs.bash}/bin/bash" ];
          WorkingDir = "/workspace";
          Volumes = { "/workspace" = {}; };
          User = "1000:1000";
          Env = [
            "PATH=${env.pkgs.lib.makeBinPath (with env.pkgs; [
              packages.default wabt wasm-tools binaryen
              hyperfine wasmer wasmtime bash coreutils
            ])}"
          ];
        };
      };

      # Apps
      apps.bundle = {
        type = "app";
        program = "${packages.foreign}/bin/wart";
      };

      apps.default = env.app [] "zig build run -- \"$@\"";
      apps.build = env.app [] "zig build \"$@\"";
      apps.test = env.app [] "zig build test -- \"$@\"";
      apps.bench = env.app [] "bash bench/run.sh";
      apps.verify = env.app [] "bash scripts/run-spec-tests.sh \"$@\"";
      apps.bench-core = env.app [] "bash scripts/run-benchmarks.sh --profile core-universal \"$@\"";
      apps.bench-extended = env.app [] "bash scripts/run-benchmarks.sh --profile preview1 \"$@\"";
      apps.fmt = env.app [] "zig fmt src examples";
      apps.docker = env.app [] "./docker.sh \"$@\"";

      # Development shells
      devShells.default = env.mkShell {
        buildInputs = with env.pkgs; [
          binaryen
          git
          jq
          python3
          wasmtime
          wasmer
        ];
          nativeBuildInputs = with env.pkgs; [
            wabt wasm-tools binaryen
            ninja
            hyperfine # for benchmarking
          ];

        shellHook = ''
          echo "wart development environment"
          echo "Available commands:"
          echo "  zig build          - Build wart runtime"
          echo "  zig build test     - Run tests"
          echo "  bash bench/run.sh  - Run benchmarks"
          echo "  zig fmt src        - Format code"
          echo ""
          echo "Build variants:"
          echo "  nix build .#debug  - Debug build"
          echo "  nix build .#small  - Minimal build"
          echo "  nix build .#foreign - Release build"
          echo ""
          echo "Containers:"
          echo "  nix build .#container     - Build runtime container"
          echo "  nix build .#container-dev - Build dev container"
          echo "  ./docker.sh build        - Build with Docker"
        '';
      };

      devShells.minimal = env.mkShell {
        nativeBuildInputs = with env.pkgs; [ wabt ];
      };

      devShells.bench = env.mkShell {
        nativeBuildInputs = with env.pkgs; [
          git jq python3
          wabt wasm-tools hyperfine
          wasmer wasmtime # comparison runtimes
        ];
      };

      devShells.docker = env.mkShell {
        nativeBuildInputs = with env.pkgs; [
          docker
          docker-compose
          docker-buildx
          skopeo
          dive
        ];

        shellHook = ''
          echo "wart Docker development shell"
          echo "Quick commands:"
          echo "  ./docker.sh build  - Build containers"
          echo "  ./docker.sh run     - Run wart container"
          echo "  ./docker.sh shell   - Development shell"
        '';
      };
    }));
}
