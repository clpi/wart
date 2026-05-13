# Container Registry Setup

This document describes how to set up the required secrets for publishing Docker images to multiple container registries.

## Required Secrets

The following secrets need to be configured in your GitHub repository settings:

### Docker Hub

1. **DOCKERHUB_USERNAME**: Your Docker Hub username
2. **DOCKERHUB_TOKEN**: Docker Hub access token
   - Create at: https://hub.docker.com/settings/security
   - Click "New Access Token"
   - Give it a descriptive name like "GitHub Actions"
   - Copy the token and save it as a secret

### Quay.io

1. **QUAY_USERNAME**: Your Quay.io username (or organization name)
2. **QUAY_TOKEN**: Quay.io robot account token or CLI password
   - For robot accounts: https://quay.io/organization/[YOUR_ORG]?tab=robots
   - Or use your account credentials from: https://quay.io/user/[YOUR_USERNAME]?tab=settings

### GitHub Container Registry (ghcr.io)

No additional secrets required! The workflow uses the built-in `GITHUB_TOKEN` which is automatically provided by GitHub Actions.

## How to Add Secrets

1. Go to your repository on GitHub
2. Click on **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with its name and value
5. Click **Add secret**

## Registry Image URLs

After setup, your images will be available at:

- **GitHub Container Registry**: `ghcr.io/clpi/wx:latest`
- **Docker Hub**: `[DOCKERHUB_USERNAME]/wx:latest`
- **Quay.io**: `quay.io/clpi/wx:latest`

## Testing Locally

Before pushing to registries, you can test building the multi-platform image locally:

```bash
# Build for multiple platforms
docker buildx build --platform linux/amd64,linux/arm64 -t wx:test .

# Build and test for your current platform
docker build -t wx:test .
docker run --rm wx:test --help
```

## Disabling Specific Registries

If you don't want to push to all registries, you can:

1. **Option 1**: Don't add the secrets for registries you don't want to use
   - The workflow will skip login for registries without secrets
   - However, the build step may fail if secrets are missing

2. **Option 2**: Modify `.github/workflows/docker.yml`
   - Comment out or remove the login and metadata steps for unused registries
   - Update the `images:` list in the metadata step

## Platform Support

The Docker images are built for:
- `linux/amd64` (x86_64)
- `linux/arm64` (aarch64)

Both platforms are fully supported thanks to Zig's excellent cross-compilation capabilities.
