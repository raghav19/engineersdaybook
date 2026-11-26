# One manifest for the whole agent sandbox: is a standard available?

Question: Does a ready-made, spec-driven manifest standard exist that describes the whole agent sandbox in one place? It must ship as an OCI artifact or OCI image. The owner would switch to Compose and wants one manifest, not many scattered files.

Research date: 2026-11-25. Local repo state: `main` at `a49cd73`. Host: Podman 6.1.4, `runsc` in `/usr/local/bin`, `podman-compose` present.

Source: Primary sources only, unless a line says **[secondary]**. Podman tag `v6.1.4` (source and docs). `docker/compose` tag `v5.8.0`. `containers/podman-compose` tag `v1.6.0`. `compose-spec/compose-spec` `main` at `6b3a2a9`. `docker/sandbox-kit-spec` `main` (pushed 2026-11-25). `containers/podlet` `main` (release `v0.3.2`). `devcontainers/spec` and `devcontainers/cli` `main`. `opencontainers/image-spec` `v1.1.1` and `main`. `kubernetes-sigs/agent-sandbox` `v1.0.12`. Nothing ran on the host. I read the sources and the local `podman ... --help` text only.

Evidence tags: **[repo]** is a file in this repo. **[doc]** is an official documentation page. **[src]** is source code at the stated tag. **[spec]** is a specification text. **[secondary]** is a news or blog page. **[inference]** is my own conclusion. "Not found in the sources checked" means I searched and found no text. It does not prove that the feature is absent.

## Short answer

No standard describes this whole sandbox in one OCI-distributed manifest and runs it on rootless Podman with gVisor. OCI defines packaging only. It does not define a sandbox description. The closest match by intent is the Docker Sandbox Kit specification. It declares egress policy, credentials and host mounts in the manifest of an OCI image. But only the closed `sbx` CLI runs a Kit, and that CLI uses microVMs. The closest match that Podman can run is Quadlet. Quadlet keeps systemd, gVisor flags, healthchecks and limits, and `podman quadlet install --application` installs a whole directory in one command. Compose is portable and has `docker compose publish` for OCI. But Compose has no egress policy, no systemd integration and no gVisor path through the Docker-compatible socket of Podman. A switch to Compose therefore adds glue. It does not remove glue. I rank "keep Quadlet, install it as one application, ship the config as an OCI artifact" first.

## Comparison table

Values: Yes, Partial, No, Not found (not found in the sources checked).

| Candidate | Image and tools | Config files | Multi-container | Egress policy | Credentials | OCI runtime (gVisor) | Host files | systemd | Podman runs it | OCI distribution | Maturity and license |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 Compose spec | Partial (`image`, `build`) | Yes (`configs`, `secrets`) | Yes | No (only `internal` network) | Partial (`secrets`, no injection) | Yes in spec (`runtime`) | Partial (bind volumes) | No | Partial (see section 1) | Yes in Docker Compose only (`publish`, `oci://`) | Spec Apache-2.0. Many keys optional |
| 2 Kit spec v3 | Yes (it is an image) | Yes (layers) | No (one workload plus mixins) | Yes (`network-policy@2`) | Yes (`credential@1`) | Not found | Partial (`host-mount@1`, no host path) | Not found | No (only `sbx`) | Yes (annotation on a plain image) | Experimental. Spec Apache-2.0. `sbx` is closed |
| 3 Dev Container | Yes (image, Dockerfile, Features) | Partial (`mounts`, lifecycle commands) | Partial (`dockerComposeFile`) | No | Partial (`secrets` names) | Partial (`runArgs`) | Partial (`mounts`, `initializeCommand`) | No | Partial (`--docker-path podman`) | Features and Templates only | Spec CC-BY-4.0. CLI MIT |
| 4 Kubernetes YAML with `kube play` | Partial | Yes (ConfigMap, Secret) | Yes (Pod) | No (no NetworkPolicy kind) | Partial (Secret) | No (`runtimeClassName` unsupported) | Yes (`hostPath`) | Yes (`.kube` Quadlet) | Yes | Via Flux, Helm or ORAS, then a manual pull | Podman support table is partial |
| 5 OCI specs and ORAS | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | Yes (`podman artifact`) | Yes (packaging only) | image-spec `v1.1.1` |
| 6 agent-sandbox CRD and others | Partial (pod spec) | Partial | Partial (one pod) | Yes in Kubernetes (`NetworkPolicy`) | Not found | Yes (via `RuntimeClass`) | Partial (PVC) | n/a | No (needs Kubernetes) | Not found | `v1.0.12`, Apache-2.0 |
| 7 Quadlet | Yes (`.build`, `.image`) | Partial (files by directory or `.artifact`) | Yes (many units, `.pod`) | No | Partial (`Secret=`, systemd credentials) | Yes (`PodmanArgs=`) | Yes (`Volume=`) | Yes | Yes | Partial (see section 7) | Upstream Podman. `.artifact` is experimental |
| 8 Nix and Home Manager | Yes | Yes | Yes | No | Partial | Partial | Yes | Yes | Yes | No (not OCI) | Baseline only |

