# docker-openclaw

Builds a custom OpenClaw Docker image.

## GitHub Actions

The repository includes `.github/workflows/docker-image.yml`.

- Pull requests build the image for validation.
- Pushes to `main` build and publish to `ghcr.io/<owner>/docker-openclaw`.
- Git tags matching `v*` also publish tagged images.

The OpenClaw version is pinned in `Dockerfile` via `ARG OPENCLAW_TAG`.

On first boot, the image also seeds `plugins.entries.diffs.enabled=true` and
`plugins.entries.lobster.enabled=true` into `openclaw.json` when those settings
are unset, so bundled diff-viewer and Lobster support are available without
interactive plugin installs.
