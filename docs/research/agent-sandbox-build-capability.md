# Build capability in agent sandboxes

Question: Sources on agent sandboxing cover isolation, network control and credentials. They seem silent on builds. What do primary sources say about code builds (compile, install packages, run tests) and container image builds (`docker build`) inside the agent sandbox? What is the best practice? Is "no build in the sandbox" the common answer? How do the sources get images built when the agent changes code?

Research date: 2026-11-18. Local repo state: branch `research-agent-build-capability`, based on `main` at `b4c9525`.

Versions read (all primary sources):

- Anthropic `sandbox-runtime` tag `v0.0.83` (commit `0bbebed`, released 2026-11-13). The repo is `anthropic-experimental/sandbox-runtime`.
- `kubernetes-sigs/agent-sandbox` tag `v1.0.11` (released 2026-11-12), `main` at `820a382`.
- microsandbox tag `v0.7.16` (released 2026-11-18), `main` at `ba93645`. The `docs/` folder is the source of the doc claims.
- BuildKit tag `v0.35.0` (commit `f55949d`, local clone). Buildx tag `v0.39.0`. Buildah tag `v1.46.1` (commit `2560f60`). Podman tag `v6.2.0` (commit `055de04`).
- gVisor `master` (`b29c832`) for the Docker tutorial, and tag `release-20261116.0`.
- Kaniko tag `v1.24.0` (released 2025-05-23). `main` at `236ba56` (2025-06-03) is the last commit. The README says the project is archived.
- OpenHands `main` at `309f23f` (tag `v1.41.0`). Firecracker tag `v1.18.0`. Kata Containers tag `4.4.0`. Sysbox tag `v0.7.1`.
- E2B: CLI `2.24.0`, infra tag `2026.30`. Daytona tag `v0.190.0`. SWE-agent tag `v1.1.0`.
- SLSA specification `v1.2` (status "Approved").
- Documentation pages have no version. These are Claude Code docs, AWS docs, Docker docs, E2B docs, Modal docs, Daytona docs and Fly.io docs. I read each page on 2026-11-18.

Evidence tags:

- **[doc]**: an official documentation page, README or first-party blog. A URL is given.
- **[src]**: source code at the version above. File and line are given.
- **[advisory]**: a security advisory of the project.
- **[repo]**: a file in this repo, or an earlier note of this repo. File and line are given.
- **[inference]**: my own conclusion from the sources. No source says it.
- **UNVERIFIED**: I did not find a source, or I could not read the page.

I ran no build and no sandbox. Every statement about behavior comes from reading pages and files. I read the pages in full unless I say that a page was truncated.

## Answer

1. **Build capability is almost never a topic.** The Anthropic blog [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude) is silent on builds. AWS agent sandbox pages are silent on `docker build`. Builds appear only in product pages. [doc]
2. **Code builds and package installs are normal in a sandbox.** Anthropic, AWS, Daytona and microsandbox all let the agent install packages and run tests. All of them control the network for these steps with a host allowlist. [doc]
3. **AWS adds a stronger rule for package installs.** The AWS DevOps Agent docs say to pre-install packages and not to allow registries at runtime. Anthropic lets you allow the registries. [doc]
4. **Image builds split the sources into two groups.** Sandboxes for coding agents give a private Docker daemon in a microVM (Docker Sandboxes, microsandbox, Daytona, Modal VM runtime, Anthropic cloud sessions). Hosted agent platforms build images outside the agent session (AgentCore, GKE Agent Sandbox, Modal, E2B, Fly.io). [doc]
5. **"No image build in the sandbox" is the answer of the platform sources, not of every source.** The Anthropic Bash sandbox cannot run `docker`. It cannot run rootless Podman or Buildah. The docs tell you to run them unsandboxed with full access, or to use a VM. [doc]
6. **No source describes a separate disposable builder for an untrusted agent.** The sources cover remote BuildKit (pattern D) in general. None of them covers an agent that holds the builder socket. BuildKit and Kaniko say they do not make untrusted builds safe by themselves. [doc] [inference]
7. **Best practice, by case.** Code builds: build in the sandbox and allow only the registries you need. Image builds: build the image that ships in a trusted CI that signs it. Use a microVM with its own daemon, or a separate builder, only for the inner loop. The first rule has source support. The second rule is [inference].
8. **Your design is a pattern D builder.** It is stricter on network and secrets than any source I read. It lacks authorization, provenance, signing and a multi-platform build. See "Comparison with this repo's design".

## What the sources say

### Anthropic