## 1. Compose Specification

What it covers [spec]:

- Services, volumes, networks, `configs`, `secrets`, `healthcheck`, `read_only`, `cap_drop`, `tmpfs`, `init`, `runtime`, `post_start` and `x-` extensions. Source: https://github.com/compose-spec/compose-spec/blob/main/spec.md
- `runtime` quote: "`runtime` specifies which runtime to use for the service's containers. The value of `runtime` is specific to the implementation." Source: same file, section `runtime`.
- `configs` take `file`, `environment` or `content`. `secrets` take `file` or `environment`. Source: https://github.com/compose-spec/compose-spec/blob/main/08-configs.md and `09-secrets.md`.
- `x-` quote: "Compose ignores any fields that start with `x-`, this is the sole exception where Compose silently ignores unrecognized fields." Source: https://github.com/compose-spec/compose-spec/blob/main/11-extension.md
- The spec says no implementation must support every key. Quote: "supporting any of these is optional". Source: `spec.md`, section "Requirements and optional attributes".

What it does not cover:

- Egress allowlist and credential injection. Only `internal: true` on a network exists. Source: `spec.md`, section `internal`.
- systemd. The spec has no text on systemd. I found none.
- `include` with `oci://` is not in the spec text. The `include` page of the spec lists local paths only. Source: https://github.com/compose-spec/compose-spec/blob/main/14-include.md. The Docker how-to page does show `oci://docker.io/username/my-compose-app:latest` as an `include` item. Source: https://docs.docker.com/compose/how-tos/multiple-compose-files/include/ **[doc]**. The Docker reference page for `include` does not mention remote sources. Source: https://docs.docker.com/reference/compose-file/include/. So `oci://` include is a Docker Compose feature, not a spec feature. **[inference]**

OCI distribution [doc] [src]:

- `docker compose publish <ref>` pushes the Compose file as an OCI artifact. `docker compose -f oci://<ref> up` runs it. Source: https://docs.docker.com/compose/how-tos/oci-artifact/
- Limits: "You can't publish a configuration where a service has bind mounts." A service with only `build` cannot publish. Local files in `include` block publishing. Same page.
- Compose scans for sensitive data and asks you to confirm. It adds environment variables only with `--with-env`. Same page.
- The artifact must keep its files in one flat folder. The loader rejects names with path separators. Source: https://github.com/docker/compose/blob/v5.8.0/pkg/remote/oci.go (`validatePathInBase`, "OCI artifact resources must all live within the same folder"). The loader checks the constant `oci.ComposeProjectArtifactType` as the artifact type (same file). I did not read the constant value.
- This sandbox mounts host files with bind mounts (`ca.crt`, `repo.git`, the proxy config). So `docker compose publish` would refuse the sandbox unchanged. **[inference]** from the first two bullets and `.sandbox/agent/sandbox-agent.container` **[repo]**.

Does Podman run it?

- `podman compose` is "a thin wrapper around an external compose provider such as docker-compose or podman-compose". If both exist, docker-compose wins. Source: https://docs.podman.io/en/latest/markdown/podman-compose.1.html and local `podman compose --help`.
- Path A: `docker-compose` against the Podman socket. The Podman compat API handler for container create maps many `HostConfig` fields, such as `CapDrop`, `ReadonlyRootfs`, `SecurityOpt`, `Tmpfs`, `PidsLimit` and `Init`. I found no line that maps `HostConfig.Runtime`. Source: https://github.com/containers/podman/blob/v6.1.4/pkg/api/handlers/compat/containers_create.go. So `runtime: runsc` has no effect through this path. **[inference]** The `runsc` flags come from `containers.conf` in any case **[repo]** `.sandbox/agent/runsc.conf`.
- Path B: `podman-compose` v1.6.0 (GPL-2.0). It passes `--runtime` for `runtime`, and handles `read_only`, `cap_drop`, `security_opt`, `tmpfs`, `init`, `restart`, `cpus`, `pids_limit`, `mem_limit` and `healthcheck`. Source: https://github.com/containers/podman-compose/blob/v1.6.0/podman_compose.py (lines near `cnt.get("runtime")` and `healthcheck`). It does not read the top-level `configs` (the source has only a comment "configs: {...}"). It reads only local `include` paths. It has no `post_start`. I found no `oci://` code. The `healthcheck` code carries a "WIP" comment.
- `podman-compose` has a `systemd` subcommand that registers a stack for a template unit `podman-compose@<project>.service`. Source: `podman_compose.py`, function `compose_systemd`. This is one unit for the whole stack. It does not give per-container `[Service]` limits. **[inference]**

