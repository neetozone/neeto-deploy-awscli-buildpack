# AWS CLI Buildpack

This buildpack installs AWS CLI for use in Cloud Native Buildpacks.

## Multi-Architecture Support

This buildpack supports both `amd64` and `arm64` targets.

## Building the Buildpack

`scripts/package.sh` requires a version and supports multi-arch output.

```bash
# Build multi-arch buildpackage (auto-loads targets from buildpack.toml)
./scripts/package.sh --version 0.47.18

# Or specify targets explicitly
./scripts/package.sh --version 0.47.18 --target linux/amd64 --target linux/arm64

# Or build a single architecture
./scripts/package.sh --version 0.47.18 --target linux/amd64 --output build/buildpackage-linux-amd64.cnb
```

Default output base name is `build/buildpackage.cnb`.

- For one target, one `.cnb` file is generated.
- For multiple targets, `pack` generates one file per target with architecture suffixes.

The buildpack archive used for publish is generated at `build/buildpack.tgz`.

## Publishing the Buildpack

Publish to a registry:

```bash
./scripts/publish.sh \
  --image-ref 348674388966.dkr.ecr.us-east-1.amazonaws.com/neeto-deploy/buildpacks/awscli:0.47.18 \
  --archive-path build/buildpack.tgz
```

`scripts/publish.sh` reads `[[targets]]` from `buildpack.toml`. If multiple targets are configured, it publishes per-arch images and creates a multi-arch manifest list at `--image-ref`.

## Versions

- `aws`: `latest`
