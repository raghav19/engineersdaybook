# syntax=docker/dockerfile:1

FROM debian:trixie-slim AS stage1-base
ARG MISE_VERSION=v2026.10.0

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

RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && mkdir -p /opt/mise /home/agent/.cache/terraform-providers \
 && chown -R agent:agent /opt/mise /home/agent

RUN curl -fsSL https://mise.run | MISE_VERSION=$MISE_VERSION sh
COPY mise.toml /etc/mise/conf.d/mise.toml
USER agent


FROM stage1-base AS stage2-runtimes
COPY tools/runtimes.toml /etc/mise/conf.d/runtimes.toml
RUN mise install --yes && rm -rf /opt/mise/installs/node/*/include

# 
FROM stage2-runtimes AS stage3-headroom
COPY tools/headroom.toml /etc/mise/conf.d/headroom.toml
# The uv cache (about 880 MiB) is a download cache of the install. The tools do not read it, so the same step removes it from the layer.
RUN mise install --yes && rm -rf /home/agent/.cache/uv

FROM stage1-base AS stage4-infra
COPY tools/infra.toml /etc/mise/conf.d/infra.toml
# The same step removes spire-server. The VM runs only the agent.
RUN mise install --yes && rm -f /opt/mise/installs/github-spiffe-spire/*/bin/spire-server

FROM stage1-base AS stage5-dev
COPY tools/dev.toml /etc/mise/conf.d/dev.toml
RUN mise install --yes

FROM stage1-base AS stage6-agents
COPY tools/agents.toml /etc/mise/conf.d/agents.toml
RUN mise install --yes

FROM stage1-base AS stage7-lsp
COPY tools/lsp.toml /etc/mise/conf.d/lsp.toml
RUN mise install --yes

FROM stage1-base AS stage8-ttt-plugins
USER root
ARG TTT_PLUGINS_REF=2722887bdbd6080e1a8970fcdf4cb958b2089484
RUN set -eu; \
    url="https://raw.githubusercontent.com/eugenioenko/ttt-plugins/${TTT_PLUGINS_REF}"; \
    mkdir -p /plugins/markdown-preview /plugins/lang-just/syntaxes; \
    curl -fsSL -o /plugins/markdown-preview/plugin.lua      "$url/markdown-preview/plugin.lua"; \
    curl -fsSL -o /plugins/markdown-preview/plugin.ttt.json "$url/markdown-preview/plugin.ttt.json"; \
    curl -fsSL -o /plugins/lang-just/plugin.ttt.json        "$url/lang-just/plugin.ttt.json"; \
    curl -fsSL -o /plugins/lang-just/syntaxes/just.tmLanguage.json "$url/lang-just/syntaxes/just.tmLanguage.json"

FROM stage1-base AS stage9-final
COPY --from=stage2-runtimes --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage3-headroom --chown=agent:agent /opt/mise/installs/pypi-headroom-ai /opt/mise/installs/pypi-headroom-ai
COPY --from=stage3-headroom --chown=agent:agent /opt/mise/installs/uv /opt/mise/installs/uv
COPY --from=stage4-infra --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage5-dev --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage6-agents --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage7-lsp --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY tools/ /etc/mise/conf.d/
# mise makes the shims from the tools that it finds. A task in mise.toml makes the bash completions. Bash loads a file from
# ~/.local/share/bash-completion/completions when you first complete its command. No rc file is necessary.
RUN mise reshim && mise run sandbox:completions

# Proof at build time that the editor runs in this image. It prints the version and exits before it opens a screen.
# The shims are not on PATH here yet: the ENV at the bottom of this file adds them, after every step above.
RUN PATH=/opt/mise/shims:$PATH ttt --version

USER root
COPY configs/spire/spire-agent.conf /etc/spire/agent.conf
COPY sandbox-boot /usr/local/bin/sandbox-boot

COPY --chown=agent:agent configs/editor/ttt-settings.json /home/agent/.config/ttt/settings.json
COPY --from=stage8-ttt-plugins --chown=agent:agent /plugins/markdown-preview/ /home/agent/.config/ttt/plugins/markdown-preview/
COPY --from=stage8-ttt-plugins --chown=agent:agent /plugins/lang-just/ /home/agent/.config/ttt/plugins/lang-just/
COPY --chown=agent:agent configs/editor/ttt-plugins.json /home/agent/.config/ttt/plugins.ttt.json

# containers.conf puts the trust store of the VM in each container. It has the msb CA. So HTTPS to the allowed hosts works in a build step.
COPY configs/containers/containers.conf /etc/containers/containers.conf.d/10-sandbox.conf
RUN touch /etc/containers/nodocker

# claude code settings
RUN mkdir -p /etc/claude-code && chmod 0755 /etc/claude-code
COPY --chmod=0644 configs/agents/managed-settings.json /etc/claude-code/managed-settings.json

# qwen settings
RUN mkdir -p /etc/qwen-code && chmod 0755 /etc/qwen-code
COPY --chmod=0644 configs/agents/qwen-settings.json /etc/qwen-code/settings.json

# git settings
RUN git config --system --add safe.directory '*' \
 && git config --system credential.https://github.com.helper '!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'
# The /etc/profile of Debian resets PATH for login shells (bash -l, the TTT terminal and ssh). This removes the shims that the ENV below adds.
RUN printf '%s\n' 'case ":$PATH:" in *:/opt/mise/shims:*) ;; *) PATH=/opt/mise/shims:$PATH ;; esac' 'export PATH' 'export EDITOR=nano' > /etc/profile.d/mise-shims.sh \
 && chmod 0755 /usr/local/bin/sandbox-boot

ENV PATH=/opt/mise/shims:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8