systemd integration:

- Compose has none of its own. The path from Compose to Quadlet is `podlet compose` (next paragraph).

Podlet [doc] [src]:

- Podlet (MPL-2.0, latest release `v0.3.2`, 2026-05-18) "generates Podman Quadlet files from a Podman command, compose file, or existing object". It can write multiple `.container` files, a `.pod` file, a `.kube` file or one `.quadlets` file. Source: https://github.com/containers/podlet/blob/main/README.md
- The converter rejects a number of Compose keys with an error. These include `configs`, `include`, `deploy`, `build`, `extends`, `profiles`, `scale`, `volumes_from`, all `x-` extensions, and any `secrets` that are not external. Source: https://github.com/containers/podlet/blob/main/src/cli/container/compose.rs and `src/cli/compose.rs`.
- Podlet takes `runtime` for global args (comment "Taken in `crate::cli::GlobalArgs::from_compose()`"). I did not check the exact output. Test it before you rely on it.
- Podlet has no `[Service]` mapping for `ExecStartPost`. Compose has no such key. So the three `ExecStartPost` lines of `sandbox-agent.container` **[repo]** cannot come from Compose. **[inference]**

Verdict: Compose is a portable service list. It covers four of the five container units well. It cannot hold the egress policy, the systemd limits, the host-side `nsenter` step or the host bridge. See "What must stay custom".

## 2. Docker Sandboxes Kit specification

Facts [spec] [doc]:

- Quote: "A Kit is one OCI image. Its manifest annotation `vnd.docker.sandbox.kit.descriptor` carries the Kit's declarations ... and its layers carry the Kit's content. There is no kit-specific media type or artifactType." Source: https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md section 1.
- Four annotations: `vnd.docker.sandbox.kit.descriptor` (compact JSON), `schema-version`, `capabilities` and `built-by`. Source: same file, section 9.3.
- Two kinds: `workload` (exactly one per composition) and `mixin` (zero or more). Source: same file, section 1.
- The v3 descriptor file is a YAML file next to a Dockerfile-like recipe. The first line is `# syntax=docker/sandbox-kit:3`. The README example names `hello/hello.yaml` and `gh.yaml`. The v2 format uses a file named `spec.yaml`. Sources: https://github.com/docker/sandbox-kit-spec/blob/main/README.md and https://docs.docker.com/ai/sandboxes/customize/kits-v2/. The name `spec.yaml` belongs to v2. The current spec is v3.
- A descriptor "deliberately carries no top-level identity name, image reference, or runtime config". The image config carries entrypoint, env and user. Source: `SPEC-v3.md` section 1.

Capability types (section 7.2 of `SPEC-v3.md`) that match this sandbox:

| Sandbox part | Kit capability | Source page |
|---|---|---|
| Egress allowlist by host, method and path | `com.docker.sandbox/network-policy@2` | `docs/spec/capabilities/com.docker.sandbox/network-policy@2.md` |
| Placeholder token swapped by a proxy | `com.docker.sandbox/credential@1` (`apiKey.proxyManaged`, `inject[]`) | `.../credential@1.md` |
| Volume for the home folder | `volume@1` | `.../volume@1.md` |
| Shared host directory | `host-mount@1` (no host-path field: "The Kit requests where storage appears inside the sandbox, not which host files it can access.") | `.../host-mount@1.md` |
| Resource limits | `resources@1` (`cpu`, `memory`, `gpu`) | `.../resources@1.md` |
| Private Docker daemon for builds | `dockerd@1` | listed in section 7.2 |
| Host ports | `port@1`, `host-port@1` | listed in section 7.2 |
| Agent instructions, skills, sessions | `agent-context@2`, `agent-skills@1`, `agent-sessions@2` | listed in section 7.2 |

The `network-policy@2` page has `install` and `runtime` phases, `allow` and `deny` lists, host patterns such as `*.example.com`, and bounded entries with `methods` and `paths`. Deny wins. This is close to the `allowlist` and `rules` of `iron-proxy.yaml` **[repo]**. The `credential@1` page says the host credential store is "the sole source". A Kit "declares the need, the user's bindings answer it".

Other useful rules:

- Fail closed: unknown descriptor fields are errors. A required capability that the host cannot grant refuses the launch. Source: https://github.com/docker/sandbox-kit-spec/blob/main/docs/design.md
- Permission gate: a widened permission "MUST stop for approval". The spec stores a "permission surface" in a lock file and diffs it. Source: `SPEC-v3.md` section 7.4.
- Conformance: `kit-tck validate` checks a Kit. `kit-tck runtime --adapter <exe>` checks a runtime through an adapter executable "in any language". Source: https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/conformance.md

