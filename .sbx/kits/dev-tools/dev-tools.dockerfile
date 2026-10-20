# syntax=docker/dockerfile:1
# The content recipe of the dev-tools kit (dev-tools.yaml). Everything is staged under /out and lands on the workload as-is.
# The build context is this folder, so tools.toml is the only file the build can read.
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

# The SPIRE agent (node attestation of the VM), the version of the SPIRE server in the spire chart (platform/addons/spire/spire.yaml, chart 0.30.3 pins
# 1.15.3). The musl build is static. The checksum is the one published with the release (spire-1.15.3-linux-amd64-musl_sha256sum.txt). amd64 only.
ARG SPIRE_VERSION=1.15.3
ARG SPIRE_SHA256=ca1a4d1155317bdd2afc7f36663828a10410c7c840e54725b90b4064b0a301c7
RUN curl -fsSL -o /tmp/spire.tgz "https://github.com/spiffe/spire/releases/download/v${SPIRE_VERSION}/spire-${SPIRE_VERSION}-linux-amd64-musl.tar.gz" \
 && echo "${SPIRE_SHA256}  /tmp/spire.tgz" | sha256sum -c - \
 && tar -xzf /tmp/spire.tgz -C /tmp "spire-${SPIRE_VERSION}/bin/spire-agent" \
 && install -D -m 0755 "/tmp/spire-${SPIRE_VERSION}/bin/spire-agent" /out/usr/local/bin/spire-agent \
 && rm -rf /tmp/spire.tgz "/tmp/spire-${SPIRE_VERSION}"

# The bash completions come from a task in tools.toml.
RUN mise run sandbox:completions

# What those completions call: kubectl, helm and flux fail with "_get_comp_words_by_ref: command not found" without it. The
# compat file defines that name and _init_completion (bash-completion 2.12+ renamed them). The shell image has no bash-completion.
RUN mkdir -p /out/usr/share/bash-completion /out/etc/bash_completion.d \
 && cp -a /usr/share/bash-completion/bash_completion /usr/share/bash-completion/helpers /out/usr/share/bash-completion/ \
 && cp -a /etc/bash_completion.d/000_bash_completion_compat.bash /out/etc/bash_completion.d/

# The file is also the VM's system config, so the shims resolve from any directory.
COPY tools.toml /out/etc/mise/conf.d/sandbox.toml
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
