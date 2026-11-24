# syntax=docker/dockerfile:1

FROM debian:trixie-slim AS stage1-base
ARG MISE_INSTALLER_URL=https://mise.run

ENV MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    COMPLETIONS_DIR=/home/agent/.local/share/bash-completion/completions

# The image has no podman. The sandbox builds with docker and buildx in the builder and pushes with crane.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates git xz-utils bzip2 bash-completion tar gzip libstdc++6 procps less openssh-client nano \
 && rm -rf /var/lib/apt/lists/* \
 && ldconfig

RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && mkdir -p /opt/mise /home/agent/.cache/terraform-providers \
 && chown -R agent:agent /opt/mise /home/agent

RUN curl -fsSL $MISE_INSTALLER_URL | sh
COPY mise.toml /etc/mise/conf.d/mise.toml
USER agent


FROM stage1-base AS stage2-runtimes
COPY tools/runtimes.toml /etc/mise/conf.d/runtimes.toml
RUN mise install --yes && rm -rf /opt/mise/installs/node/*/include

# 
FROM stage2-runtimes AS stage3-headroom
COPY tools/headroom.toml /etc/mise/conf.d/headroom.toml
# The uv cache is a download cache. Tools do not read it, so this line removes it from the layer.
RUN mise install --yes && rm -rf /home/agent/.cache/uv

FROM stage1-base AS stage4-infra
COPY tools/infra.toml /etc/mise/conf.d/infra.toml
RUN mise install --yes

FROM stage1-base AS stage5-dev
COPY tools/dev.toml /etc/mise/conf.d/dev.toml
RUN mise install --yes

FROM stage1-base AS stage6-agents
COPY tools/agents.toml /etc/mise/conf.d/agents.toml
RUN mise install --yes

FROM stage1-base AS stage7-lsp
COPY tools/lsp.toml /etc/mise/conf.d/lsp.toml
RUN mise install --yes

FROM stage1-base AS stage9-token-economizer
ARG TE_REPO=https://github.com/microsoft/TokenEconomizer.git
RUN git clone $TE_REPO /home/agent/token-economizer \
 && rm -rf /home/agent/token-economizer/.git /home/agent/token-economizer/tests /home/agent/token-economizer/experiments /home/agent/token-economizer/docs /home/agent/token-economizer/.github /home/agent/token-economizer/README.md /home/agent/token-economizer/SECURITY.md /home/agent/token-economizer/CLAUDE.md /home/agent/token-economizer/.gitattributes /home/agent/token-economizer/.gitignore

FROM stage1-base AS stage10-final
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends binutils socat \
 && rm -rf /var/lib/apt/lists/*
USER agent
COPY --from=stage2-runtimes --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage3-headroom --chown=agent:agent /opt/mise/installs/pypi-headroom-ai /opt/mise/installs/pypi-headroom-ai
COPY --from=stage3-headroom --chown=agent:agent /opt/mise/installs/uv /opt/mise/installs/uv
COPY --from=stage4-infra --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage5-dev --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage6-agents --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage7-lsp --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY tools/ /etc/mise/conf.d/
# mise creates shims from the installed tools. A mise task writes the bash completions.
RUN mise reshim && mise run sandbox:completions && rm -rf /tmp/mise-cache

USER root
# The config of docker is read-only at run time. It has the placeholder login of ghcr.io, the proxy settings of the build steps and the definition of the builder.
# docker finds the plugin buildx through cliPluginsExtraDirs. crane reads the login from this file. The placeholder must equal the proxy_value line of agent/proxy/iron-proxy.yaml. It is not a secret.
# buildx create only writes the definition. It does not connect. The endpoint is the socket that the sandbox mounts.
COPY --chmod=0644 configs/tools/docker-config.json /etc/docker/config.json
RUN mkdir -p /etc/docker/buildx/activity /etc/docker/buildx/refs \
 && PATH=/opt/mise/shims:$PATH DOCKER_CONFIG=/etc/docker BUILDKIT_HOST=unix:///run/sandbox/buildkit/buildkitd.sock docker buildx create --name sandbox \
 && chmod -R a+rX /etc/docker
USER agent

# Agent-level configs.
COPY --chown=agent:agent configs/editor/fresh-config.json /home/agent/.config/fresh/config.json
# The mise task fresh:plugins runs fresh-plugins.sh. The script reads fresh-plugins.yaml with yq and fetches each package at its pinned commit.
COPY --chown=agent:agent configs/editor/fresh-plugins.yaml /home/agent/.config/fresh/fresh-plugins.yaml
COPY --chmod=0755 configs/editor/fresh-plugins.sh /usr/local/share/sandbox/fresh-plugins.sh
RUN mise run fresh:plugins
COPY --chown=agent:agent configs/tools/herdr-config.toml /home/agent/.config/herdr/config.toml
COPY --chown=agent:agent configs/tools/k9s-config.yaml /home/agent/.config/k9s/config.yaml
COPY --chown=agent:agent configs/tools/k9s-skin-catppuccin-mocha.yaml /home/agent/.config/k9s/skins/catppuccin-mocha.yaml
COPY --chown=agent:agent configs/tools/k9s-skin-tokyo-night.yaml /home/agent/.config/k9s/skins/tokyo-night.yaml
COPY --from=stage9-token-economizer --chown=agent:agent /home/agent/token-economizer /home/agent/token-economizer
COPY --chown=agent:agent configs/tools/gitconfig /home/agent/.gitconfig
RUN mkdir -p /home/agent/.tokeneconomizer /home/agent/.qwen

# Root-only: the start script, managed settings.
USER root
COPY --chmod=0755 sandbox-start /usr/local/bin/sandbox-start
# The image has no command. sandbox-agent.container sets the command, starts the relay and runs sandbox-start.
# The config of otelcol, and the report of `mise run otel:report`.
COPY --chmod=0644 configs/tools/otelcol-config.yaml /etc/otelcol/config.yaml
COPY --chmod=0644 configs/tools/otel-report.jq /usr/local/share/sandbox/otel-report.jq

# At run time the root file system is read-only and /home/agent is a tmpfs. Keep what the image put in /home/agent
# as a skeleton. sandbox-start copies it into the tmpfs at each start.
RUN mkdir -p /usr/share/sandbox \
 && mv /home/agent /usr/share/sandbox/home \
 && mkdir /home/agent \
 && chown agent:agent /home/agent

RUN mkdir -p /etc/claude-code && chmod 0755 /etc/claude-code
COPY --chmod=0644 configs/agents/managed-settings.json /etc/claude-code/managed-settings.json

RUN mkdir -p /etc/qwen-code && chmod 0755 /etc/qwen-code
COPY --chmod=0644 configs/agents/qwen-settings.json /etc/qwen-code/settings.json

RUN echo 'eval "$(mise activate bash)"' >> /etc/bash.bashrc

ENV PATH=/opt/mise/shims:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    EDITOR=fresh \
    TMPDIR=/tmp