What it does not cover or what I did not find:

- Multi-container topology. A Kit is one image. The builder and the proxy are services of the `sbx` runtime, not parts of a Kit. Source: README ("A Kit is a single OCI image") and https://docs.docker.com/ai/sandboxes/architecture/ ("All outbound TCP traffic from the sandbox routes through a proxy on your host").
- OCI runtime selection such as gVisor. The spec has no capability for it. A search of the spec files for `runsc`, `gvisor`, `kata` and `microvm` found no match. `podman` appears once, as an example value of a `conflicts` field.
- systemd units. Not found in the sources checked.
- A runtime other than `sbx`. The README names only the `sbx` CLI ("supports Kits v3 in both local and cloud mode"). The spec describes the conformance suite for other runtimes, but I found no other runtime that claims support. Search of GitHub repositories found a fork of the spec and a CI gate tool. I found no second runtime.
- A Podman path. Not found in the sources checked.

Status and license:

- Quote: "This specification is experimental. ... A final version is planned for Q4 2026." Source: README.
- Spec repository: Apache-2.0. Created 2026-09-16. 204 stars on 2026-11-25. Source: GitHub API for `docker/sandbox-kit-spec`.
- The `sbx` release repository has a license file with "Copyright (c) 2026 Docker Inc. All rights reserved." GitHub lists the license as `NOASSERTION`. Source: https://github.com/docker/sbx-releases/blob/main/LICENSE. The `sbx` binary is not open source. **[inference]** from that text.
- `GOVERNANCE.md` says "Docker maintains this specification". Source: https://github.com/docker/sandbox-kit-spec/blob/main/GOVERNANCE.md. A Linux.com article says Docker will contribute the spec to the CNCF for neutral governance and has not yet submitted it. **[secondary]** https://www.linux.com/featured/docker-commits-to-bringing-the-sandbox-kit-spec-to-the-cncf/
- Install note: on Ubuntu, `sbx` needs the user in the `kvm` group. Source: https://github.com/docker/sbx-releases/blob/main/README.md. The architecture page calls the isolation "Full (hypervisor)". Source: https://docs.docker.com/ai/sandboxes/architecture/. This does not match a gVisor design. **[inference]**
- `sbx kit` is a CLI command group. `sbx kit verify` checks signatures. `sbx run <kit-ref>` accepts an OCI reference, a local directory or a Git URL. Source: https://docs.docker.com/ai/sandboxes/customize/use-kits/. Building a custom template needs Docker Desktop. Source: https://docs.docker.com/ai/sandboxes/customize/kits-v2/.

Verdict: This is the best match for the idea "one OCI artifact holds the content and the authority". It cannot run on this host's Podman and gVisor stack today. Use it as a design reference only.

## 3. Dev Container specification

Facts [spec] [doc]:

- Purpose quote: "provide a way to enrich containers with the content and metadata necessary to enable development inside them." Source: https://containers.dev/implementors/spec/
- `devcontainer.json` has `image` or `build`, `features`, `mounts`, `containerEnv`, `remoteUser`, `init`, `privileged`, `capAdd`, `securityOpt`, `runArgs`, lifecycle commands (`onCreateCommand`, `postStartCommand`), `initializeCommand` (runs on the host), `dockerComposeFile` with `service`, and `secrets`. Source: https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainerjson-reference.md
- `runArgs` takes Docker CLI arguments. So `--runtime=runsc` fits there. It applies to image and Dockerfile setups. **[inference]**
- The `secrets` property only declares names. Source: https://github.com/devcontainers/spec/blob/main/docs/specs/declarative-secrets.md. It has no proxy injection.
- Features are OCI artifacts. Quote: "A custom media type `application/vnd.devcontainers` and `application/vnd.devcontainers.layer.v1+tar`". Pattern: `<registry>/<namespace>/<id>[:version]`. Source: https://containers.dev/implementors/features-distribution/
- Lockfile: `.devcontainer-lock.json` pins Features. The CLI writes it on `build` and `up`. Source: https://github.com/devcontainers/cli/blob/main/README.md
- Image metadata: the spec stores dev container settings in a prebuilt image, so an image can carry `mounts`, `containerEnv`, lifecycle commands and `remoteUser`. Source: https://github.com/devcontainers/spec/blob/main/docs/specs/image-metadata.md
- Dotfiles are CLI options (`--dotfiles-repository`, `--dotfiles-install-command`, `--dotfiles-target-path`), not a `devcontainer.json` property. Source: https://github.com/devcontainers/cli/blob/main/src/spec-node/devContainersSpecCLI.ts
- Podman: the CLI repo has a test that runs `devcontainer up --docker-path podman` with a Features config. Source: https://github.com/devcontainers/cli/blob/main/src/test/cli.podman.test.ts. I found no statement about rootless limits or Quadlet.
- License and status: spec CC-BY-4.0 (last push 2026-03-20). CLI MIT (push 2026-11-20). Source: GitHub API for `devcontainers/spec` and `devcontainers/cli`.

