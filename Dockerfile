# Base images are pinned to SHA256 digests for reproducible builds.
# Trade-off: digests must be updated manually when upstream tags move.
# To update, run: docker buildx imagetools inspect node:24-bookworm (or podman)
# and replace the digest below with the current multi-arch manifest list entry.
ARG OPENCLAW_NODE_BOOKWORM_IMAGE="node:24-bookworm"
ARG OPENCLAW_NODE_BOOKWORM_DIGEST="sha256:3a09aa6354567619221ef6c45a5051b671f953f0a1924d1f819ffb236e520e6b"
ARG GOGCLI_VERSION="0.34.1"
ARG WACLI_VERSION="0.13.0"

FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE}@${OPENCLAW_NODE_BOOKWORM_DIGEST}

ARG GOGCLI_VERSION
ARG WACLI_VERSION

# Verify Docker apt signing key fingerprint before trusting it as a root key.
# Update DOCKER_GPG_FINGERPRINT when Docker rotates release keys.
ARG DOCKER_GPG_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

SHELL ["/bin/bash", "-c"]
ENV SHELL="/bin/bash"

USER root
ENV HOME="/root"
WORKDIR "${HOME}"

COPY nodejs-dummy.yaml ${HOME}/nodejs-dummy.yaml

RUN set -exuo pipefail \
	&& install -m 0755 -d /etc/apt/keyrings \
	&& curl -fsSL https://download.docker.com/linux/debian/gpg -o /tmp/docker.gpg.asc \
	&& expected_fingerprint="$(printf '%s' "${DOCKER_GPG_FINGERPRINT}" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')" \
	&& actual_fingerprint="$(gpg --batch --show-keys --with-colons /tmp/docker.gpg.asc | awk -F: '$1 == "fpr" { print toupper($10); exit }')" \
	&& if [ -z "$actual_fingerprint" ] || [ "$actual_fingerprint" != "$expected_fingerprint" ]; \
		then \
			echo "ERROR: Docker apt key fingerprint mismatch (expected $expected_fingerprint, got ${actual_fingerprint:-<empty>})" >&2; \
			exit 1; \
		fi \
	&& gpg --dearmor -o /etc/apt/keyrings/docker.gpg /tmp/docker.gpg.asc \
	&& rm -f /tmp/docker.gpg.asc \
	&& chmod a+r /etc/apt/keyrings/docker.gpg \
	&& printf \
		'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable\n' \
		"$(dpkg --print-architecture)" \
		> /etc/apt/sources.list.d/docker.list \
	&& DEBIAN_FRONTEND=noninteractive apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y equivs \
	&& equivs-build nodejs-dummy.yaml \
	&& dpkg -i nodejs_1.0_all.deb \
	&& rm nodejs-dummy.yaml nodejs_1.0_all.deb \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y \
		bash \
		build-essential \
		ca-certificates \
		ccache \
		chromium \
		clang-tools \
		cmake \
		curl \
		dnsutils \
		docker-ce-cli \
		docker-compose-plugin \
		ffmpeg \
		fonts-liberation \
		fonts-noto-color-emoji \
		gh \
		git \
		gnupg \
		hostname \
		iproute2 \
		iputils-ping \
		jq \
		libsqlite3-dev \
		lsof \
		make \
		novnc \
		openssl \
		procps \
		pipx \
		python3 \
		ripgrep \
		rsync \
		socat \
		tmux \
		websockify \
		x11vnc \
		xvfb \
	&& rm -rf /var/lib/apt/lists/*

# Enable standard aliases and create blank space before other tools edit bashrc.
RUN set -exuo pipefail \
	&& sed 's/^# alias/alias/g' -i ${HOME}/.bashrc \
	&& echo '' >> ${HOME}/.bashrc

# Install go to the global /usr/local/bin
RUN set -exuo pipefail \
	&& export GOROOT='/usr/local/src/go' GOPATH='/usr/local/go' GOBIN='/usr/local/bin' \
	&& bash <(curl -sL https://git.io/go-installer) \
	&& mv ${GOROOT}/bin/go ${GOBIN}/go \
	&& mv ${GOROOT}/bin/gofmt ${GOBIN}/gofmt \
	&& rmdir ${GOROOT}/bin ${GOPATH}/bin \
	&& echo '' >> ${HOME}/.bashrc

# Install bun to the global /usr/local/bin and skip editing bashrc
RUN set -exuo pipefail \
	&& BUN_INSTALL='/usr/local' SHELL='NOSHELL' \
		bash <(curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL https://bun.sh/install)

# Install standalone CLI binaries needed by bundled OpenClaw skills without
# depending on Homebrew inside the container image.
RUN set -exuo pipefail \
	&& arch="$(dpkg --print-architecture)" \
	&& case "$arch" in \
		amd64) release_arch='linux_amd64' ;; \
		arm64) release_arch='linux_arm64' ;; \
		*) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
	   esac \
	&& tmpdir="$(mktemp -d)" \
	&& cd "$tmpdir" \
	&& gog_asset="gogcli_${GOGCLI_VERSION}_${release_arch}.tar.gz" \
	&& curl -fsSLO "https://github.com/openclaw/gogcli/releases/download/v${GOGCLI_VERSION}/${gog_asset}" \
	&& curl -fsSLO "https://github.com/openclaw/gogcli/releases/download/v${GOGCLI_VERSION}/checksums.txt" \
	&& grep "  ${gog_asset}$" checksums.txt | sha256sum -c - \
	&& tar -xzf "$gog_asset" gog \
	&& install -m 0755 gog /usr/local/bin/gog \
	&& rm -f "$gog_asset" checksums.txt gog \
	&& wacli_asset="wacli_${WACLI_VERSION}_${release_arch}.tar.gz" \
	&& curl -fsSLO "https://github.com/openclaw/wacli/releases/download/v${WACLI_VERSION}/${wacli_asset}" \
	&& curl -fsSLO "https://github.com/openclaw/wacli/releases/download/v${WACLI_VERSION}/checksums.txt" \
	&& grep "  ${wacli_asset}$" checksums.txt | sha256sum -c - \
	&& tar -xzf "$wacli_asset" wacli \
	&& install -m 0755 wacli /usr/local/bin/wacli \
	&& cd / \
	&& rm -rf "$tmpdir"

# Corepack needs a shared home so the non-root node user can resolve pnpm
# without a first-run network fetch failing on permissions.
# We prepare pnpm here as root so the binary is cached before switching users.
ENV COREPACK_HOME=/usr/local/share/corepack
RUN set -exuo pipefail \
	&& install -d -m 0755 "${COREPACK_HOME}" \
	&& corepack enable \
	&& corepack prepare pnpm@latest --activate \
	&& chmod -R a+rwX "$COREPACK_HOME"

# Pre-create the non-root pnpm directories while still root so later global
# installs do not depend on BuildKit cache-mount ownership behavior.
RUN set -exuo pipefail \
	&& install -d -o node -g node -m 0775 \
		/home/node/.local/bin \
		/home/node/.local/share/pnpm \
		/home/node/.local/share/pnpm/store \
		/home/node/.local/share/pnpm/global

RUN chown -R node:node /home/node
USER node
ENV HOME="/home/node"
WORKDIR "${HOME}"

# From this point, we specify ENV and write to .bashrc.
# This way the exec call to openclaw has the values, and they are set when grabbing a shell.

# Enable standard aliases and create blank space before other tools edit bashrc.
ENV PATH="${HOME}/.local/bin:${PATH}"
RUN set -exuo pipefail \
	&& sed 's/^#alias/alias/g' -i ${HOME}/.bashrc \
	&& mkdir -p ${HOME}/.local/bin \
	&& echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> ${HOME}/.bashrc \
	&& echo '' >> ${HOME}/.bashrc

# Install go tools
ENV GOROOT="/usr/local/src/go"
ENV GOPATH="${HOME}/go"
ENV GOBIN="${GOPATH}/bin"
ENV PATH="${GOBIN}:${PATH}"
RUN set -exuo pipefail \
	&& echo 'export GOROOT="/usr/local/src/go"' >> ${HOME}/.bashrc \
	&& echo 'export GOPATH="${HOME}/go"' >> ${HOME}/.bashrc \
	&& echo 'export GOBIN="${GOPATH}/bin"' >> ${HOME}/.bashrc \
	&& echo 'export PATH="${GOBIN}:${PATH}"' >> ${HOME}/.bashrc \
	&& source ${HOME}/.bashrc \
	&& go install golang.org/x/tools/cmd/goimports@latest \
	&& go install golang.org/x/tools/gopls@latest \
	&& go install github.com/steipete/songsee/cmd/songsee@latest \
	&& go install github.com/steipete/gifgrep/cmd/gifgrep@latest \
	&& go install github.com/steipete/goplaces/cmd/goplaces@latest

# Install Node.js based tools
## QMD: Run this if it's the first time starting the container
# qmd collection add docs --name openclaw-docs
# qmd embed
ENV NODE_LLAMA_CPP_CMAKE_OPTION_GGML_CUDA=OFF
ENV NODE_LLAMA_CPP_CMAKE_OPTION_GGML_HIP=OFF
ENV NODE_LLAMA_CPP_CMAKE_OPTION_GGML_VULKAN=OFF
ENV NODE_LLAMA_CPP_GPU="false"
RUN set -exuo pipefail \
	&& pnpm config set package-import-method copy \
	&& pnpm config set global-bin-dir ${HOME}/.local/bin \
	&& pnpm install -g --child-concurrency=1 --allow-build=better-sqlite3 --allow-build=node-llama-cpp @tobilu/qmd \
	&& pnpm install -g --child-concurrency=1 --allow-build=protobufjs @steipete/summarize \
	&& pnpm install -g --child-concurrency=1 clawhub \
	&& pnpm install -g --child-concurrency=1 @google/gemini-cli

# Install Python tools
RUN set -exuo pipefail \
	&& pipx install "git+https://github.com/truenas/api_client.git@TS-25.10.3" \
	&& pipx install openai-whisper

# Clone openclaw
ARG OPENCLAW_TAG="2026.5.4"
RUN set -exuo pipefail \
	&& git clone --branch "v${OPENCLAW_TAG}" --depth 1 \
		https://github.com/openclaw/openclaw

WORKDIR ${HOME}/openclaw

ENV NODE_ENV=production
ENV OPENCLAW_PREFER_PNPM=1
RUN --mount=type=cache,id=docker-openclaw-pnpm-store,target=/home/node/.local/share/pnpm/store,sharing=locked,uid=1000,gid=1000,mode=0775 \
	set -exuo pipefail \
	&& export NODE_OPTIONS='--max-old-space-size=2048' \
	&& pnpm install --frozen-lockfile \
	&& (pnpm canvas:a2ui:bundle \
		|| (echo "A2UI bundle: creating stub (non-fatal)" \
			&& mkdir -p src/canvas-host/a2ui \
			&& echo "/* A2UI bundle unavailable */" > src/canvas-host/a2ui/a2ui.bundle.js \
			&& echo "stub" > src/canvas-host/a2ui/.bundle.hash \
			&& rm -rf vendor/a2ui apps/shared/OpenClawKit/Tools/CanvasA2UI)) \
	&& pnpm build:docker \
	&& pnpm ui:build \
	&& pnpm postinstall \
	&& ln -sf ${HOME}/openclaw/openclaw.mjs ${HOME}/.local/bin/openclaw \
	&& echo 'export PATH="${HOME}/openclaw/node_modules/.bin:${PATH}"' >> ${HOME}/.bashrc \
	&& echo '' >> ${HOME}/.bashrc
