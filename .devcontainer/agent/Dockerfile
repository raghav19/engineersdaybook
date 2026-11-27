# syntax=docker/dockerfile:1
# The agent image of the sandbox. Build and push: ../README.md#update-the-agent-image

FROM debian:trixie-slim AS stage1-base
ARG MISE_INSTALLER_URL=https://mise.run

ENV MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    COMPLETIONS_DIR=/home/agent/.local/share/bash-completion/completions

# No podman: the agent builds with docker buildx through the builder and pushes with crane.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates git xz-utils bzip2 bash-completion tar gzip libstdc++6 procps less openssh-client nano \
 && rm -rf /var/lib/apt/lists/* \
 && ldconfig

RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && mkdir -p /opt/mise /home/agent/.cache/terraform-providers \
 && chown -R agent:agent /opt/mise /home/agent

RUN curl -fsSL $MISE_INSTALLER_URL | sh
USER agent


FROM stage1-base AS stage2-runtimes
COPY tools/runtimes.toml /etc/mise/conf.d/runtimes.toml
RUN mise install --yes && rm -rf /opt/mise/installs/node/*/include

FROM stage1-base AS stage4-infra
COPY tools/infra.toml /etc/mise/conf.d/infra.toml
# Keeps only the docker client of the docker-cli bundle. The agent has no daemon: it sends each build to the builder over buildkitd.sock.
RUN mise install --yes \
 && find /opt/mise/installs/docker-cli -path '*/docker/*' -type f ! -name docker -delete

FROM stage1-base AS stage5-dev
COPY tools/dev.toml /etc/mise/conf.d/dev.toml
RUN mise install --yes

FROM stage1-base AS stage6-agents
COPY tools/agents.toml /etc/mise/conf.d/agents.toml
RUN mise install --yes

FROM stage1-base AS stage7-lsp
COPY tools/lsp.toml /etc/mise/conf.d/lsp.toml
# Removes TypeScript from vscode-langservers-extracted. The JSON server, the only one that Fresh uses, runs without it.
RUN mise install --yes \
 && rm -rf /opt/mise/installs/npm-vscode-langservers-extracted/*/node_modules/.mise/typescript@*

FROM stage1-base AS stage9-token-economizer
ARG TE_REPO=https://github.com/microsoft/TokenEconomizer.git
RUN git clone $TE_REPO /home/agent/token-economizer \
 && rm -rf /home/agent/token-economizer/.git /home/agent/token-economizer/tests /home/agent/token-economizer/experiments /home/agent/token-economizer/docs /home/agent/token-economizer/.github /home/agent/token-economizer/README.md /home/agent/token-economizer/SECURITY.md /home/agent/token-economizer/CLAUDE.md /home/agent/token-economizer/.gitattributes /home/agent/token-economizer/.gitignore

# Plugins at pinned versions. A stage of its own, so a bump of a tool does not fetch them again.
FROM stage1-base AS stage8-plugins
COPY tools/agents.toml /etc/mise/conf.d/agents.toml
COPY --from=stage6-agents /opt/mise/installs /opt/mise/installs
COPY --from=stage9-token-economizer /home/agent/token-economizer /home/agent/token-economizer
ENV PATH=/opt/mise/shims:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mise reshim

# The token usage plugin of Herdr: a commit after v0.5.0.
RUN herdr plugin install --yes --ref 7f2689bb0880c72fe7465a1dbd44519fb5cb4476 pseudovar/herdr-plugin-token-usage

# The review pane plugin of Herdr: v0.9.0.
RUN herdr plugin install --yes --ref 0b5781997e9b3d833b17463c0824113cba4bfbd0 persiyanov/herdr-reviewr

# Fresh packages. ADD fetches only the folder after the colon, without .git.
# The target folder depends on the kind: plugins/, languages/ or themes/, then packages/<name>.
# fresh-plugins: todo-highlighter 1.0.0, color-highlighter 1.0.0, catppuccin 1.0.0.
ADD --chown=agent:agent https://github.com/sinelaw/fresh-plugins.git#3f327361b8b64e6e192386e5badda9d22241c854:todo-highlighter /home/agent/.config/fresh/plugins/packages/todo-highlighter
ADD --chown=agent:agent https://github.com/sinelaw/fresh-plugins.git#3f327361b8b64e6e192386e5badda9d22241c854:color-highlighter /home/agent/.config/fresh/plugins/packages/color-highlighter
ADD --chown=agent:agent https://github.com/sinelaw/fresh-plugins.git#3f327361b8b64e6e192386e5badda9d22241c854:themes/catppuccin /home/agent/.config/fresh/themes/packages/catppuccin
# dotfiles-fresh-language 1.0.0.
ADD --chown=agent:agent https://github.com/2fd/dotfiles-fresh-language.git#2b8c0e58721001dba0b7f9bf7608ee8b52e04261 /home/agent/.config/fresh/languages/packages/dotfiles-fresh-language

# Claude Code plugins: ponytail v5.3.2 and TokenEconomizer from stage9.
# Must equal CLAUDE_CONFIG_DIR in ../compose.yaml, so the paths in installed_plugins.json stay valid.
ENV CLAUDE_CONFIG_DIR=/home/agent/.claude
# Keeps only ~/.claude/plugins. managed-settings.json enables the plugins. The rest of ~/.claude is the state of the agent.
RUN claude plugin marketplace add DietrichGebert/ponytail#v5.3.2 && claude plugin install ponytail@ponytail \
 && claude plugin marketplace add /home/agent/token-economizer && claude plugin install tokeneconomizer@tokeneconomizer \
 && find "$CLAUDE_CONFIG_DIR" -mindepth 1 -maxdepth 1 ! -name plugins -exec rm -rf {} +

FROM stage1-base AS stage10-final
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends binutils \
 && rm -rf /var/lib/apt/lists/*
USER agent
COPY --from=stage2-runtimes --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage4-infra --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage5-dev --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage6-agents --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY --from=stage7-lsp --chown=agent:agent /opt/mise/installs /opt/mise/installs
COPY tools/ /etc/mise/conf.d/
RUN mise reshim

# The plugins from stage8. The config links of ../lifecycle/on-create.sh replace a file from stage8 that has the same path.
COPY --from=stage8-plugins --chown=agent:agent /home/agent/.config/fresh /home/agent/.config/fresh
COPY --from=stage8-plugins --chown=agent:agent /home/agent/.config/herdr /home/agent/.config/herdr
COPY --from=stage8-plugins --chown=agent:agent /home/agent/.local/state/herdr /home/agent/.local/state/herdr
COPY --from=stage8-plugins --chown=agent:agent /home/agent/.claude /home/agent/.claude

COPY --from=stage9-token-economizer --chown=agent:agent /home/agent/token-economizer /home/agent/token-economizer
RUN mkdir -p /home/agent/.tokeneconomizer /home/agent/.qwen

USER root
# The home is a volume at run time, so the image keeps its home files as a skeleton. ../lifecycle/on-create.sh copies them into the volume.
RUN mkdir -p /usr/share/sandbox \
 && mv /home/agent /usr/share/sandbox/home \
 && mkdir /home/agent \
 && chown agent:agent /home/agent

# Build-time env only. The run-time env and the command are in ../compose.yaml.
ENV PATH=/opt/mise/shims:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8