What it does not cover:

- Egress policy. Not found in the sources checked.
- Host services and systemd. The spec targets a tool that attaches to a dev container. A host unit such as `bridge.service` has no place. `initializeCommand` runs on the host but only at create and start. **[inference]**
- Distribution of the whole configuration as one OCI artifact. Only Features and Templates have OCI distribution. Source: https://containers.dev/implementors/features-distribution/ and `devcontainer-templates-distribution.md`.
- Multi-container sandbox control. The Compose path names one `service` for the tool. The other services are supporting services.

Verdict: Poor fit. It describes a development environment that an editor attaches to. It does not describe a security boundary.

## 4. Kubernetes YAML with `podman kube play` and Quadlet `.kube`

Facts [doc]:

- Kinds that `podman kube play` supports: Pod, Deployment, PersistentVolumeClaim, ConfigMap, Secret, DaemonSet, Job. Source: https://github.com/containers/podman/blob/v6.1.4/docs/source/markdown/podman-kube-play.1.md.in
- Volume types: `hostPath`, `emptyDir`, `configMap`, `persistentVolumeClaim`, `image`. Same page. The `image` volume works in rootful mode only.
- ConfigMap quote: "ConfigMaps aren't a standalone object in Podman. Instead, when a container uses a ConfigMap, Podman creates environment variables or volumes as needed." A Secret "represents a Podman named secret". Same page.
- Field support table (v6.1.4): supported are `securityContext.readOnlyRootFilesystem`, `capabilities.drop`, `allowPrivilegeEscalation`, `runAsUser`, `resources.limits` for containers, `livenessProbe`, `restartPolicy`, `initContainers` and `hostNetwork`. Not supported are `runtimeClassName`, `readinessProbe`, `startupProbe`, `seccompProfile`, `dnsPolicy` and `automountServiceAccountToken`. Source: https://github.com/containers/podman/blob/v6.1.4/docs/kubernetes_support.md
- So gVisor cannot be chosen in the YAML. With a `.kube` unit, `PodmanArgs=` goes to `podman kube play`. I found no statement that `kube play` accepts `--runtime`. Not found in the sources checked.
- A `NetworkPolicy` kind is not in the supported list. So the egress policy cannot be in the YAML.
- Podman-specific behavior hides in annotations such as `io.podman.annotations.userns` and `io.podman.annotations.pids-limit/$ctrname`. Source: `podman-kube-play.1.md.in`.
- The `[Kube]` Quadlet section: one required key `Yaml`. It also takes `ConfigMap=`, `Network=`, `PublishPort=`, `UserNS=` and `PodmanArgs=`. Source: https://github.com/containers/podman/blob/v6.1.4/docs/source/markdown/podman-systemd.unit.5.md (section "Kube units").

Distribution as OCI:

- `flux push artifact` "creates a tarball from the given directory or the single file" and "uploads the artifact to an OCI repository". Source: https://fluxcd.io/flux/cmd/flux_push_artifact/
- Helm stores a chart under `oci://` with config type `application/vnd.cncf.helm.config.v1+json` and content layer `application/vnd.cncf.helm.chart.content.v1.tar+gzip`. Source: https://helm.sh/docs/topics/registries/
- ORAS pushes any files. Source: https://oras.land/docs/commands/oras_push/ ("Push files to a registry or an OCI image layout").
- Podman cannot pull a Flux or Helm artifact by itself. `podman artifact pull` and `podman artifact extract` exist in v6.1.4 and work on OCI artifacts. Source: https://github.com/containers/podman/blob/v6.1.4/docs/source/markdown/podman-artifact-extract.1.md. That page says extract names each file from the `org.opencontainers.image.title` annotation. Whether a directory tree survives is not found in the sources checked.

Verdict: Strong on Podman and good for a pod of containers. It cannot name `runsc` and it cannot express the egress policy. It is a step backward for this sandbox, because the gVisor flag is the core control.

## 5. OCI specifications and ORAS

What OCI defines:

