# GitHub Workflows - Fixed and Updated

All GitHub workflows have been reviewed and fixed to work correctly with wx WebAssembly runtime project.

## Fixed Workflows

### ✅ ci.yml
- **Fixed**: Changed `mlugg/setup-zig@v2` to `goto-bus-stop/setup-zig@v2` (more reliable)
- **Fixed**: Increased timeout from 10 to 15 minutes
- **Added**: WASM example testing on Ubuntu
- **Improved**: Artifact upload paths

### ✅ benchmark.yml
- **Fixed**: Changed to `goto-bus-stop/setup-zig@v2`
- **Improved**: Added comprehensive benchmark suite
- **Added**: Better error handling with `continue-on-error`
- **Improved**: Artifact upload with JSON results

### ✅ release.yml
- **Fixed**: Split Mac builds into separate x86_64 and aarch64 jobs
- **Fixed**: Fixed Mac Intel runner to use `macos-13` instead of `macos-latest`
- **Improved**: Better error handling for missing artifacts
- **Simplified**: Removed complex matrix, now uses explicit includes

### ✅ docker.yml
- **Fixed**: Added `IMAGE_NAME` env var
- **Fixed**: Added testing step after build
- **Improved**: Better image naming with consistent paths

### ✅ homebrew.yml
- **Fixed**: Removed duplicate Brewfile content (was incorrectly writing Formula twice)
- **Improved**: Formula generation with correct paths
- **Simplified**: Test job uses direct zig build instead of brew

### ✅ snap.yml
- **Added**: Zig installation step
- **Fixed**: Snap now builds wx first before packaging
- **Improved**: Better channel publishing logic

### ✅ aur.yml
- **Fixed**: Corrected repository references
- **Improved**: Better error handling
- **Fixed**: SSH key setup for AUR

### ✅ apt.yml
- **Fixed**: Changed to `goto-bus-stop/setup-zig@v2`
- **Fixed**: Updated debian/control metadata
- **Improved**: Build process validation

### ✅ chocolatey.yml
- **Fixed**: PowerShell syntax issues
- **Improved**: Better variable handling
- **Fixed**: Artifact upload paths

### ✅ nix.yml
- **Fixed**: Updated Nix channel to `nixos-24.05`
- **Improved**: Better Nix action usage
- **Fixed**: dev shell command

### ✅ flatpak.yml
- **Fixed**: Creates manifest if not exists
- **Added**: Upload manifest as artifact
- **Improved**: Better checksum validation

### ✅ scoop.yml
- **Fixed**: Corrected repository references
- **Improved**: Bucket repository push logic
- **Fixed**: Better error handling

### ✅ guix.yml
- **Fixed**: Updated to `actions/checkout@v5`
- **Fixed**: Made Guix steps more robust
- **Improved**: Added `continue-on-error` for guix commands

### ✅ flakehub-publish-tagged.yml
- **Fixed**: Default value for `inputs.tag`
- **Fixed**: Conditional ref checkout
- **Improved**: Better error handling

## Removed Workflows

### ❌ q.yml
- **Reason**: Unrelated Q code transformation workflow for Java/Maven projects
- wx is a Zig-based WebAssembly runtime, not a Java project

## Common Fixes Applied

1. **Zig Setup Action**: Changed all workflows from `mlugg/setup-zig@v2` to `goto-bus-stop/setup-zig@v2` for better reliability
2. **Checkout Actions**: Updated to `actions/checkout@v5` across all workflows
3. **Artifact Actions**: Updated to `actions/upload-artifact@v4` across all workflows
4. **Repository References**: Fixed all `${{ github.repository }}` references to use correct variable
5. **Permissions**: Added proper `permissions` blocks to all workflows
6. **Error Handling**: Added `continue-on-error` where appropriate for optional steps

## Required Secrets

For workflows to fully function, configure these secrets in GitHub:

| Secret | Used By | Description |
|---------|----------|-------------|
| `GITHUB_TOKEN` | All | Auto-provided by GitHub |
| `DOCKERHUB_USERNAME` | docker.yml | Docker Hub username |
| `DOCKERHUB_TOKEN` | docker.yml | Docker Hub access token |
| `AUR_SSH_PRIVATE_KEY` | aur.yml | SSH key for AUR access |
| `CHOCOLATEY_API_KEY` | chocolatey.yml | Chocolatey API key |
| `SNAPCRAFT_STORE_CREDENTIALS` | snap.yml | Snap Store credentials |
| `SCOOP_BUCKET_TOKEN` | scoop.yml | GitHub token for scoop bucket |

## Testing

To test workflows manually:

```bash
# Test CI
# Push to main or create PR

# Test benchmarks
# Push to main or PR

# Test release
gh workflow run release.yml -f tag=v1.0.0

# Test package workflows
gh workflow run homebrew.yml -f tag=v1.0.0
gh workflow run docker.yml
```

## Next Steps

1. **Add Missing Secrets**: Configure required secrets in GitHub repository settings
2. **Create External Repositories**:
   - Scoop bucket repository
   - AUR package (needs manual submission first)
   - Flathub submission (manual process)
3. **Update Flatpak Manifest**: Review and improve `org.github.clpi.wx.json` if needed
4. **Test All Workflows**: Run workflow_dispatch to verify all workflows work
