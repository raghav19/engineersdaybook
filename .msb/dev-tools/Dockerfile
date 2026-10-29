# syntax=docker/dockerfile:1
# The image of the msb sandbox. It has Debian, mise and exactly the tools in tools/. The VM boots from this image,
# so the image is a full root file system. (The sbx kit was a layer on top of the sbx shell kit.)
# The Lapce proxy and the mise tools need an image with glibc (not Alpine). The install script of the proxy needs tar, gzip and curl.
FROM debian:trixie-slim AS base
ARG MISE_VERSION=v2026.10.0

# The ENV lines set these values one time. mise and its tasks read them. mise is in /usr/local/bin, because the shims that it makes link to that path.
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    COMPLETIONS_DIR=/home/agent/.local/share/bash-completion/completions

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates git xz-utils bzip2 bash-completion tar gzip libstdc++6 procps less openssh-client nano \
      podman podman-docker uidmap passt fuse-overlayfs \
 && rm -rf /var/lib/apt/lists/* \
 && ldconfig

# The agent user has uid 1000, as in the sbx shell kit. mise installs as agent, so agent owns the shims and the new tools.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && mkdir -p /opt/mise /home/agent/.cache/terraform-providers \
 && chown -R agent:agent /opt/mise /home/agent

# Install mise. mise.toml (the settings) is the system config of mise in every stage below.
RUN curl -fsSL https://mise.run | MISE_VERSION=$MISE_VERSION sh
COPY mise.toml /etc/mise/conf.d/mise.toml
USER agent

# One stage for each file of tools/. BuildKit builds the stages at the same time. A new version in one file rebuilds only its stage,
# so the other stages come from the cache. The last stage puts the results together.
FROM base AS runtimes
COPY tools/runtimes.toml /etc/mise/conf.d/runtimes.toml
RUN mise install --yes

FROM base AS headroom
COPY tools/headroom.toml /etc/mise/conf.d/headroom.toml
# The uv cache (about 880 MiB) is a download cache of the install. The tools do not read it, so the same step removes it from the layer.
RUN mise install --yes && rm -rf /home/agent/.cache/uv

FROM base AS infra
COPY tools/infra.toml /etc/mise/conf.d/infra.toml
# The same step removes spire-server. The VM runs only the agent.
RUN mise install --yes && rm -f /opt/mise/installs/github-spiffe-spire/*/bin/spire-server

FROM base AS dev
COPY tools/dev.toml /etc/mise/conf.d/dev.toml
RUN mise install --yes

FROM base AS claude
COPY tools/claude.toml /etc/mise/conf.d/claude.toml
RUN mise install --yes

FROM base AS lsp
COPY tools/lsp.toml /etc/mise/conf.d/lsp.toml
RUN mise install --yes

# The proxy of Lapce, the part of the editor that runs in the VM. Lapce on the host runs `~/.local/share/lapce-stable/proxy/lapce --version`.
# If the answer is not `Lapce-proxy <its own version>`, Lapce downloads and uploads the proxy again at each connection. So this version must be the
# version of Lapce on the host. LAPCE_VERSION and the checksum change together. The checksum is the digest of the asset in the GitHub release.
FROM base AS lapce-proxy
ARG LAPCE_VERSION=v0.4.6
ARG LAPCE_PROXY_SHA256=90248f443f9434fd4d442435ada1f44002f5c82640509078e78829d9cc85036f
RUN mkdir -p /home/agent/.local/share/lapce-stable/proxy \
 && curl -fsSL -o /tmp/lapce-proxy.gz "https://github.com/lapce/lapce/releases/download/${LAPCE_VERSION}/lapce-proxy-linux-x86_64.gz" \
 && echo "${LAPCE_PROXY_SHA256}  /tmp/lapce-proxy.gz" | sha256sum -c - \
 && gunzip -c /tmp/lapce-proxy.gz > /home/agent/.local/share/lapce-stable/proxy/lapce \
 && chmod 0755 /home/agent/.local/share/lapce-stable/proxy/lapce

# Lapce has no setting for a language server. A volt (a plugin: a folder with volt.toml and a WASM file) starts each one. One WASM module starts every server.
# It reads the [server] table of the volt.toml next to it. This stage builds the module. It is throwaway: the image keeps the wasm file and no Rust.
FROM rust:1.99-slim-trixie AS lapce-wasm
RUN rustup target add wasm32-wasip1
WORKDIR /src
COPY lapce-lsp/Cargo.toml lapce-lsp/Cargo.lock ./
COPY lapce-lsp/src src
RUN cargo build --release --locked --target wasm32-wasip1