- An image manifest holds a config descriptor and layer descriptors. The goals are content-addressable images, multi-architecture images and translation to the OCI Runtime Specification. Source: https://github.com/opencontainers/image-spec/blob/main/manifest.md
- Other content "MAY be packaged using the image manifest". Then `config.mediaType` "MUST be set to a value specific to the artifact type or the empty value". If it is the empty value, `artifactType` "MUST be defined". Same page, section "Guidelines for Artifact Usage".
- `artifactType` is "OPTIONAL" and "MUST comply with RFC 6838". A registry must not error on an unknown `artifactType`. Same page.
- `subject` makes a "weak association" to another manifest. The referrers API lists such manifests. Same page and https://github.com/opencontainers/distribution-spec/blob/main/spec.md
- The empty descriptor media type is `application/vnd.oci.empty.v1+json`. Source: https://github.com/opencontainers/image-spec/blob/main/media-types.md
- Latest image-spec release: `v1.1.1` (2025-03-03). Latest distribution-spec release: `v1.1.1` (2025-01-29). Source: GitHub API for both repositories.
- ORAS: "The structure of an OCI Artifact includes an Image Manifest or an Image Index that points to other OCI artifacts." Source: https://oras.land/docs/concepts/artifact/
- The OCI Runtime Specification `config.json` describes one container: "the process to run, environment variables to inject, sandboxing features to use". Source: https://github.com/opencontainers/runtime-spec/blob/main/config.md

What "manifest" means in OCI versus here:

- In OCI, a manifest lists blobs by digest. It describes how to store and fetch content. It does not say what the content means or how to run it.
- In this note, a sandbox manifest says which containers run and which hosts they reach. It also says which secrets they hold and which runtime isolates them.
- OCI defines packaging, not a sandbox description. The OCI texts that I read contain no sandbox schema. The Kit spec and the Compose artifact both add their own meaning on top of OCI. The Kit spec does it by an annotation. Compose does it by an `artifactType`. **[inference]** from the sources above.

Verdict: Use OCI as the shipping container for whatever description you choose.

## 6. Agent-sandbox specifications

Search of GitHub and the web on 2026-11-25. Results:

- `kubernetes-sigs/agent-sandbox` (Apache-2.0, `v1.0.12`, released 2026-11-20, 4.7k stars). A Kubernetes CRD `Sandbox` under SIG Apps. Quote: "a declarative, standardized API for managing workloads that require the characteristics of a long-running, stateful, singleton container with a stable identity". It has `SandboxTemplate`, `SandboxClaim` and `SandboxWarmPool`. `SandboxTemplate` has a `networkPolicy` field (ingress and egress rules, `Managed` or `Unmanaged`) and a `podTemplate`. Isolation comes from a `RuntimeClass` such as gVisor or Kata. Sources: https://github.com/kubernetes-sigs/agent-sandbox/blob/main/README.md and https://github.com/kubernetes-sigs/agent-sandbox/blob/main/docs/api.md. It needs Kubernetes 1.25 or later. I found no OCI distribution of the CRD manifest and no Podman path.
- Agent Substrate (CNCF Sandbox, accepted 2026-09-28, Apache-2.0). "Zero-trust sandboxing for millions of agents on Kubernetes". It runs OCI images in gVisor or Cloud Hypervisor microVMs, has an egress gateway that injects credentials and gives each actor a SPIFFE identity. It uses its own `ActorTemplate` and `WorkerPool` resources. Sources: https://www.cncf.io/projects/agent-substrate/ and https://github.com/agent-substrate/substrate/blob/main/README.md. It is a runtime on Kubernetes, not a manifest standard.
- OpenShell (CNCF Sandbox, accepted 2026-09-26, Apache-2.0). "You declare what each agent can touch in a policy, and OpenShell enforces it." The policy is YAML with a `network_policies` section (endpoints, binaries, enforcement). The support matrix lists Docker, Podman, Kubernetes and MicroVM runtimes. It does not list gVisor. Sources: https://www.cncf.io/projects/openshell/, https://github.com/ai-openshell/openshell/blob/main/README.md, https://docs.nvidia.com/openshell/latest/about/support-matrix, https://docs.nvidia.com/openshell/latest/tutorials/first-network-policy. It is a product with its own policy format. I found no OCI distribution of the policy.
- OpenAI Agents SDK "Manifest": a workspace contract in an SDK (files, repos, mounts, environment, users). Search result only, **[secondary]**. I did not open the page. It is an SDK feature. I found no open standard text and no OCI link.
- "Agent Manifest" (agent-manifest-spec.org): an identity and governance declaration for agents. It says it is not a runtime. Search result only, **[secondary]**. It does not describe a sandbox.
- A ratified open standard for agent-sandbox manifests: not found.

Verdict: Several projects exist. None is a manifest standard that runs on rootless Podman with gVisor and ships as one OCI artifact.

## 7. Podman Quadlet

Unit types (v6.1.4): `.artifact`, `.build`, `.container`, `.image`, `.kube`, `.network`, `.pod`, `.volume`. Source: https://github.com/containers/podman/blob/v6.1.4/docs/source/markdown/podman-systemd.unit.5.md. The `.artifact` unit is marked "experimental and still in development".

