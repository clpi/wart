# GitHub Actions Workflows

This document describes the GitHub Actions workflows used in the wx project and how to maintain them.

## Available Workflows

### 1. CI Workflow (ci.yml)

**Triggers**: Push to main, Pull Request, Manual dispatch

**Purpose**: Builds and tests the wx runtime on multiple platforms.

**Jobs**:
- `validate-workflows`: Validates all workflow YAML files to catch syntax errors early
- `build`: Builds wx on Ubuntu, Windows, and macOS, runs tests, and builds WASM opcodes CLI

**Matrix Strategy**:
- ubuntu-22.04
- windows-latest
- macos-latest

**Features**:
- Code formatting check with `zig fmt --check` (Ubuntu only)
- Unit tests via `zig build test`
- WASM opcodes CLI build (Ubuntu only)

**Artifacts**: Binary artifacts for each platform

### 2. Release Workflow (release.yml)

**Triggers**: Version tags (v*), Manual dispatch

**Purpose**: Creates GitHub releases with pre-built binaries.

**Platforms**:
- Linux (x86_64)
- Windows (x86_64)
- macOS (x86_64, aarch64)

**Output**: 
- GitHub release with binaries
- SHA256 checksums
- Automated release notes

### 3. Docker Workflow (docker.yml)

**Triggers**: Push to main, Version tags, Pull requests, Releases, Manual dispatch

**Purpose**: Builds and publishes multi-platform Docker images.

**Registries**:
- GitHub Container Registry (ghcr.io) - Always enabled
- Docker Hub - Optional (requires secrets)
- Quay.io - Optional (requires secrets)

**Platforms**:
- linux/amd64
- linux/arm64

**Tags**:
- Latest (main branch)
- Version tags (from git tags)
- Branch names
- Commit SHA

### 4. Benchmark Workflow (benchmark.yml)

**Triggers**: Push to main, Pull requests, Manual dispatch

**Purpose**: Runs performance benchmarks comparing wx against Wasmer and Wasmtime.

**Requirements**:
- WABT (wat2wasm) - Required
- Wasmer - Optional
- Wasmtime - Optional

**Output**: Benchmark results uploaded as artifacts

### 5. Homebrew Formula Update Workflow (homebrew.yml)

**Triggers**: Release published, Manual dispatch

**Purpose**: Automatically updates the Homebrew formula when a new release is published.

**Actions**:
- Downloads the release tarball
- Calculates SHA256 checksum
- Updates Formula/wx.rb with new version and checksum
- Updates Brewfile to match
- Commits and pushes changes to main branch
- Creates/updates HOMEBREW.md documentation

**Manual Trigger**: Can be run manually with a specific release tag

## Workflow Validation

### Automated Validation

Every push and pull request automatically validates all workflow YAML files using the `validate-workflows` job in ci.yml. This catches syntax errors before they can break CI/CD.

### Local Validation

Before pushing changes to workflow files, validate them locally:

```bash
# Run the validation script
.github/validate_workflows.sh

# Or manually with Python
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```

## Common Issues and Solutions

### Issue: Docker Registry Login Fails

**Symptom**: Docker workflow fails during registry login step

**Solution**: 
1. Ensure secrets are properly configured in repository settings
2. The workflow uses `continue-on-error: true` for optional registries
3. Check that secret names match: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `QUAY_USERNAME`, `QUAY_TOKEN`

### Issue: Benchmark Workflow Fails

**Symptom**: Benchmark workflow fails when running benchmarks

**Solutions**:
- Wasmer/Wasmtime installation failures are expected and handled gracefully
- The wx runtime must build successfully
- WASM benchmark files must exist in examples/ directory
- Python 3 must be available (included in ubuntu-22.04)

### Issue: Release Build Fails for Specific Platform

**Symptom**: Release workflow fails for one or more platforms

**Solutions**:
1. Check the target specification in the matrix (e.g., `x86_64-linux`)
2. Verify Zig can cross-compile to that target: `zig targets`
3. Check build.zig for platform-specific issues
4. Review the build logs for platform-specific errors

## Secrets Configuration

### Required Secrets
- `GITHUB_TOKEN` - Automatically provided by GitHub Actions

### Optional Secrets (for Docker registries)
- `DOCKERHUB_USERNAME` - Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub access token
- `QUAY_USERNAME` - Quay.io username  
- `QUAY_TOKEN` - Quay.io access token

To configure secrets:
1. Go to repository Settings
2. Navigate to Secrets and variables → Actions
3. Add new repository secrets

## Maintenance Guidelines

### When Updating Workflows

1. **Validate locally first**: Run `.github/validate_workflows.sh`
2. **Test in a draft PR**: Create a draft PR to test workflow changes
3. **Use semantic versioning**: For action versions (e.g., `actions/checkout@v5`)
4. **Document changes**: Update this file when adding/modifying workflows

### When Updating Zig Version

Update the Zig version in all workflows:
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `.github/workflows/benchmark.yml`
- `Dockerfile`

### When Creating a New Release

The Homebrew formula will be automatically updated when you:
1. Create and push a version tag (e.g., `v0.1.0`)
2. The release workflow builds the binaries
3. The homebrew workflow updates the formula with the new version and SHA256

To manually update the formula for a specific release:
1. Go to Actions → Update Homebrew Formula
2. Click "Run workflow"
3. Enter the release tag (e.g., `v0.1.0`)
4. Click "Run workflow"

### When Adding New Platforms

For ci.yml:
- Add to the matrix strategy

For release.yml:
- Add a new matrix entry with target, artifact_name, and asset_name

## Troubleshooting

### Viewing Workflow Logs

1. Go to the "Actions" tab in GitHub
2. Select the workflow run
3. Click on the job that failed
4. Expand the failed step to view logs

### Common Error Messages

**"Binary not found at ./zig-out/bin/wx"**
- Build failed - check Zig build output
- Artifact path mismatch - verify build.zig output directory

**"Validation failed"**
- YAML syntax error in workflow file
- Run local validation to identify the issue

**"Secret not found"**
- Secret is not configured in repository settings
- Secret name mismatch in workflow file

## Best Practices

1. **Use specific action versions**: `actions/checkout@v5` not `@main`
2. **Add continue-on-error for optional steps**: Prevents workflow failure for non-critical steps
3. **Use matrix strategies**: Test across multiple platforms efficiently
4. **Cache dependencies**: Use GitHub Actions cache for faster builds
5. **Validate before merging**: Always run workflows on draft PRs first

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Docker Build Push Action](https://github.com/docker/build-push-action)
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
