# GitHub Actions Setup Guide

This guide explains how to configure GitHub Actions for the wx WebAssembly runtime project.

## Required Secrets

### ZIG_VERSION (Optional)
Controls which Zig version is used for builds and tests.

**Default**: `master` (uses latest Zig master build)

**To set a specific version**:
1. Go to repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `ZIG_VERSION`
4. Value: 
   - `master` - Use latest Zig master (recommended for development)
   - `0.16.0` - Use specific Zig version
   - `0.17.0` - Use specific Zig version
5. Click "Add secret"

**When to use**: Set this if you need to pin to a specific Zig version for stability.

## Optional Publishing Secrets

These secrets are only needed if you want to publish to the respective package managers.

### Docker Hub Publishing
**Workflow**: `docker.yml`

**Secrets**:
- `DOCKERHUB_USERNAME` - Your Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub access token (from Account Settings → Security → Access Tokens)

**How to generate token**:
1. Log in to Docker Hub
2. Go to Account Settings → Security
3. Click "New Access Token"
4. Give it a description (e.g., "GitHub Actions")
5. Set permissions: Read, Write, Delete
6. Generate and copy the token

### Arch User Repository (AUR) Publishing
**Workflow**: `aur.yml`

**Secrets**:
- `AUR_SSH_PRIVATE_KEY` - SSH private key for AUR account

**How to setup**:
1. Generate SSH key: `ssh-keygen -t ed25519 -f ~/.ssh/aur_wx`
2. Copy public key content to AUR account: https://aur.archlinux.org/account → SSH Public Keys
3. Add private key as GitHub secret (paste the entire file content of the private key)

### Snap Store Publishing
**Workflow**: `snap.yml`

**Secrets**:
- `SNAPCRAFT_STORE_CREDENTIALS` - Snapcraft login credentials

**How to generate**:
1. Install snapcraft: `sudo snap install snapcraft --classic`
2. Register package at https://snapcraft.io
3. Export login: `snapcraft export-login --snaps=wx`
4. Copy the output as the secret value

### Chocolatey Publishing
**Workflow**: `chocolatey.yml`

**Secrets**:
- `CHOCOLATEY_API_KEY` - Chocolatey API key

**How to get**:
1. Register at https://chocolatey.org
2. Go to Account → API Keys
3. Create new API key
4. Copy the key

### Scoop Bucket Publishing
**Workflow**: `scoop.yml`

**Secrets**:
- `SCOOP_BUCKET_TOKEN` - GitHub personal access token

**How to generate**:
1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with `repo` scope
3. Copy the token

## Automatic Secrets

These secrets are automatically provided by GitHub and don't need configuration:

### GITHUB_TOKEN
- **Status**: ✅ Automatically provided
- **Usage**: Used in docker.yml, release.yml, apt.yml
- **Permissions**: Controlled by workflow `permissions` section

### OIDC for FlakeHub
- **Status**: ✅ Uses OIDC (no token needed)
- **Workflow**: flakehub-publish-tagged.yml
- **How it works**: Uses `id-token: write` permission instead of static token

## Workflow Testing

To test workflows without triggering all of them:

1. **Test CI workflow**:
   ```bash
   # Push to a branch or create a PR
   git push origin feature-branch
   ```

2. **Test specific workflow manually**:
   - Go to Actions tab in GitHub
   - Select the workflow
   - Click "Run workflow"
   - Select branch and inputs (if any)

3. **Test with specific Zig version**:
   - Set `ZIG_VERSION` secret to desired version
   - Trigger workflow
   - Check logs to confirm version used

## Zig Version Matrix

The workflows are designed to work with:

| Zig Version | Status | Notes |
|-------------|--------|-------|
| `master` | ✅ Default | Latest Zig master build (recommended) |
| `0.17.0` | ✅ Supported | Stable release |
| `0.16.0` | ✅ Supported | Stable release |
| `0.15.1` | ❌ Deprecated | Upgrade to 0.16+ or master |

## Troubleshooting

### Workflows failing with "zig not found"
- Ensure `ZIG_VERSION` is set to a valid version or leave unset for `master`

### Build failing with Zig master
- Zig master may have temporary issues, try pinning to latest stable version
- Check Zig build status: https://ziglang.org/builds/

### Permission errors for publishing
- Ensure secrets are correctly set
- Verify tokens have correct permissions
- Check workflow `permissions` section

### FlakeHub publish failing
- Ensure workflow has `id-token: write` permission
- Verify package name matches your FlakeHub registration

## Best Practices

1. **For development**: Leave `ZIG_VERSION` unset to use `master`
2. **For releases**: Pin to specific version (e.g., `0.16.0`)
3. **For testing**: Use `master` but monitor for breaking changes
4. **Secrets management**:
   - Rotate publishing tokens regularly
   - Use descriptive token names
   - Set appropriate token permissions
   - Enable secret scanning in repository settings

## Workflow Security

All workflows follow GitHub Actions security best practices:
- ✅ No hardcoded credentials
- ✅ Secrets only used in secure contexts
- ✅ Minimal permissions requested
- ✅ OIDC used where possible (e.g., FlakeHub)
- ✅ Branch protection rules recommended for main

## Support

For issues with workflows:
1. Check workflow logs in Actions tab
2. Refer to this guide for secret configuration
3. Open an issue with workflow name and error message
4. Include relevant log snippets (redact any secrets)