Install and application [doc] [src]:

- `podman quadlet install [options] QUADLET-PATH-OR-URL [FILES-PATH-OR-URL...]`. Source: https://github.com/containers/podman/blob/v6.1.4/docs/source/markdown/podman-quadlet-install.1.md.in
- The page says the command can install a directory of files. Quote: "a directory containing multiple Quadlet files and other non-Quadlet files for installation (for example a config file for a quadlet container)". All files from one directory are one "application". The page also says: "removing a quadlet that is part of an application will remove the entire application."
- `--application <name>`: "all files will be installed under a directory with the application name". The name is "required when specifying a directory path".
- Multi-unit file: a file with the extension `.quadlets`. Units are separated by `---`. Each unit needs a `# FileName=<name>` comment. Quote: "Multi-quadlet functionality requires the `.quadlets` file extension." Units from one `.quadlets` file form one application only if you pass `--application`. Same page. The `podman-systemd.unit` page does not mention `.quadlets`.
- Quadlet searches subdirectories of its unit directories recursively. Source: `podman-systemd.unit.5.md`, section on unit search paths.
- Podlet can write one `.quadlets` file from a Compose file (`--quadlets-file`). Source: podlet README.

OCI install, with a conflict in the sources:

- The command help text, on this host and in the source, says: "Quadlets may be specified as local files, Web URLs, and OCI artifacts." Source: local `podman quadlet install --help` and https://github.com/containers/podman/blob/v6.1.4/cmd/podman/quadlet/install.go
- The install code that I read handles local paths, directories, `.quadlets` files and URLs. The function `isURL` accepts only `http://` and `https://`. I found no OCI pull code in `pkg/domain/infra/abi/quadlet.go` at `v6.1.4` or at `main`. Source: https://github.com/containers/podman/blob/v6.1.4/pkg/domain/infra/abi/quadlet.go. The man page does not document OCI install. **[inference]** The "OCI artifacts" text may refer to the `.artifact` unit type. Test it before you rely on it.
- A native OCI path does exist for content. Podman has `podman artifact pull|push|extract|add`. The `.artifact` unit pulls an artifact. A container mounts it with `Mount=type=artifact,source=my-artifact.artifact,destination=/etc/config`. Source: `podman-systemd.unit.5.md`, section "Artifact units" (the example `my-artifact.artifact` and `my-app.container`) and https://github.com/containers/podman/blob/v6.1.4/docs/source/markdown/options/mount.md. So the proxy config and the runtime flags file could ship as an OCI artifact and mount into the container without a symlink. **[inference]** Mount options `digest`, `title` and `name` exist for multi-blob artifacts.

What Quadlet keeps from this sandbox [repo] [doc]:

- gVisor: no `Runtime=` key exists in the `[Container]` section I read. The sandbox uses `PodmanArgs=--runtime=runsc`. Source: `podman-systemd.unit.5.md` (key list) and `.sandbox/agent/sandbox-agent.container`.
- `[Unit]`, `[Service]` and `[Install]` pass to systemd. Quote: "the [Service] table and [Install] tables pass directly to systemd". So `MemoryMax`, `ExecStartPost` and `LoadCredentialEncrypted` stay. Source: `podman-systemd.unit.5.md`.
- `HealthCmd=`, `ReadOnly=`, `DropCapability=`, `NoNewPrivileges=`, `Tmpfs=`, `RunInit=`, `Secret=`, `Network=` and `ContainersConfModule=` exist as keys. Source: same page.
- `.build` builds an image from a Containerfile. Minimal keys: `ImageTag=` and `File=` or `SetWorkingDirectory=`. A container can depend on it. Source: same page, section "Build units". This could replace the `podman build` lines of `just sandbox build`. **[inference]**

What Quadlet does not cover:

- Egress allowlist. The sandbox solves it with a proxy container, not with a Quadlet key.
- Files outside the Quadlet tree. `~/.config/containers/containers.conf.d/*.conf` (the `runsc` flags) and `~/.config/systemd/user/sandbox-bridge.service` are not Quadlet files. The application folder is under the Quadlet unit directory. A plain `.service` file there is not loaded by systemd as a unit. **[inference]** The `ContainersConfModule=` key may carry the `runsc` flags. I found no statement that a module can set `[engine.runtimes_flags]`. Spike it.
- Key creation, the encrypted credential and CA creation. These are setup steps, not unit content.

Verdict: This is the manifest format that Podman itself defines for this exact job. It is not a cross-vendor standard.

## 8. Baseline: Nix and Home Manager

