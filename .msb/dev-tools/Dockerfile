# syntax=docker/dockerfile:1
# The image of the msb sandbox. It has Debian, mise and exactly the tools in tools/. The VM boots from this image,
# so the image is a full root file system. (The sbx kit was a layer on top of the sbx shell kit.)
# The mise tools need an image with glibc (not Alpine).
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
# The same step removes the headers of node (include/, 61 MB). Only a build of a native module needs them. The npm tools of the image have no native build.
# No other stage may install node: a node with its headers would put them back in the final image. So lsp.toml has no node.
RUN mise install --yes && rm -rf /opt/mise/installs/node/*/include

# This stage starts from runtimes, so the venv of Headroom is built on the python of runtimes.toml (UV_PYTHON in headroom.toml is its path).
# The final stage copies only pypi-headroom-ai and uv from this stage, so the image has one python and one node.
FROM runtimes AS headroom
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

FROM base AS agents
COPY tools/agents.toml /etc/mise/conf.d/agents.toml
RUN mise install --yes

FROM base AS lsp
COPY tools/lsp.toml /etc/mise/conf.d/lsp.toml
RUN mise install --yes

# The editor is TTT (https://github.com/eugenioenko/ttt), and tools/dev.toml installs the binary through the mise github backend.
# The binary carries its own themes and grammars, so it needs no build stage of its own. To add one theme or one grammar later,
# drop its JSON in a folder here and COPY it to ~/.config/ttt/themes/ or ~/.config/ttt/grammars/. No upstream clone is needed.

FROM base AS final
COPY --from=runtimes --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=headroom --chown=agent:agent /opt/mise/installs/pypi-headroom-ai /opt/mise/installs/pypi-headroom-ai
COPY --from=headroom --chown=agent:agent /opt/mise/installs/uv /opt/mise/installs/uv
COPY --from=infra --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=dev --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=agents --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=lsp --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY tools/ /etc/mise/conf.d/
# mise makes the shims from the tools that it finds. A task in mise.toml makes the bash completions. Bash loads a file from
# ~/.local/share/bash-completion/completions when you first complete its command. No rc file is necessary.
RUN mise reshim && mise run sandbox:completions

# Proof at build time that the editor runs in this image. It prints the version and exits before it opens a screen.
# The shims are not on PATH here yet: the ENV at the bottom of this file adds them, after every step above.
RUN PATH=/opt/mise/shims:$PATH ttt --version

USER root
COPY spire-agent.conf /etc/spire/agent.conf
COPY sandbox-boot /usr/local/bin/sandbox-boot
# TTT and its configuration. The binary is a mise tool (tools/dev.toml), so it needs no COPY of its own.
# ttt-settings.json is the one place that says which language server starts for which language. TTT reads it from
# ~/.config/ttt, the directory that TTT_CONFIG_DIR names in mise.toml. agent owns it, because TTT rewrites files in it.
COPY --chown=agent:agent ttt-settings.json /home/agent/.config/ttt/settings.json
# The Just grammar. TTT compiles in 125 grammars and Just is not one of them, so without this file a justfile gets no
# highlighting and just-lsp never starts. NOTICE travels with it, because the grammar is MIT. See ttt-grammars/NOTICE.
COPY --chown=agent:agent ttt-grammars/just.tmLanguage.json /home/agent/.config/ttt/grammars/just.tmLanguage.json
COPY --chown=agent:agent ttt-grammars/NOTICE /home/agent/.config/ttt/grammars/NOTICE
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
# The settings of Qwen Code: one provider (the Token Plan, international, Singapore), and the MCP servers (draw.io, Flux schema catalog, GitHub). Root owns the file. The agent cannot change it, and project settings cannot override it. The key is the placeholder QWEN_API_KEY. The host swaps it on the network, so the file has no secret.
# This is the system scope of Qwen Code. It wins over the user scope (~/.qwen/settings.json) and the project scope, and root owns the folder, so the agent cannot replace the file.
# Qwen Code makes ~/.qwen itself, as agent, for the state that it writes (extensions, logs, history).
# The mkdir is necessary, as above: COPY --chmod also sets the mode of a folder that it creates, and 0644 has no execute bit, so the agent could not open a file in it.
RUN mkdir -p /etc/qwen-code && chmod 0755 /etc/qwen-code
COPY --chmod=0644 qwen-settings.json /etc/qwen-code/settings.json
# Git settings for every user. Git treats each directory as safe, because agent owns the clone and root owns the mount.
# GitHub over HTTPS takes the token from GH_TOKEN. GH_TOKEN holds only a placeholder. The host replaces it with the token on the network.
RUN git config --system --add safe.directory '*' \
 && git config --system credential.https://github.com.helper '!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'
# The /etc/profile of Debian resets PATH for login shells (bash -l, the TTT terminal and ssh). This removes the shims that the ENV below adds.
RUN printf '%s\n' 'case ":$PATH:" in *:/opt/mise/shims:*) ;; *) PATH=/opt/mise/shims:$PATH ;; esac' 'export PATH' 'export EDITOR=nano' > /etc/profile.d/mise-shims.sh \
 && chmod 0755 /usr/local/bin/sandbox-boot

# The tools are the mise shims. sandbox.yaml sets the workspace paths for mise (MISE_TRUSTED_CONFIG_PATHS and MISE_IGNORED_CONFIG_PATHS).
ENV PATH=/opt/mise/shims:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8