ENV PATH="${HOME}/openclaw/node_modules/.bin:${PATH}"

# Strip dev dependencies and build artifacts to match upstream runtime layout.
# Whitelist approach: keep only what runtime needs, delete everything else.
RUN --mount=type=cache,id=docker-openclaw-pnpm-store,target=/home/node/.local/share/pnpm/store,sharing=locked,uid=1000,gid=1000,mode=0775 \
	set -exuo pipefail \
	&& CI=true NPM_CONFIG_FROZEN_LOCKFILE=false pnpm prune --prod \
	&& find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete \
	&& chmod 750 openclaw.mjs \
	&& rm -rf docs/ja-JP docs/zh-CN \
	&& find . -maxdepth 1 -mindepth 1 \
		! -name 'dist' \
		! -name 'docs' \
		! -name 'extensions' \
		! -name 'node_modules' \
		! -name 'skills' \
		! -name 'openclaw.mjs' \
		! -name 'package.json' \
		-exec rm -rf {} +

HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
	CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

LABEL \
	org.opencontainers.image.source="https://github.com/openclaw/openclaw" \
	org.opencontainers.image.url="https://openclaw.ai" \
	org.opencontainers.image.documentation="https://docs.openclaw.ai/install/docker" \
	org.opencontainers.image.licenses="MIT" \
	org.opencontainers.image.title="OpenClaw (custom)" \
	org.opencontainers.image.description="Custom OpenClaw runtime with extra tooling"

EXPOSE 18789
EXPOSE 9222 5900 6080

CMD ["/usr/local/bin/node", "/home/node/openclaw/openclaw.mjs", "gateway"]