A Nix flake or a Home Manager module can declare the host side as one evaluated configuration. It covers the units, the config files, the symlinks and the packages. Home Manager has a `services.podman` module that writes Quadlet files, with `extraPodmanArgs` and `extraConfig` options. Source: https://github.com/nix-community/home-manager/tree/master/modules/services/podman/linux (files `containers.nix`, `builds.nix`, `install-quadlet.nix`). It is declarative and reproducible. It is not an OCI format and not an open specification. It needs Nix on the host. I did not read its option text in full. Treat this as a baseline only.

## Ranked recommendation for this sandbox

| Rank | Option | Why | Main cost |
|---|---|---|---|
| 1 | Keep Quadlet. Install the units, the proxy configs and the image recipes as one application with `podman quadlet install --application sandbox <dir>`. Optionally ship the configs as an OCI artifact with `.artifact` and `Mount=type=artifact`. | Podman-native. It keeps gVisor, systemd limits, healthchecks and `ExecStartPost`. It replaces the symlink loop of `just sandbox setup` for Quadlet files. | Not one file. The `runsc` flags, the bridge unit and the key steps stay outside. OCI install of a whole application is not confirmed. |
| 2 | Compose with `podman-compose`, plus `podlet` to regenerate Quadlet if needed. | Familiar format. `docker compose publish` gives an OCI artifact on Docker Compose. | No systemd limits, no `configs` in `podman-compose` v1.6.0, no `post_start`, no egress policy. More glue than now. `publish` refuses bind mounts. |
| 3 | Watch the Kit spec. Reuse its ideas. | It puts network policy, credentials and mounts in the manifest of an OCI image and makes widened authority visible in a diff. | `sbx` only, closed binary, microVM, experimental, no Podman or gVisor. |
| 4 | Kubernetes YAML with `kube play` | Pod grouping, ConfigMap and Secret. | No `runtimeClassName`, no NetworkPolicy. |
| 5 | Dev Container | Good for the editor and Features. | Not a security boundary. No egress policy. |
| 6 | agent-sandbox, Agent Substrate, OpenShell | Real projects with egress and credential control. | Need Kubernetes, or replace the whole stack and use their own policy format. |

Plan for rank 1, each step with a check:

1. Put the units in one directory. Give the two proxy units distinct names, because Quadlet names a unit by its file name. Check: `podman quadlet install --application sandbox <dir>` then `podman quadlet list` shows all units.
2. Spike `ContainersConfModule=` for the `runsc` flags. Check: `podman info` shows the flags and `podman exec sandbox-agent dmesg` shows gVisor. If it fails, keep the `containers.conf.d` link.
3. Spike `.artifact` with `Mount=type=artifact` for `iron-proxy.yaml`. Check: the proxy container reads the file after `podman artifact push` and a service restart.
4. Spike `podman quadlet install oci://...`. Check: the command either pulls the artifact or prints an error. If it prints an error, use `podman artifact extract` and then install from the directory.
5. TODO: test `.build` units in place of `podman build`. Check: a start of `sandbox-agent.service` builds the image once and reuses the cache.

## What must stay custom

- The egress policy and credential injection. `iron-proxy.yaml` stays. No candidate except the Kit spec has an equivalent, and the Kit spec has no runtime for Podman. A converter from `network-policy@2` to `iron-proxy.yaml` would be custom work. **[inference]**
- The gVisor flags (`ignore-cgroups`, `network=host`, `host-uds=open`) in `containers.conf`. Compose, Dev Containers and `kube play` do not carry them. Whether a Quadlet module can carry them is unconfirmed.
- The host loopback step (`podman unshare nsenter ... ip link set lo up`) and the socat relay. They run on the host as `ExecStartPost`. Compose has `post_start`, which runs inside the container, so it does not fit the host `nsenter` step. **[inference]**
- The host bridge `bridge.service` and its `ports` file. This is a plain systemd user unit.
- Setup of the CA, the encrypted credential (`systemd-creds`) and the repo link. These are host steps. The Kit spec leaves secret storage to the host. Quadlet and Compose leave it to you.
- The image tool list (mise `tools/*.toml`, mise tasks) and the Dockerfile. No candidate describes tools at that level. Kits and Dev Container Features only install packages inside an image.
- The systemd limits (`MemoryMax`, `TasksMax`, `CPUQuota`) that replace the gVisor cgroup limits. Only Quadlet and plain systemd carry them.
- The check that gates a change of authority. The Kit spec defines a permission surface and a gate. For this sandbox, a review of a diff of `iron-proxy.yaml` is the equivalent.

## Not tested

I ran no install, no `systemctl` and no container. These claims come from reading sources and `--help` text. They need a spike: OCI install by `podman quadlet install`, `ContainersConfModule=` carrying `runsc` flags, `Mount=type=artifact` in a rootless gVisor container, the output of `podlet compose` for `runtime`, and whether the Podman compat API ignores `runtime`.
