# syntax=docker/dockerfile:1
# The content recipe of the dev-tools kit (dev-tools.yaml). Everything is staged under /out and lands on the workload as-is.
# The build context is this folder. The build reads tools.toml (the tools) and spire-agent.conf (the config of the SPIRE agent).
FROM dhi.io/debian-base:trixie-dev AS build
ARG MISE_VERSION=v2026.10.0

# Set once, read by mise and the tasks. mise sits in /usr/local/bin because the shims it makes link to that path.
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    COMPLETIONS_DIR=/out/opt/sandbox/completions

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git xz-utils bzip2 bash-completion \
 && rm -rf /var/lib/apt/lists/*

# mise, then exactly the tools in tools.toml, which is copied in as it is: it is mise's system config.
RUN curl -fsSL https://mise.run | MISE_VERSION=$MISE_VERSION sh
COPY tools.toml /etc/mise/conf.d/sandbox.toml
RUN mise install --yes

# The SPIRE release holds the agent and the server. The VM runs only the agent, so the 167 MB server binary goes before the copy to /out.
RUN rm -f /opt/mise/installs/github-spiffe-spire/*/bin/spire-server

# The bash completions come from a task in tools.toml.
RUN mise run sandbox:completions

# What those completions call: kubectl, helm and flux fail with "_get_comp_words_by_ref: command not found" without it. The
# compat file defines that name and _init_completion (bash-completion 2.12+ renamed them). The shell image has no bash-completion.
RUN mkdir -p /out/usr/share/bash-completion /out/etc/bash_completion.d \
 && cp -a /usr/share/bash-completion/bash_completion /usr/share/bash-completion/helpers /out/usr/share/bash-completion/ \
 && cp -a /etc/bash_completion.d/000_bash_completion_compat.bash /out/etc/bash_completion.d/

# The file is also the VM's system config, so the shims resolve from any directory.
COPY tools.toml /out/etc/mise/conf.d/sandbox.toml
COPY spire-agent.conf /out/etc/spire/agent.conf
RUN mkdir -p /out/usr/local/bin && cp -a /opt/mise /out/opt/mise && cp /usr/local/bin/mise /out/usr/local/bin/mise \
 && chown -R 0:0 /out && chown -R 1000:1000 /out/opt/mise  # 1000 is agent in the shell kit: mise installs new tools as agent

FROM scratch
COPY --from=build /out /
ARG WORKSPACE
# The tools are the mise shims. MISE_TRUSTED_CONFIG_PATHS trusts the clone's nested mise.toml files, which nothing else would.
# MISE_IGNORED_CONFIG_PATHS skips the clone's root mise.toml, which lists host-only tools (kind, sbx) that are not installed here.
ENV PATH=/opt/mise/shims \
    LANG=C.UTF-8 \
    MISE_DATA_DIR=/opt/mise \
    MISE_TRUSTED_CONFIG_PATHS=$WORKSPACE \
    MISE_IGNORED_CONFIG_PATHS=$WORKSPACE/mise.toml