# One volt for each table of lapce-lsp/servers.toml. yq (the version of the dev stage) writes the volt.toml of the volt: the name, the activation, and the table itself as [server].
FROM base AS lapce-volts
COPY --from=dev /opt/mise/installs/yq/latest/yq /usr/local/bin/yq
COPY --from=lapce-wasm /src/target/wasm32-wasip1/release/lapce-lsp-launcher.wasm /tmp/lapce-lsp-launcher.wasm
COPY lapce-lsp/servers.toml /tmp/servers.toml
RUN <<'EOF'
set -euo pipefail
cd /tmp
names=$(yq -p toml -oy 'keys | .[]' servers.toml)
[ -n "$names" ]
for name in $names; do
  mkdir -p "out/$name"
  cp lapce-lsp-launcher.wasm "out/$name/"
  NAME=$name yq -p toml -o toml '{
    "name": "lsp-" + strenv(NAME),
    "version": "0.1.0",
    "author": "sandbox",
    "display-name": strenv(NAME),
    "description": "Starts the " + strenv(NAME) + " language server from the image of the sandbox.",
    "wasm": "lapce-lsp-launcher.wasm",
    "activation": {"language": ([.[strenv(NAME)].language] | map(select(. != null))), "workspace-contains": .[strenv(NAME)].patterns},
    "server": .[strenv(NAME)]
  }' servers.toml > "out/$name/volt.toml"
done
EOF

FROM base AS final
COPY --from=runtimes --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=headroom --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=headroom --chown=agent:agent /opt/mise/uv-python /opt/mise/uv-python
COPY --from=infra --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=dev --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=claude --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=lsp --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=lapce-proxy --chown=agent:agent /home/agent/.local/share/lapce-stable/proxy /home/agent/.local/share/lapce-stable/proxy
COPY --from=lapce-volts --chown=agent:agent /tmp/out /home/agent/.local/share/lapce-stable/plugins
COPY tools/ /etc/mise/conf.d/
# mise makes the shims from the tools that it finds. A task in mise.toml makes the bash completions. Bash loads a file from
# ~/.local/share/bash-completion/completions when you first complete its command. No rc file is necessary.
RUN mise reshim && mise run sandbox:completions

USER root
COPY spire-agent.conf /etc/spire/agent.conf
COPY sandbox-boot /usr/local/bin/sandbox-boot
# Lapce sends no language id for Terraform files, and terraform-ls then gives no hover, completion or symbols. The volt of terraform-ls starts the server through this script.
COPY --chmod=0755 lsp-langid /usr/local/bin/lsp-langid
# The proxy is also the command `lapce <folder>`. In the terminal of Lapce it opens the folder in the Lapce window that is connected to this VM.
RUN ln -s /home/agent/.local/share/lapce-stable/proxy/lapce /usr/local/bin/lapce
# Podman, for the container builds of a developer. It runs rootless, as agent. `docker` is the podman-docker script, and nodocker removes its notice.
# containers.conf puts the trust store of the VM in each container. It has the msb CA. So HTTPS to the allowed hosts works in a build step.
COPY containers.conf /etc/containers/containers.conf.d/10-sandbox.conf
RUN touch /etc/containers/nodocker
# The policy of Claude Code. Root owns the file. The agent cannot change it, and project settings and user settings cannot override it.
# It has the MCP servers and the deny list for the GitHub tools. $MSB_GH_TOKEN is the placeholder that msb puts in GH_TOKEN.
# The host replaces the placeholder with the token on the network, so the file has no secret.
# The deny list stops mistakes. The agent can still call the GitHub API with the placeholder. The scope of the token is the real limit.
RUN mkdir -p /etc/claude-code && chmod 0755 /etc/claude-code
COPY --chmod=0644 managed-settings.json /etc/claude-code/managed-settings.json
# Git settings for every user. Git treats each directory as safe, because agent owns the clone and root owns the mount.
# GitHub over HTTPS takes the token from GH_TOKEN. GH_TOKEN holds only a placeholder. The host replaces it with the token on the network.
RUN git config --system --add safe.directory '*' \
 && git config --system credential.https://github.com.helper '!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'
# The /etc/profile of Debian resets PATH for login shells (bash -l, the Lapce terminal and ssh). This removes the shims that the ENV below adds.
RUN printf '%s\n' 'case ":$PATH:" in *:/opt/mise/shims:*) ;; *) PATH=/opt/mise/shims:$PATH ;; esac' 'export PATH' 'export EDITOR=nano' > /etc/profile.d/mise-shims.sh \
 && chmod 0755 /usr/local/bin/sandbox-boot

# The tools are the mise shims. sandbox.yaml sets the workspace paths for mise (MISE_TRUSTED_CONFIG_PATHS and MISE_IGNORED_CONFIG_PATHS).
ENV PATH=/opt/mise/shims:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8
