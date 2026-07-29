# docker-openclaw

Builds a custom OpenClaw Docker image.

## GitHub Actions

The repository includes `.github/workflows/docker-image.yml`.

- Pull requests build the image for validation.
- Pushes to `main` build and publish to `ghcr.io/<owner>/docker-openclaw`.
- Git tags matching `v*` also publish tagged images.

The OpenClaw version is pinned in `Dockerfile` via `ARG OPENCLAW_TAG`.
RTK is pinned via `ARG RTK_VERSION`.

On first boot, the image also seeds `plugins.entries.diffs.enabled=true`,
`plugins.entries.lobster.enabled=true`, and
`plugins.entries["rtk-rewrite"].enabled=true` into `openclaw.json` when those
`plugins.entries.google-meet.enabled=true` into `openclaw.json` when those
settings are unset, so bundled diff-viewer, Lobster, Google Meet, and RTK
command rewriting are available without interactive plugin installs.

The RTK integration bundles the upstream OpenClaw plugin under
`openclaw/extensions/rtk-rewrite` and installs the `rtk` binary into the image.
