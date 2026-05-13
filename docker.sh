#!/usr/bin/env nix-shell
#! nix-shell -i bash -p docker docker-compose

# wart Docker Container Workflow
set -euo pipefail

IMAGE_NAME="wart-runtime"
DEV_IMAGE_NAME="wart-dev"
VERSION=${VERSION:-latest}

build_runtime() {
    echo "🏗️  Building runtime container..."
    docker build --target runtime -t "${IMAGE_NAME}:${VERSION}" .
    docker tag "${IMAGE_NAME}:${VERSION}" "${IMAGE_NAME}:latest"
}

build_dev() {
    echo "🛠️  Building development container..."
    docker build --target dev -t "${DEV_IMAGE_NAME}:${VERSION}" .
    docker tag "${DEV_IMAGE_NAME}:${VERSION}" "${DEV_IMAGE_NAME}:latest"
}

run_runtime() {
    local wasm_file=${1:-""}
    if [[ -z "$wasm_file" ]]; then
        docker run --rm -it "${IMAGE_NAME}:latest"
    else
        docker run --rm -v "$(pwd):/workspace" "${IMAGE_NAME}:latest" "/workspace/$wasm_file"
    fi
}

run_dev() {
    docker run --rm -it -v "$(pwd):/workspace" "${DEV_IMAGE_NAME}:latest"
}

benchmark() {
    echo "📊 Running benchmarks in container..."
    docker run --rm -v "$(pwd):/workspace" "${IMAGE_NAME}:latest" \
        nix develop --command bash bench/run.sh
}

case "${1:-help}" in
    build)
        build_runtime
        build_dev
        ;;
    runtime)
        build_runtime
        ;;
    dev)
        build_dev
        ;;
    run)
        run_runtime "${2:-}"
        ;;
    shell)
        run_dev
        ;;
    bench)
        benchmark
        ;;
    push)
        echo "🚀 Pushing to registry..."
        docker push "${IMAGE_NAME}:${VERSION}"
        docker push "${IMAGE_NAME}:latest"
        ;;
    clean)
        echo "🧹 Cleaning up containers..."
        docker rmi "${IMAGE_NAME}:${VERSION}" "${IMAGE_NAME}:latest" || true
        docker rmi "${DEV_IMAGE_NAME}:${VERSION}" "${DEV_IMAGE_NAME}:latest" || true
        ;;
    help|*)
        echo "wart Docker Workflow"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  build     - Build both runtime and dev containers"
        echo "  runtime   - Build runtime container only"
        echo "  dev       - Build development container only"
        echo "  run [file] - Run wart with optional WASM file"
        echo "  shell     - Enter development shell"
        echo "  bench     - Run benchmarks"
        echo "  push      - Push to registry"
        echo "  clean     - Remove containers"
        echo "  help      - Show this help"
        ;;
esac
