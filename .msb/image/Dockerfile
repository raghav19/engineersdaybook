# syntax=docker/dockerfile:1
# The image of the msb sandbox: Debian, mise, and exactly the tools in tools.toml. The VM boots from this image, so it is a full
# root file system (the sbx kit was a layer on top of the sbx shell kit). VS Code Remote-SSH needs a glibc image (not Alpine) with tar and libstdc++.
FROM debian:trixie-slim
ARG MISE_VERSION=v2026.10.0

# Set once, read by mise and its tasks. mise sits in /usr/local/bin because the shims it makes link to that path.
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    COMPLETIONS_DIR=/home/agent/.local/share/bash-completion/completions

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates git xz-utils bzip2 bash-completion tar gzip libstdc++6 procps less openssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && ldconfig

# The agent user: uid 1000, as in the sbx shell kit. mise installs as agent, so the shims and new tools belong to it.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && mkdir -p /opt/mise /home/agent/.cache/terraform-providers \
 && chown -R agent:agent /opt/mise /home/agent

# mise, then exactly the tools in tools.toml, which is copied in as it is: it is the system config of mise.
RUN curl -fsSL https://mise.run | MISE_VERSION=$MISE_VERSION sh
COPY tools.toml /etc/mise/conf.d/sandbox.toml
USER agent
RUN mise install --yes

# Remove spire-server: the VM runs only the agent.
RUN rm -f /opt/mise/installs/github-spiffe-spire/*/bin/spire-server

# The bash completions come from a task in tools.toml. bash loads a file of ~/.local/share/bash-completion/completions when you first complete its command, so no rc file is needed.
RUN mise run sandbox:completions

USER root
COPY spire-agent.conf /etc/spire/agent.conf
COPY sandbox-boot /usr/local/bin/sandbox-boot
# Git for every user: any directory is safe (the clone belongs to agent, the mount to root), and GitHub over HTTPS takes the token from GITHUB_TOKEN,
# which holds only a placeholder. The host swaps it for the real token on the wire.
RUN git config --system --add safe.directory '*' \
 && git config --system credential.https://github.com.helper '!f() { echo username=x-access-token; echo "password=$GITHUB_TOKEN"; }; f'
# Debian's /etc/profile resets PATH for login shells (bash -l, the VS Code terminal, ssh), which drops the shims from the ENV below.
RUN printf '%s\n' 'case ":$PATH:" in *:/opt/mise/shims:*) ;; *) PATH=/opt/mise/shims:$PATH ;; esac' 'export PATH' 'export EDITOR="code --wait"' > /etc/profile.d/mise-shims.sh \
 && chmod 0755 /usr/local/bin/sandbox-boot

# The tools are the mise shims. The workspace paths for mise (MISE_TRUSTED_CONFIG_PATHS, MISE_IGNORED_CONFIG_PATHS) come from sandbox.yaml.
ENV PATH=/opt/mise/shims:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8