- **Engineering blog.** [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude) (2026-05-25). Silent on builds. The headings are "Three types of risk, three components of defense", "Patterns for containing agents", "Trusting what the agent reads", "Looking ahead" and "Summary". It says that Claude on claude.ai runs code in a gVisor container. It says to treat an allowed domain as a grant of capability. It says developers "already run npm install from untrusted sources several times a week". [doc]
- **Sandboxing docs.** [Sandboxing](https://code.claude.com/docs/en/sandboxing). A build or a test suite runs in the Bash sandbox. A tool that must write elsewhere gets `sandbox.filesystem.allowWrite`. A tool that needs a host gets `allowedDomains`. `npm`, `curl` and `git` over HTTPS work once the host is allowed. [doc]
- **Docker in the Bash sandbox.** The page says "`docker` is incompatible with the sandbox". The fix is an `excludedCommands` pattern such as `docker compose *`. An excluded command "runs with your full access". [doc]
- **A Makefile does not match.** Claude Code matches the text of the call. A script or `make` target that calls `docker` inside does not match the pattern. So an unchanged Makefile that runs `docker build` stays sandboxed and fails. [doc]
- **Rootless Podman and Buildah.** User namespaces are off by default. Rootless Podman fails with `cannot clone: Operation not permitted`. The fix is `excludedCommands` such as `podman *`. The setting `allowNestedUserNamespaces` "isn't enough for rootless Podman or Buildah". It also "turns off a security boundary". [doc]
- **`sandbox-runtime` source.** The README lists `allowNestedUserNamespaces` for "rootless podman or buildah" ([README.md line 592](https://github.com/anthropic-experimental/sandbox-runtime/blob/v0.0.83/README.md)). It says that allowing `/var/run/docker.sock` "would effectively grant access to the host system" (line 1329). It says that `enableWeakerNestedSandbox` "considerably weakens security" (line 1332). [src]
- **Environments page.** [Choose a sandbox environment](https://code.claude.com/docs/en/sandbox-environments) names Docker Sandboxes for a VM. It says the VM option has "its own Docker daemon". It says dev containers need Docker. It gives no build advice. [doc]
- **Dev container docs.** [Development containers](https://code.claude.com/docs/en/devcontainer). Build tools run inside the container. The page covers an egress firewall and non-root users. It is silent on image builds. The reference container adds `NET_ADMIN` and `NET_RAW`. [doc]
- **Cloud sessions.** [Cloud environments](https://code.claude.com/docs/en/cloud-environments). The VM has `docker`, `dockerd` and `docker compose` (section "Installed tools"). A setup script runs as root and can run `docker compose build`. The cache keeps the images (section "Docker"). Replacing the base image "isn't supported yet". [doc]
- **Cloud session network.** A new environment starts at "Limited" access with "Allow package managers" on. The default allowlist covers npm, PyPI, crates.io, Go and Docker Hub hosts (section "Default allowed domains"). "None" network access makes installs fail. [doc]
- **GitHub Action.** [Claude Code GitHub Actions](https://code.claude.com/docs/en/github-actions). Claude pushes commits and opens pull requests. CI workflows then run. The troubleshooting section says commits that use the default `GITHUB_TOKEN` do not start workflows. [doc]
- **Secure deployment guide.** [Securely deploying AI agents](https://code.claude.com/docs/en/agent-sdk/secure-deployment). It gives the hardened container, gVisor and Firecracker options, and the proxy pattern for credentials. It is silent on builds. It lists `.npmrc` and `~/.docker/config.json` as files that expose tokens. [doc]
- **Network page.** [Enterprise network configuration](https://code.claude.com/docs/en/network-config). Silent on builds. `registry.npmjs.org` is needed to install Claude Code itself. [doc]

### AWS

- **AgentCore Code Interpreter.** Pages read: [overview](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-tool.html), [getting started](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-getting-started.html) and [resource and session management](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-resource-session-management.html). Silent on `docker` and image builds. The agent can run shell commands. The network mode is "Sandbox" or "Public" (VPC appears on the overview). [doc]
- **AgentCore Runtime.** [microVMs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-how-it-works.html). Each session runs "in a dedicated microVM". The deploy steps say "Build and push a container image to Amazon ECR directly or via the AgentCore SDK". The build is outside the agent session. [doc]
- **Lambda MicroVMs blog.** [Secure code execution for AI agents with AWS Lambda MicroVMs](https://aws.amazon.com/blogs/compute/secure-code-execution-for-ai-agents-with-aws-lambda-microvms/). Agents install packages, run shell commands, execute "build toolchains" and run tests. Network access is public or VPC-only. The post says that "VPC-only connectivity is usually sufficient because deployment goes through the gateway". Promotion to production "should go through the CI/CD pipeline". It is silent on image builds. [doc]
- **DevOps Agent sandbox.** [Set up a Sandbox](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-integrations-and-knowledge-sandbox.html). The sandbox runs in a Lambda MicroVM. An empty allowlist reaches AWS endpoints only. The page says "Pre-install packages instead of allowlisting registries". It sets limits of 50 `pip` packages and 50 `npm` packages. [doc]
- **Domain control blog.** [Control which domains your AI agents can access](https://aws.amazon.com/blogs/machine-learning/control-which-domains-your-ai-agents-can-access/). To install with `pip`, allow `.pypi.org` and `.pythonhosted.org`. The page is silent on `npm` and on image builds. I read it up to the point where it truncated. [doc]
- **CodeBuild and ECR.** [Publish Docker image to an Amazon ECR image repository](https://docs.aws.amazon.com/codebuild/latest/userguide/sample-docker.html). A `buildspec.yml` runs `docker build` and `docker push`. This shows the "build outside the agent" pattern. It makes no claim about agents. [doc]
- **Firecracker.** [design.md](https://github.com/firecracker-microvm/firecracker/blob/v1.18.0/docs/design.md). Silent on builds. It says Firecracker can "safely run workloads from different customers on the same machine". [doc]

### Docker

- **Docker Sandboxes.** [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/), [architecture](https://docs.docker.com/ai/sandboxes/architecture/) and [security](https://docs.docker.com/ai/sandboxes/security/). The primary trust boundary is the microVM. "Each sandbox has its own Docker Engine with no path to the host daemon". The agent has full privileges inside, including `sudo`. Images "built or pulled by the agent" stay in the sandbox. [doc]
- **What Docker Sandboxes does not state.** No page says "`docker build` works". The architecture page only implies it. The landing page is silent on builds. [doc] [inference]
- **Docker Sandboxes network and credentials.** Outbound TCP is deny-by-default. "The default allowed domains include broad wildcards". A host proxy swaps a sentinel value for the real key. In direct mode the agent can change Git hooks and build scripts on the host. [doc]
- **Buildx remote driver.** [Remote driver](https://docs.docker.com/build/builders/drivers/remote/). It connects Buildx to an externally managed BuildKit. Endpoints are `tcp://`, `unix://`, `docker-container://` and `kube-pod://`. TCP without TLS "allows unauthenticated access". [doc]
- **BuildKit.** README line 741 says "Enabling TCP without mTLS is dangerous because the executor containers (aka Dockerfile `RUN` containers) can call BuildKit API as well" ([README.md](https://github.com/moby/buildkit/blob/v0.35.0/README.md)). `PROJECT.md` says that a build can use untrusted sources (line 147). It says that "Multiple concurrent builds from separate client share their build resources without namespacing" (line 167, [PROJECT.md](https://github.com/moby/buildkit/blob/v0.35.0/PROJECT.md)). [src]
- **BuildKit rootless mode.** Rootless mode "is always set to `network.host`" ([docs/rootless.md line 9](https://github.com/moby/buildkit/blob/v0.35.0/docs/rootless.md)). `--oci-worker-no-process-sandbox` "is discouraged" (line 101). Entitlements are "disabled by default" ([docs/buildkitd.toml.md line 19](https://github.com/moby/buildkit/blob/v0.35.0/docs/buildkitd.toml.md)). [src]
- **BuildKit advisories.** The earlier note [remote-buildkit-for-agent-sandbox.md](remote-buildkit-for-agent-sandbox.md) lists the advisories of 2026. The cache-poisoning advisory says to use "isolated BuildKit daemons or ephemeral builders for untrusted image sources". I did not read the advisories again. [repo] [advisory]
- **BuildKit maintainer answer.** In [discussion 5796](https://github.com/moby/buildkit/discussions/5796), a collaborator says that a privileged container still runs `buildkitd` as an unprivileged process. He says that VM runtimes such as Kata can run BuildKit, with a cost for nested virtualization. He gives no advice on authorization. [doc]

### Google and gVisor

- **Agent Sandbox project.** [README.md](https://github.com/kubernetes-sigs/agent-sandbox/blob/main/README.md) at `820a382`. The project delegates isolation to gVisor or Kata through `RuntimeClass`. The README is silent on image builds and on `docker`. The example uses an existing image. [doc]
- **GKE Agent Sandbox.** [Agent Sandbox on GKE](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox). The sandbox template pulls a prebuilt image. The page is silent on builds and package installs. The default policy "allows egress to the public internet" and blocks private ranges and the metadata server. [doc]
- **gVisor and Docker.** [docker-in-gvisor.md](https://github.com/google/gvisor/blob/master/g3doc/user_guide/tutorials/docker-in-gvisor.md). "All basic docker commands should function as expected". Docker needs `--net-raw` (line 39). Docker v28 and later need `--allow-packet-socket-write` (line 16). Docker v29 needs a `tmpfs` at `/var/lib/docker` (lines 17 and 76). The tutorial runs `docker build -t whalesay .` inside a gVisor container (line 125). [src]
- **Kaniko.** [README.md](https://github.com/GoogleContainerTools/kaniko/blob/v1.24.0/README.md). Line 1: "This project is archived and no longer developed or maintained". Last commit `236ba56` is from 2025-06-03. The security section says kaniko "does not make it safe to run untrusted builds inside your cluster, or anywhere else" (line 1189). It "relies on the security features of your container runtime" (line 1192). [src]
- **Cloud Build.** [Build container images](https://docs.cloud.google.com/build/docs/building/build-containers). Cloud Build runs the `docker` builder and stores the image in Artifact Registry. The page does not describe how it isolates builds. It does not mention Kaniko or BuildKit. [doc]

### microsandbox

- **Docker in a sandbox.** [docker-in-sandbox.mdx](https://github.com/microsandbox/microsandbox/blob/main/docs/how-to/docker/docker-in-sandbox.mdx). The guide starts `dockerd` in the microVM. It is "useful for sandboxed builds, agent workflows that need their own Docker daemon" (line 8). A flat ext4 root disk avoids overlay on overlay (line 56). [doc]
- **Compose tests.** [compose-tests.mdx line 8](https://github.com/microsandbox/microsandbox/blob/main/docs/how-to/ci-cd/compose-tests.mdx). The inner daemon "never receives the host's `/var/run/docker.sock`". [doc]
- **Local images.** [local-images.mdx](https://github.com/microsandbox/microsandbox/blob/main/docs/how-to/docker/local-images.mdx). microsandbox cannot read the Docker image store. You build with `docker build` on the host, then run `docker save ... | msb load`. This is pattern D in a small form. [doc]
- **Network.** Sandboxes reach the public internet by default. Private networks, the host and cloud metadata are blocked ([networking/overview.mdx line 12](https://github.com/microsandbox/microsandbox/blob/main/docs/networking/overview.mdx)). The docs warn against routing the Docker socket into a sandbox ([host-sockets.mdx line 95](https://github.com/microsandbox/microsandbox/blob/main/docs/networking/host-sockets.mdx)). [doc]

### E2B

- **Templates.** [How it works](https://docs.e2b.dev/template/how-it-works). The build creates a container from the definition, extracts the file system, runs the layer commands and snapshots the sandbox. The page does not say where the build runs. It does not say how the build is isolated. [doc]
- **Template quickstart.** [Quickstart](https://docs.e2b.dev/template/quickstart). "The template build environment is a full sandbox environment". It allows "running Docker containers as part of the setup". A build runs up to 1 hour. [doc]
- **Build System 2.0.** [Introducing Build System 2.0](https://e2b.dev/blog/introducing-build-system-2-0). Templates are code. The build "runs automatically when you execute your template". The post is silent on trust and isolation of the build. [doc]
- **Network.** [Internet access](https://docs.e2b.dev/sandbox/internet-access). Outbound access is on by default. `allowOut` and `denyOut` take domains. The page is silent on package registries. [doc]
- **Infra source.** I cloned no E2B infra source. I did not read the builder code. UNVERIFIED.

### Modal

- **Sandboxes.** [Sandboxes](https://modal.com/docs/guide/sandboxes). "Use the VM runtime to run Docker in a Sandbox". The example runs `dockerd` as the entrypoint. The image with Docker was "built and published ahead of time". The page says to prefer named images so that Modal never builds them when a Sandbox starts. Nested virtualization needs the Enterprise plan. [doc]
- **Images.** [Images](https://modal.com/docs/guide/images). "Image builders run atop Modal's gVisor runtime". The guide gives `uv_pip_install`, `apt_install` and `run_commands` for the build. Builds cache by layer. The page is silent on `docker build` in a Sandbox. [doc]
- **CI builds.** The Sandboxes page says to call `Image.build` in a deployment flow, in a scheduled job or in CI. [doc]

### Daytona

- **Snapshots.** [Snapshots](https://www.daytona.io/docs/en/snapshots/). A snapshot starts from an image or a Dockerfile. "Daytona will build the snapshot for you". The page does not say where the build runs. "Sandboxes can run Docker containers inside them (Docker-in-Docker)". Dockerfile builds are not supported for VM snapshots. [doc]
- **Network.** [Network limits](https://www.daytona.io/docs/en/network-limits/). Tier 1 and 2 are restricted. "Essential services" stay reachable. The list covers package registries and Docker registries. Tier 3 and 4 have full access. A custom allowlist replaces the essential services. [doc]

### Others

- **Buildah and Podman.** Buildah tutorial 5 builds rootless inside an OpenShift container. The container needs extra capabilities `cap_kill`, `cap_setgid` and `cap_setuid` ([tutorial 05, line 134](https://github.com/containers/buildah/blob/v1.46.1/docs/tutorials/05-openshift-rootless-build.md)). `buildah build --isolation` has the types `oci`, `rootless` and `chroot` ([buildah-build.1.md line 568](https://github.com/containers/buildah/blob/v1.46.1/docs/buildah-build.1.md)). [src]
- **OpenHands.** [Runtime architecture](https://docs.openhands.dev/openhands/usage/architecture/runtime). "OpenHands builds a new Docker image" from the base image. The backend starts the sandbox container. The page does not say which process runs the build. It does not say if `docker.sock` enters the sandbox. UNVERIFIED for both. The repo at `309f23f` is now a front end. I did not find the runtime builder in it. [doc]
- **Fly.io.** [fly deploy](https://docs.fly.io/flyctl/deploy). Builds run on a remote builder "instead of using the local docker daemon". This "is the default". `--image` deploys an existing image. [doc]
- **SLSA.** [Build requirements v1.2](https://slsa.dev/spec/v1.2/build-requirements). "The build platform is responsible for generating provenance". It is also "responsible for isolating between builds, even within the same tenant project". The producer "MUST select a build platform that is capable of reaching their desired SLSA Build Level". [doc]
- **Silent.** Sysbox [security.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md) (a Docker-inside example, no `docker build`). Kata Containers [README.md](https://github.com/kata-containers/kata-containers/blob/main/README.md). SWE-agent [installation tips](https://swe-agent.com/latest/installation/tips/) (no word on images or networks). [doc]
- **Not read.** Dagger: the pages `docs.dagger.io/reference/configuration/engine` and `.../custom-runner` returned 404. Sigstore and Cosign: I did not read them. A search summary says that the Dagger Engine needs privileged mode. I did not rely on it. UNVERIFIED.

## The patterns A to E

### A. No image build in the agent sandbox. CI builds, tests, signs and pushes.

- **Who uses it.**
  - AWS AgentCore Runtime: build and push to ECR, then create the runtime. [doc]
  - AWS Lambda MicroVMs blog: promotion "should go through the CI/CD pipeline". [doc]
  - Claude Code GitHub Action: Claude pushes commits and CI runs. [doc]
  - Modal: build named images in a deployment flow or in CI. [doc]
  - Fly.io: remote builder is the default. [doc]
  - SLSA: the build platform makes provenance and isolates builds. [doc]
- **Trust boundary.** The pull request and the CI platform. The agent holds no builder and no push token. [inference]
- **What an injected agent can do.** It edits the Dockerfile and the CI files in its branch. The sources do not say who reviews workflow changes. UNVERIFIED. It cannot sign or push the image. [inference]
- **Cost for a developer.** No local feedback on image builds. Each try needs a push and a CI run. An unchanged Makefile or Dockerfile works in CI.

### B. A microVM with its own container daemon

- **Who uses it.**
  - Docker Sandboxes (microVM with its own Docker Engine). [doc]
  - microsandbox (`dockerd` in the microVM). [doc]
  - Daytona (Docker-in-Docker in the sandbox). [doc]
  - Modal (VM runtime). [doc]
  - Anthropic cloud sessions (a VM with `dockerd`). [doc]
  - The Anthropic environments page points to Docker Sandboxes. [doc]
- **Trust boundary.** The guest kernel and the hypervisor. [doc]
- **What an injected agent can do.** It has root in the VM. It runs any `RUN` step. It reaches every host that the egress policy allows. In direct mode it edits host files such as Git hooks. [doc]
- **Cost for a developer.** An unchanged Dockerfile, Makefile and `docker compose` work. Docker Sandboxes pays "a VM plus its own daemon". microsandbox needs a flat ext4 root disk. Modal nested virtualization needs the Enterprise plan. [doc]

### C. Rootless build inside the sandbox

- **Who shows it.**
  - gVisor documents Docker, and a `docker build`, inside gVisor with flags. [src]
  - Buildah documents a rootless build in an OpenShift container. [src]
  - BuildKit documents rootless mode. [src]
  - Kaniko is archived. [src]
  - Anthropic says its Bash sandbox blocks rootless Podman and Buildah. [doc]
- **Trust boundary.** User namespaces, or the gVisor sentry. The build and the agent share one sandbox. [inference]
- **What an injected agent can do.** It runs any `RUN` step beside its own tools. Kaniko "does not make it safe to run untrusted builds". BuildKit rootless mode uses `network.host`. [src]
- **Cost for a developer.** The sandbox needs extra capabilities and `newuidmap`. Storage needs `tmpfs` or ext4 in gVisor and in microVMs. The Anthropic Bash sandbox needs an unsandboxed exception. [src] [doc]

### D. A separate builder with a trust boundary

- **Who uses it.**
  - Buildx remote driver and an external BuildKit. [doc]
  - E2B template builds (the build runs in E2B infrastructure). [doc]
  - Modal `Image.build`. [doc]
  - Fly.io remote builder. [doc]
  - microsandbox: build with `docker build` on the host, then `msb load`. [doc]
  - CodeBuild and Cloud Build. [doc]
- **Trust boundary.** The builder host, its network and its credentials. BuildKit has no authorization. Its only controls are mTLS or socket permissions. [repo] [src]
- **What an injected agent can do.** It holds the client key, so it runs any `RUN` step on the builder. It can prune or poison a shared cache. The builder must be disposable and hold no secret. [advisory] [inference]
- **Cost for a developer.** Unchanged Dockerfiles work through `docker buildx` or `buildctl`. The context goes to the builder. The setup has more parts than pattern B. [doc]

### E. Pre-built images only

- **Who uses it.**
  - GKE Agent Sandbox: the template pulls a prebuilt image. [doc]
  - Modal: use named images that Modal never builds when a Sandbox starts. [doc]
  - Anthropic cloud sessions: "Replacing the base image entirely isn't supported yet". [doc]
  - AWS DevOps Agent: pre-install packages. [doc]
  - AgentCore Runtime: run an ECR image. [doc]
- **Trust boundary.** The registry and the image allowlist. [inference]
- **What an injected agent can do.** It cannot change the image. It can still pull from any allowed registry. The Anthropic default allowlist includes Docker Hub hosts. [doc]
- **Cost for a developer.** The agent cannot test a Dockerfile change. A person or CI must build every new image.

## Ranked recommendation

Order for each criterion. The first pattern is the best.

| Criterion | Order of patterns | Basis |
|---|---|---|
| Security for an untrusted agent | A and E, then D, then B, then C | [inference] |
| Developer experience | B, then D, then C, then A, then E | [inference] |
| Supply chain (provenance, signer) | A, then D, then B, then C, then E | [inference] from SLSA |
| Simplicity | E, then A, then B, then D, then C | [inference] |

The basis for the supply chain row: SLSA says a hosted build platform makes provenance and isolates builds. A build in a sandbox that the agent controls cannot meet that rule. E ranks last because it has no build step to rank. [doc] [inference]

Overall rank for image builds:

| Rank | Pattern | Reason |
|---|---|---|
| 1 | A | Best security and supply chain. Sources use it to ship. |
| 2 | D | Keeps an unchanged Dockerfile. Needs a disposable builder. |
| 3 | B | Best developer experience. The VM is the only boundary. |
| 4 | E | Simple and safe. The agent cannot build. |
| 5 | C | Weakest boundary. Kaniko is archived. |

Recommendation for code builds:

- Build in the sandbox. Allow only the registries and hosts that the build needs. Pre-install the packages when the set is small and fixed. [doc]
- Anthropic states the allowlist step. AWS DevOps Agent states the pre-install step. The choice between them is [inference]. Pre-install for a fixed set. Allowlist for a changing set.

Recommendation for image builds:

- Ship only images that a trusted CI built, scanned, signed and pushed. [inference] from SLSA, AgentCore and Modal.
- For the agent's inner loop, use pattern D with a disposable builder, or pattern B with a microVM. [inference]
- Do not use pattern C for an untrusted agent. Kaniko says it does not make untrusted builds safe. [doc]
- Sources state pattern B for local agent work (Anthropic environments page, Docker Sandboxes). Sources state pattern A for shipping (AgentCore, Modal, Lambda MicroVMs blog). No source states pattern D for an untrusted agent. [doc] [inference]

## Comparison with this repo's design

Files read: `.sandbox/README.md`, `.sandbox/docs/internals.md`, `.sandbox/proxy/iron-proxy-builder.yaml`, `.sandbox/builder/sandbox-builder.container`, `.sandbox/image/configs/tools/docker-config.json` and `docs/handoff/agent-sandbox-buildkit-builder.md`. I also read `.sandbox/proxy/iron-proxy.yaml` and `.sandbox/builder/Containerfile`. I did not edit them.

The design:

- A separate gVisor builder (`runsc-builder`) runs BuildKit. It has `Network=none`, user 1000, three capabilities and no secret. It is new for each sandbox session. [repo] (`sandbox-builder.container` lines 25 to 32 and 13)
- A builder proxy in `sni-only` mode with a host-name allowlist gives it egress. The proxy holds no token. [repo] (`iron-proxy-builder.yaml` lines 1 to 3 and 13 to 14)
- The agent sandbox runs `docker` with the Buildx remote driver. There is no daemon. The socket is in a read-only folder. [repo] (`README.md` lines 67 to 74 and 96)
- The agent sandbox pushes the tar with `crane` through the host proxy. The proxy swaps a placeholder for the real token. [repo] (`README.md` lines 72 to 74 and 95)

**Closest pattern: D**, with the trust boundary of pattern B.

- Like D, the builder is separate and the client holds only a socket.
- Like B, the builder is a sandbox of the same kind as the agent sandbox, and the agent has no capability.
- It is not C. The agent sandbox has no `newuidmap` and no user namespaces. [repo]
- It is not A or E. The agent builds images itself. [repo]

What it does better than the patterns in the sources:

- **No network device in the builder.** The sources give a builder either public egress (microsandbox, E2B, Modal) or a firewall allowlist. Your builder has only a proxy socket. [repo] [doc]
- **No credential in the builder.** The builder proxy holds no token. The builder cannot reach the host proxy. [repo] (`internals.md` line 199)
- **No registry login in the builder, and no push from the builder.** BuildKit sends credentials only from the client session. [repo] [src]
- **A fresh builder for each session.** BuildKit says that builds share resources "without namespacing". A fresh daemon avoids shared cache between sessions. [repo] [src] (`internals.md` line 176)
- **A health check that kills a bad builder.** No source shows this. [repo]
- **The agent never holds a push token.** Docker Sandboxes also uses a sentinel value. Your design adds a separate proxy for the builder. [repo] [doc]

What it lacks. I checked each item named in the task:

| Gap | Evidence | Rating |
|---|---|---|
| BuildKit socket has no authorization | `README.md` line 99: "BuildKit has no authorization". Only the mount limits access. | Open |
| `RUN` steps run as root in the builder | `README.md` line 100. Rootless BuildKit maps uid 1000 to root inside `RUN`. Network is `network.host` in rootless mode. | Open |
| Listed hosts can receive data | `README.md` line 142. `iron-proxy-builder.yaml` lists `github.com`, `*.githubusercontent.com` and `*.docker.com`. | Open |
| No provenance or signing | The files show a plain `crane push` of a tar. No file mentions attestation or `cosign`. | Open |
| One platform only | `README.md` line 86. | Open |
| No cache between sessions | `internals.md` lines 177 and 204: the cache is `tmpfs`. | Open |

Notes on each gap:

- **No authorization.** In pattern B the VM holds the agent too. In your design the agent and the builder are two containers. The agent holds the socket, so the agent can run any build step in the builder. The container is the wall. [repo]
- **Same subuid.** The builder and the agent share subuid 1000 (`internals.md` line 203). A gVisor escape from either reaches your host user. The README states this limit (line 139). [repo]
- **`sni-only` filters by name.** The Anthropic docs warn that a proxy that decides from the client-supplied host name allows "domain fronting or similar techniques". `sni-only` checks only the host name. [doc] [repo] (`iron-proxy-builder.yaml` line 2). The risk applies to the builder egress. I did not test it. UNVERIFIED.
- **Data goes out through listed hosts.** A hostile `RUN` step can send build context data to a listed host that accepts writes. I did not test this. [inference]
- **Push path is open.** `iron-proxy.yaml` swaps the placeholder for any request to host `ghcr.io` (lines 120 to 123). The file has no path rule. The earlier design had a path rule for `/v2/raghav19/sandbox-builds/**`. An injected agent can push to any package that the token allows. The token scope is not in the files. [repo] [inference]
- **No signature, no provenance.** The pushed image comes from an untrusted agent and an untrusted builder. A consumer cannot tell it from a trusted image. SLSA wants the build platform to make provenance that tenants cannot forge. [doc] [inference]
- **Untested paths.** The handoff of 2026-11-18 lists a `FROM` pull through the builder proxy and a push of the tar as not tested. Later commits can have tested them. I did not check. [repo] (`agent-sandbox-buildkit-builder.md`, "What was not tested")
- **A placeholder in a file.** `docker-config.json` holds a base64 placeholder login for `ghcr.io`. It decodes to a user name and a placeholder text, not a secret. [repo]

## What the sources do not say, and open questions

Gaps in the sources:

- No source states "no image build in the agent sandbox" as a rule. It is a pattern that I infer from AgentCore, Modal and E2B. [inference]
- No Anthropic page covers image builds for the sandboxed Bash tool, other than "`docker` is incompatible" and the `excludedCommands` fix.
- No source covers an untrusted agent that holds a BuildKit socket. The BuildKit threat model covers "untrusted sources" and bad daemons. It does not cover an authorized hostile client. [src]
- No source covers provenance or signing for images that an agent changed. SLSA covers the build platform only. [doc]
- E2B, Daytona and Modal pages do not say where their builds run or how they isolate them.
- Docker Sandboxes pages do not say "`docker build` works". They imply it.
- No source says how to limit what CI runs from an agent branch. GitHub docs were not in scope. UNVERIFIED.
- I read no Dagger page and no Sigstore page.

Open questions for the owner:

1. Do you want the agent to ship images, or only to test them? If it only tests, pattern E plus the builder can drop the `crane push` path.
2. Who signs a pushed image today? Should CI rebuild the image from the pull request and sign it, with the builder output used only for tests?
3. How wide is the `GITHUB_TOKEN` token behind `sandbox-placeholder-GHCR_PUSH_TOKEN`? Can it push to any package? Do you want a path rule in `iron-proxy.yaml`?
4. Is `github.com` plus `*.githubusercontent.com` needed in the builder allowlist? Can an earlier download step on the agent side replace it?
5. Does BuildKit `proxyNetwork` or a `RUN --network=none` default fit your `RUN` steps? Which `RUN` steps need the network at all?
6. Do you accept that the agent can run any build step in the builder? The handoff says the agent holds no capability, but it holds that power.
7. Should the builder and the agent use different subuids? What does the host user own that a gVisor escape reaches?
8. Do you need a second platform (for example `arm64`)? If yes, does BuildKit emulation in `runsc` work?
9. Do you want a cache between sessions? Cache poisoning is a known BuildKit risk, so a shared cache needs its own trust rule.
10. Which spike would test the `FROM` pull and the `crane push` through the proxies? The handoff lists both as untested.

## Sources

- https://www.anthropic.com/engineering/how-we-contain-claude
- https://code.claude.com/docs/en/sandboxing, `sandbox-environments`, `devcontainer`, `network-config`, `cloud-environments`, `claude-code-on-the-web`, `github-actions`, `agent-sdk/secure-deployment`
- https://github.com/anthropic-experimental/sandbox-runtime/blob/v0.0.83/README.md (lines 431, 522, 591, 592, 709, 715, 1329, 1332)
- https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/ (`code-interpreter-tool.html`, `code-interpreter-getting-started.html`, `code-interpreter-resource-session-management.html`, `runtime-how-it-works.html`)
- https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-integrations-and-knowledge-sandbox.html
- https://aws.amazon.com/blogs/compute/secure-code-execution-for-ai-agents-with-aws-lambda-microvms/
- https://aws.amazon.com/blogs/machine-learning/control-which-domains-your-ai-agents-can-access/
- https://docs.aws.amazon.com/codebuild/latest/userguide/sample-docker.html
- https://github.com/firecracker-microvm/firecracker/blob/v1.18.0/docs/design.md
- https://docs.docker.com/ai/sandboxes/ (`architecture/`, `security/`) and https://docs.docker.com/build/builders/drivers/remote/
- https://github.com/moby/buildkit/blob/v0.35.0/ (`README.md`, `PROJECT.md`, `docs/rootless.md`, `docs/buildkitd.toml.md`) and https://github.com/moby/buildkit/discussions/5796
- https://github.com/kubernetes-sigs/agent-sandbox/blob/main/README.md and https://docs.cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox
- https://github.com/google/gvisor/blob/master/g3doc/user_guide/tutorials/docker-in-gvisor.md
- https://github.com/GoogleContainerTools/kaniko/blob/v1.24.0/README.md (lines 1, 159 to 170, 1187 to 1204)
- https://docs.cloud.google.com/build/docs/building/build-containers
- https://github.com/microsandbox/microsandbox/tree/main/docs (`how-to/docker/docker-in-sandbox.mdx`, `how-to/docker/local-images.mdx`, `how-to/ci-cd/compose-tests.mdx`, `networking/overview.mdx`, `networking/host-sockets.mdx`, `security/isolation.mdx`)
- https://docs.e2b.dev/template/how-it-works, `template/quickstart`, `sandbox/internet-access` and https://e2b.dev/blog/introducing-build-system-2-0
- https://modal.com/docs/guide/sandboxes and https://modal.com/docs/guide/images
- https://www.daytona.io/docs/en/snapshots/ and `network-limits/`
- https://github.com/containers/buildah/blob/v1.46.1/docs/tutorials/05-openshift-rootless-build.md and `docs/buildah-build.1.md`
- https://docs.openhands.dev/openhands/usage/architecture/runtime
- https://docs.fly.io/flyctl/deploy
- https://slsa.dev/spec/v1.2/build-requirements
- https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md, https://github.com/kata-containers/kata-containers/blob/main/README.md, https://swe-agent.com/latest/installation/tips/ (silent)
- In this repo: `.sandbox/README.md`, `.sandbox/docs/internals.md`, `.sandbox/proxy/iron-proxy-builder.yaml`, `.sandbox/proxy/iron-proxy.yaml`, `.sandbox/builder/sandbox-builder.container`, `.sandbox/builder/Containerfile`, `.sandbox/image/configs/tools/docker-config.json`, `docs/handoff/agent-sandbox-buildkit-builder.md`, `docs/research/remote-buildkit-for-agent-sandbox.md`.
