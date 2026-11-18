# Remote BuildKit for the agent sandbox

Question: Can the agent sandbox stay on libkrun (the podman-krun design), or stay on podman with gVisor? Can it build images with a remote BuildKit in place of the `build.sock` Go listener? The builder can be a remote BuildKit, or a remote BuildKit in its own sandbox. A harness such as Claude Code must drive it with no custom code.

Research date: 2026-11-18. Local repo state: `main` at `46ba18e`, with the untracked handoff files listed in `gitStatus`.

Versions read (all primary sources):

- BuildKit tag `v0.35.0` (commit `f55949d`, released 2026-11-11). `buildctl` and `buildkitd` source, `README.md`, `PROJECT.md`, `docs/`, `examples/`.
- Buildx tag `v0.39.0` (commit `360040a`). Docker docs repo `docker/docs` `main` at `9473430`.
- Podman tag `v6.2.0` (commit `055de04`). Buildah tag `v1.46.1` (commit `2560f60`).
- gVisor tag `release-20261116.0` (source and `g3doc/`). libkrun `main` at `b7925e4` (docs) and tag `v1.19.8`. libkrunfw tag `v5.6.4`. crun tag `1.31`.
- iron-proxy `main` at `d303dcd` (the commit of release `v0.57.0`, 2026-11-18). The repo docs pin `0.56.0`.
- grpc-go `master` at `70d9d2f`. systemd `main` at `8eb3506`.

Evidence tags:

- **[doc]**: an official documentation page or README.
- **[src]**: source code at the tag above. File and line are given.
- **[advisory]**: a GitHub security advisory of the project.
- **[repo]**: a file in this repo. Your own spike results count as **[repo]**, not as primary sources.
- **[inference]**: my own conclusion from the sources. No source says it.
- **UNVERIFIED**: I did not find a source, or I did not test it.

I ran no build and no daemon. Every statement about behavior comes from reading docs and source.

## Answer

1. `podman build` cannot use a remote BuildKit. Podman builds with Buildah code. `podman --remote build` sends the build to a Podman API service, not to `buildkitd`. [src] [doc]
2. A client that speaks to `buildkitd` is needed. The stock choices are `buildctl` (one static binary from the BuildKit release) and `docker buildx` with the `remote` driver (it needs the `docker` CLI). `buildctl` is the better fit for the sandbox image. [doc]
3. `buildkitd` has no authorization. Its only access control is mutual TLS, or the file mode of a Unix socket. Any client that connects can run any `RUN` step in the worker. That is code execution on the builder. [src] [doc]
4. This changes your threat model. With `build.sock`, the agent sends one checked JSON line. With BuildKit, the agent sends build definitions. The BuildKit project says its API is only safe for a trusted client. It treats a build service for untrusted users as a special case. [advisory]
5. A remote BuildKit over mTLS cannot pass through iron-proxy in the current design. The iron-proxy tunnel listener ends TLS (MITM) for every allowed host. The client certificate and the builder certificate would not match. [doc]
6. Under krun, a remote builder needs a network path out of the VM. Your own spikes show that this is the part that made krun "too complex". Under gVisor, any TCP builder arrives over a Unix socket and a host bridge, as `proxy.sock` does today. [repo]
7. The best fit to your goal is **not** a remote builder. Run stock `buildkitd` as a sibling gVisor builder container, or as a rootless user unit. Share its Unix socket with the sandbox. No Go listener, no context upload to a registry, no `crane` step. This is UNVERIFIED and needs two spikes (see "How this works for you").
8. A hosted builder (Depot, Docker Build Cloud) removes the builder code. It adds an outward dependency and a per-account credential. It also needs direct mTLS to the vendor, so it has the same proxy problem as point 5.

## What your docs say

| Topic | Fact | Source |
|---|---|---|
| Threat model | The agent is not trusted. Every value it sends is hostile until the listener checks it. | `docs/handoff/go-build-socket-listener.md` lines 9 to 13 [repo] |
| Why `build.sock` exists | A build needs `SETUID`, `SETGID` and `SYS_CHROOT` and runs untrusted code. The sandbox must not hold these. A host process builds for the agent. | `go-build-socket-listener.md` lines 7 to 11 and `agent-image-build-system.md` lines 14 to 22 [repo] |
| What the builder does | `podman run` in gVisor, no network, uid 1000, three capabilities. It builds a context that the host downloaded with `crane export REGISTRY/build-context@sha256:DIGEST` (64 MB limit). | `go-build-socket-listener.md` lines 41 to 50 [repo] |
| Registry and auth | Image goes to `ghcr.io`. The proxy swaps the placeholder `GHCR_PUSH_TOKEN`. A path rule limits `POST`, `PATCH`, `PUT` to `/v2/raghav19/sandbox-builds/**`. The full push sequence is not tested. | `agent-image-build-system.md` lines 143 to 145 [repo] |
| Custom code in the `build.sock` path | A Go listener (about nine steps), a JSON contract, input checks, `crane`, `podman run` wiring, signal handling, tests, and a `build.just` change. | `go-build-socket-listener.md` lines 52 to 100 [repo] |
| Sandbox network | `--network=none`. One way out: `proxy.sock`, `systemd-socket-proxyd`, iron-proxy on `127.0.0.1:18080`. iron-proxy passes HTTP and TLS only. Raw TCP and SSH fail. | `podman-sandbox-merged.md` lines 25 to 36 and `podman-gvisor-caddy-sandbox.md` line 257 [repo] |
| gVisor design | Rootless Podman, `runsc`, flags `ignore-cgroups`, `network=host` (a loopback only), `host-uds=open`. A Quadlet unit sets the limits. Host-side `nft` rule by uid guards the proxy ports. | `podman-gvisor-sandbox.md` lines 38 to 44 [repo] |
| krun design | Rootless Podman, `crun` with `krun`. Own guest kernel, guest has full capabilities and no seccomp. A host Unix socket gives `ECONNREFUSED` in the guest. `--network=none` gives no route to the host loopback. `podman exec` does not work. Nested Podman works as non-root `agent` with native overlay. Status: built (PR 284 and 287), then rejected as too complex. | `podman-krun-sandbox.md` lines 86 to 90, `podman-plain-sandbox.md` lines 101 to 105, `podman-sandbox-merged.md` lines 38 to 57 and `podman-gvisor-caddy-sandbox.md` lines 164 to 197 [repo] |
| No SPIFFE needed for builds | The identity work covers the sandbox and the proxy. It does not touch builds. | `spiffe-identity-podman-sandbox.md` [repo] |

Two older handoffs claim that `--network=none` with TSI reaches the host loopback and that `podman exec` works under krun. `podman-sandbox-merged.md` (line 149) says these claims are wrong. This note follows the merged handoff.

## Evidence by question

### 1. Can `podman build` talk to a remote BuildKit?

No. I found no Podman or Buildah path that speaks the BuildKit gRPC protocol.

- `podman build` runs Buildah code. Source: Podman `v6.2.0`, `docs/source/markdown/podman-build.1.md.in` lines 43 to 45: "`podman build` uses code sourced from the `Buildah` project to build container images". [doc]
- `podman --remote` is a client for the Podman REST API. Source: `docs/source/markdown/podman-remote.1.md` lines 16 to 20. The page says Podman "uses Buildah(1) internally to create container images". It also says the remote client talks to "a Podman backend node through a RESTful API tunneled through a ssh connection". [doc]
- The Podman API server registers the compat build route `POST /build` (`pkg/api/server/register_images.go` lines 795 and 797). A search of `pkg/api/server/*.go` finds no `/grpc` or `/session` route. The remote client calls `/build` in `pkg/bindings/images/build.go` line 1003. [src] So `docker buildx` probably cannot use BuildKit through a Podman socket. [inference]
- Buildah imports only the Dockerfile parser from BuildKit. Source: Buildah `v1.46.1`, `imagebuildah/stage_executor.go` line 18 (`buildkitparser "github.com/moby/buildkit/frontend/dockerfile/parser"`). No client or solver import exists. [src]
- Consequence: a remote `podman build` means a remote Podman service. The Podman API can run any container on that host. Your own notes reject this (`podman-plain-sandbox.md`, table of rejected options: "A remote Podman socket for the agent"). [repo]

Client tools that do speak BuildKit gRPC:

| Tool | Installable with no custom code | Notes |
|---|---|---|
| `buildctl` | Yes. Static binary in the release tarball `buildkit-v0.35.0.linux-amd64.tar.gz` (also `arm64`). The release ships `.sigstore.json`, provenance and SBOM files. | Dockerfile frontend: `buildctl build --frontend=dockerfile.v0 --local context=. --local dockerfile=.` (`README.md` lines 230 to 245). [doc] |
| `docker buildx` with the `remote` driver | Yes. Release asset `buildx-v0.39.0.linux-amd64`. It is a plugin of the `docker` CLI. | Driver `remote` takes `tcp://`, `unix://`, `ssh://`, `docker-container://`, `kube-pod://`, `npipe://` (`driver/remote/util/endpoint.go` line 10). [src] |
| `nerdctl build` | Yes. | It needs a running `buildkitd` (`docs/command-reference.md` line 772 at `v2.4.2`). [doc] |
| Frontends | Inside the daemon. The Dockerfile frontend is built in. `gateway.v0` runs a frontend image. | `README.md` lines 195 to 261. [doc] |

The `moby/buildkit` project also ships `buildctl --addr podman-container://NAME`. It runs `podman exec` into a BuildKit container (`README.md` lines 785 to 793). That is a local path. It needs the Podman socket of the host. [doc]

### 2. Remote access to `buildkitd`: flags, TLS and authorization

Transport options (all [doc] unless marked):

- `buildkitd --addr tcp://HOST:PORT --tlscacert CA --tlscert CERT --tlskey KEY` and `buildctl --addr tcp://HOST:PORT --tlscacert CA --tlscert CERT --tlskey KEY build ...`. Source: `README.md` lines 736 to 757.
- `buildkitd.toml`: `[grpc]` has `address`, `debugAddress`, `uid`, `gid`. `[grpc.tls]` has `cert`, `key`, `ca`. Source: `docs/buildkitd.toml.md` lines 42 to 51. The file path is `/etc/buildkit/buildkitd.toml` (rootful) or `~/.config/buildkit/buildkitd.toml` (rootless), lines 9 to 11.
- Unix socket: `--addr unix:///path` with `--group GROUP`. Source: `docs/buildkitd.toml.md` line 46 (uid, gid) and Buildx docs `content/manuals/build/builders/drivers/remote.md` lines 45 to 49. Systemd activation: `--addr fd://` (`README.md` lines 732 to 734).
- Client check of TLS: `buildctl` applies the TLS flags to any address. [src] `client/client.go` lines 306 to 336. The server warns that TLS is off for Unix sockets: `cmd/buildkitd/main.go` lines 776 to 780. [src]

Authentication and authorization (verified in source):

- Client certificates are required **only if** `--tlscacert` is set. The code sets `ClientAuth = tls.RequireAndVerifyClientCert` only when a CA file is given. Source: `cmd/buildkitd/main.go` lines 820 to 856, especially 848 to 853. With a cert and key but no CA, the server uses TLS with no client check. [src]
- With TCP and no TLS, the daemon prints a warning and listens anyway. Source: `cmd/buildkitd/main.go` lines 786 to 797. [src]
- There is no other check. The gRPC server has one unary interceptor that only logs errors (`cmd/buildkitd/main.go` lines 365 and 805 to 818). I found no per-client identity, no ACL, no per-client cache namespace and no API token in `cmd/buildkitd`. [src]
- Every certificate that the CA signs has the same rights. The cert has no role. [inference] Revoking one client means a new CA or short-lived certificates. Go's TLS server has no CRL check by default. [inference]
- The API gives a client more than builds. The `Control` service has `DiskUsage`, `Prune`, `Solve`, `Session` and `ListWorkers`. Source: `api/services/control/control.proto` lines 14 to 20. A client can prune the cache of every other client. [src]

What an authorized client can do:

- The README says why mTLS matters: "Enabling TCP without mTLS is dangerous because the executor containers (aka Dockerfile `RUN` containers) can call BuildKit API as well." (`README.md` lines 740 to 741). [doc]
- Any client can run any command in `RUN` steps. That is code execution in the worker. With a rootful daemon, the worker is root on the host with the default OCI capabilities. With a rootless daemon, it is a user namespace of the daemon user. [inference] from `docs/rootless.md` lines 3 to 9.
- Entitlements are off by default. `docs/buildkitd.toml.md` lines 19 to 20: "insecure-entitlements allows insecure entitlements, disabled by default" (values `network.host`, `security.insecure`, `device`). `cmd/buildkitd/main.go` lines 432 to 448 accepts only these three values. A build needs the entitlement on both the daemon and the request (`docs/proxy.md` lines 41 and 58 to 63). [doc] [src]
- The default network for `RUN` is not "none". The `auto` mode uses CNI if a CNI config file exists. Otherwise it logs "using host network as the default" and uses the host network. Source: `util/network/netproviders/network.go` lines 45 to 76 and `network_unix.go` lines 14 to 16. Rootless mode "always" uses `network.host` (`docs/rootless.md` line 9). [src] [doc] So `RUN` steps can reach every service on the loopback of the builder host unless you isolate the daemon. [inference]

The project's own security boundary (`PROJECT.md`, tag `v0.35.0`, lines 133 to 171):

- Line 139: the BuildKit API, with the default daemon configuration, cannot change the host filesystem. It cannot read the host filesystem outside the BuildKit state directory.
- Line 140: application containers must not "read or write to the host system, run privileged system calls, or access external devices directly".
- Line 144: the untrusted **daemon** cannot read client files that the client did not list. The project protects a client from a bad daemon.
- Line 167: "Multiple concurrent builds from separate client share their build resources without namespacing." The text advises "multiple instances of buildkitd for each of the namespaces".
- Line 168: a manipulated `--cache-from` source can give a wrong cache match.
- Line 171: an untrusted frontend can run a container with a secret mounted and read the secret value.

The project also publishes advisories for the case "malicious client". Recent ones (GitHub advisories API for `moby/buildkit`, read 2026-11-18): [advisory]

| Date | CVE | Severity | Summary |
|---|---|---|---|
| 2026-11-03 | CVE-2026-121520 | medium | A malicious client could set an xattr on a file outside the state directory. Fixed in `v0.34.1`. The text says it affects "a build service accepting builds from untrusted users". |
| 2026-09-30 | CVE-2026-93318 | high | Cache poisoning through unchecked layer DiffIDs. Fixed in `v0.32.2`. The workaround: "Do not share BuildKit daemon cache between trusted and untrusted builds. Use isolated BuildKit daemons or ephemeral builders for untrusted image sources". |
| 2026-09-30 | CVE-2026-93321, -93322, -93319 | medium | A malformed LLB operation, a malformed `MergeOp` or a malicious frontend can crash the daemon. |
| 2026-09-30 | CVE-2026-93323 | medium | An oversized Dockerfile can exhaust daemon memory. |
| 2026-07-16 | CVE-2026-15789 | medium | A malicious client can bypass destination directory validation on local source upload. |
| 2026-06-24 | CVE-2026-61711 | low | A custom frontend can disable seccomp and AppArmor for the build container without the `security.insecure` entitlement. |

Plain reading: the daemon is a large attack surface for a hostile client. The project fixes such bugs, but it does not promise a safe multi-tenant build service. Run it as an isolated, disposable component. Do not let it hold anything that matters. [inference]

### 3. Secure a shared remote BuildKit for an untrusted client

What the project documents:

- Rootless mode: `rootlesskit buildkitd`. Limits: overlayfs needs kernel 5.11 or newer (or `fuse-overlayfs` on 4.18 and newer, `native` below). Network mode is always `network.host`. Source: `docs/rootless.md` lines 5 to 21. [doc]
- Isolate the network of the rootless daemon: `rootlesskit --net=gvisor-tap-vsock --copy-up=/etc --disable-host-loopback buildkitd` (`docs/rootless.md` lines 23 to 29). The flag `--disable-host-loopback` blocks the host loopback. That also blocks a proxy on the host loopback. [doc] [inference]
- The container image `moby/buildkit:rootless` runs as uid 1000 and maps uid 1000 to 0 inside `RUN` (`docs/rootless.md` lines 107 to 130). [doc]
- `--oci-worker-no-process-sandbox` stops `buildkitd` from making a new PID namespace and a new `/proc`. It is for rootless daemons inside a container. The doc says it "is discouraged" because `RUN` containers can `kill` (and possibly `ptrace`) other processes in the daemon container. The Kubernetes examples use it. Source: `docs/rootless.md` lines 97 to 105 and `docs/buildkitd.toml.md` lines 103 to 106. [doc]
- Docker flags for the rootless container: `seccomp=unconfined`, `apparmor=unconfined`, `systempaths=unconfined` (`docs/rootless.md` lines 67 to 95). `--privileged` is "almost safe for rootless" (line 80). [doc]
- Worker types: `oci` (runc, the default) and `containerd` (`README.md` lines 142 to 144). `buildkitd.toml.md` has `binary = ""` for another OCI runtime such as `crun` (lines 124 to 126). [doc]
- `proxyNetwork`: BuildKit can force `RUN` network traffic through its own HTTP(S) proxy. The default-network `RUN` step reaches only the proxy. "Applications that ... open raw TCP connections cannot bypass the proxy. That traffic is blocked instead of being captured." The proxy can use an upstream proxy from `HTTPS_PROXY` in the `buildkitd` environment. It does not cover the image resolver, Git and HTTP sources. It also says rootless workers "may behave like host networking". Source: `docs/proxy.md` lines 3 to 30, 96 to 106, 165 to 176. An advisory (CVE-2026-93315, medium, 2026-09-30) concerns cleanup of the proxy CA when a build changes its CA bundle. [doc] [advisory] I could not find the release that first shipped the feature. The feature is new, so treat it as less mature. [inference]
- The daemon resolver and pusher use `http.ProxyFromEnvironment` (`util/resolver/resolver.go` line 202). So base-image pulls and pushes by the daemon follow `HTTPS_PROXY`. [src]

Run `buildkitd` inside its own sandbox:

- **gVisor (`runsc`).** I found no official gVisor or BuildKit statement about running `buildkitd` in gVisor. gVisor documents Docker inside gVisor. It needs the flags `--net-raw` and `--allow-packet-socket-write`. It also needs a `tmpfs` at `/var/lib/docker`, because "gVisor currently requires `tmpfs` as an upper layer for `overlayfs`" (`g3doc/user_guide/tutorials/docker-in-gvisor.md` lines 13 to 17 and 73 to 76). [doc] A web search found third-party repositories that run rootless BuildKit under gVisor. I did not rely on them. UNVERIFIED. Your spike shows `buildah` with `--isolation=chroot --storage-driver=vfs` works in `runsc` with `SETUID`, `SETGID`, `SYS_CHROOT`, and `no-new-privileges` off, because `newuidmap` is setuid (`agent-image-build-system.md` lines 28 to 33). [repo] Rootless BuildKit also uses `newuidmap` through RootlessKit, so the same limits probably apply. [inference] The snapshotter in gVisor is probably `native`, because of the `tmpfs`-upper rule. [inference]
- **gVisor `host-uds`.** The flag has four values: none, open, create and all. `create` allows `bind(2)` of a Unix socket on the host path. Source: `runsc/config/config.go` lines 1073 to 1088. [src] A builder in `runsc` with `host-uds=create` can make a socket in a shared host folder. A second `runsc` container with `host-uds=open` can connect to it. [inference] You already plan two runtime entries (`podman-gvisor-caddy-sandbox.md` item N8g). [repo]
- **krun.** The kernel of libkrunfw `v5.6.4` (file `config-libkrunfw_x86_64`) has `CONFIG_USER_NS=y` (line 219), `CONFIG_OVERLAY_FS=y` (line 2216), `CONFIG_PID_NS`, `CONFIG_NET_NS`, `CONFIG_SECCOMP`, `CONFIG_CGROUPS`, `CONFIG_FUSE_FS` and `CONFIG_VIRTIO_FS`. [src] Rootless BuildKit has its kernel needs met. [inference] Your spike N1: native overlay works in the guest as non-root only on guest `tmpfs` or an ext4 loop image. A directory on virtiofs fails (`pivot_root` `EACCES`, or `dpkg` errors) because the libkrun virtiofs server runs each file call with the uid of the caller and no capabilities. [repo] The BuildKit state directory (`/home/user/.local/share/buildkit`) must therefore live on `tmpfs` or an ext4 loop image. [inference]
- **Rootless Podman container.** `moby/buildkit:rootless` in Podman. The README documents `podman-container://` for the client (`README.md` lines 785 to 793). [doc]
- BuildKit's own Kubernetes examples use `*.rootless.yaml` and recommend it "to minimize the chance of container breakout attacks" (`examples/kubernetes/README.md`). They use mTLS and `--oci-worker-no-process-sandbox`. [doc]

### 4. Network path from the sandbox to the builder

Your sandbox has `--network=none`. The only egress is `proxy.sock` to iron-proxy. [repo]

| Path | What it needs | Fit |
|---|---|---|
| `buildctl` over `tcp://` through `HTTPS_PROXY` | grpc-go uses HTTP CONNECT proxies by default. It reads `HTTPS_PROXY` and `NO_PROXY`. A CONNECT proxy over https is not supported (`Documentation/proxy.md` lines 1 to 12 in grpc-go). `buildctl` passes `host:port` to the default grpc dialer for `tcp://` (`client/client.go` lines 143 to 147), so it honors the variable. [doc] [src] | The tunnel is opaque only if the proxy does not end the TLS. iron-proxy does end it. See below. |
| `docker buildx` `remote` driver over `tcp://` | The driver dials with a plain `net.Dialer` and has no proxy code (`driver/remote/util/dialer_unix.go` line 11 and `driver/remote/driver.go` lines 130 to 160). It does not honor `HTTPS_PROXY`. [src] | Does not work through a proxy. |
| Unix socket from the host (the `build.sock` pattern) | One socket file in a mounted folder. Under gVisor, `host-uds=open`. Under krun, a host Unix socket gives `ECONNREFUSED` in the guest. [repo] | Works for gVisor. Not for krun. |
| Host bridge to a TCP builder | `systemd-socket-proxyd HOST:PORT` listens on a socket unit and forwards to a TCP address (`man/systemd-socket-proxyd.xml` lines 25 to 30 in systemd `main`). It is stock and your design already uses it for the proxy bridge. [doc] [repo] TLS stays end to end, because the bridge is a byte relay. [inference] | Works for gVisor. Two unit files, no code. |
| `buildx` or `buildctl` with `ssh://HOST` | The client runs `ssh -- HOST buildctl dial-stdio` (`client/connhelper/ssh/ssh.go` lines 25 to 40). It needs an `ssh` client and a key in the sandbox, and raw TCP to port 22. The SSH account has a shell on the builder unless you force the command in `authorized_keys`. [src] [inference] | iron-proxy passes HTTP and TLS only. SSH fails (`podman-gvisor-caddy-sandbox.md` line 257). [repo] |
| `docker-container://`, `podman-container://`, `nerdctl-container://` | The client runs `docker exec`, `podman exec` or `nerdctl exec` on the same host. [src] `client/connhelper/` | Needs a container engine socket in the sandbox. Rejected in your docs. |
| `kube-pod://` and the `kubernetes` driver | The client calls the Kubernetes API. It needs a role with `pods/exec` (`examples/kubernetes/README.md`). The `kubernetes` driver also creates Deployments (`drivers/kubernetes.md`). [doc] | A kubeconfig in the sandbox is a bigger credential than a build socket. |

**iron-proxy and mTLS.** The tunnel listener takes CONNECT and SOCKS5. "After the CONNECT or SOCKS5 handshake, the proxy peeks at the first byte". For TLS (byte `0x16`) it "performs MITM the same way as the HTTPS listener, generating a leaf cert on the fly" (`README.md` lines 733 to 737). The only "passthrough" setting is for DNS (`README.md` lines 238 and 290). [doc] So the client would see a leaf certificate that your iron-proxy CA signed, not the `buildkitd` certificate. The client certificate would stop at the proxy. This matches your own note in `spiffe-identity-podman-sandbox.md` lines 66 to 72. [repo] Result: remote mTLS through iron-proxy does not work today. [inference]

An untested route fits your design. End TLS at a gateway in front of `buildkitd`. Let iron-proxy swap a placeholder token for a real bearer token. The gRPC method names are `/moby.buildkit.v1.Control/Solve` and `/moby.buildkit.v1.Control/Session` (`api/services/control/control.proto`). iron-proxy has path rules for host, methods and paths (`README.md` lines 386 and 418). The README mentions gRPC only in a retry note (lines 314 to 315). I found no statement that iron-proxy supports long bidirectional gRPC streams. UNVERIFIED. The gateway needs its own token check (Envoy or agentgateway). `buildkitd` has none. See the TODO in "How this works for you".

iron-proxy `v0.57.0` has an optional SSH listener. It needs an external "authorizer" service (`internal/sshproxy/README.md`). That is custom code. I did not follow this further. [doc]

### 5. Build output, registry and credentials

Output (all [doc], `README.md`):

- Push directly from the daemon: `--output type=image,name=REGISTRY/IMAGE:TAG,push=true` (lines 267 to 309). No image data returns to the client.
- Export to the client: `--output type=oci,dest=out.tar` or `type=oci > out.tar` (lines 430 to 436), or `type=docker,name=IMG | docker load` (lines 423 to 426). For Podman, the README shows `... --output type=oci | podman load foo` (line 790).
- Local files: `--output type=local,dest=DIR` (line 319).
- With no `--output`, "the build result and intermediate cache will only remain internally in BuildKit" (line 269).
- Build context: `--local context=.` sends the files from the client to the daemon (line 245). So the context upload to `REGISTRY/build-context` and the host `crane export` step are not needed. [doc] [inference]

Credentials:

- `buildkitd.toml` has no registry credential setting. A search of `cmd/buildkitd/config/config.go` for `password`, `username` and `auth` finds only `SessionAuthTimeout`. [src] The daemon takes registry credentials from the client session.
- `buildctl` always loads the Docker config file and adds an auth provider to the session. `cmd/buildctl/build.go` lines 190 to 199. The README says "`buildctl` will attempt to read Docker configuration file `$DOCKER_CONFIG/config.json`" (lines 316 to 317). [src] [doc]
- Default flow: "registry credentials are not shared with BuildKit daemon, and short-lived token is generated on client side instead." The daemon can ask for the credentials instead. This "is always required for basic auth". The client logs it, with no confirmation (`PROJECT.md` line 170). [doc] The code that answers the request is `Credentials` in `session/auth/authprovider/authprovider.go` line 263, and the logged line is `[auth] sharing credentials for HOST`. [src]
- The token request runs in the client. The client calls the registry token endpoint with the Docker config credentials (`authprovider.go` lines 144 to 202). The HTTP client of the Go standard library reads `HTTPS_PROXY`. [src] [inference] So with a token registry (for example `ghcr.io`), the sandbox could request the token through iron-proxy. The proxy would swap the placeholder. The sandbox would receive a short-lived bearer token, never the real token. The daemon would then push with that bearer token. UNVERIFIED for `ghcr.io`.
- With a basic-auth registry, the daemon asks the client for the credentials. The sandbox would send the placeholder to the daemon. The daemon would send the placeholder to the registry, outside the swap. That fails. [inference]
- Risk: the credentials in the session, and any `--secret` or `--ssh` value, go to the daemon. An untrusted frontend can read build secrets (`PROJECT.md` line 171). Keep only the placeholder and short-lived tokens in the sandbox. Keep the real token on the proxy. [doc] [inference]

Cache:

- `--export-cache type=registry,ref=...` and `--import-cache type=registry,ref=...` (`README.md` lines 465 to 520). A manipulated `--cache-from` can give a wrong cache match (`PROJECT.md` line 168). [doc]
- A shared daemon shares its cache between all clients (`PROJECT.md` line 167). CVE-2026-93318 shows a real cache-poisoning attack. Use one daemon for the agent only. [advisory]

### 6. How a harness calls it

- A plain shell command is enough: `buildctl --addr unix:///run/sandbox/proxy/buildkit.sock build --frontend=dockerfile.v0 --local context=. --local dockerfile=. --output type=image,name=...,push=true`. `BUILDKIT_HOST` sets the address (`README.md` lines 777 to 778). The harness needs no tool plugin. [doc]
- I found no BuildKit MCP server. A search restricted to `github.com` returned only Buildkite MCP servers, which are for a different product (CI). Lower confidence: one search only. You do not need one. [inference]
- Claude Code in a sandbox can run `buildctl` as any other command. `buildctl` runs inside your sandbox and needs only a socket. This differs from `docker` and `podman`, which your merged handoff says do not work in the Anthropic sandbox (`podman-sandbox-merged.md` line 85). [repo]

### 7. Existing build services (facts only)

| Service | Kind | Trust and network requirements (from official docs) |
|---|---|---|
| `kubernetes` driver of Buildx | Self-hosted. Buildx creates BuildKit Deployments or StatefulSets in your cluster. | The client needs Kubernetes API access. Options include `rootless`, `serviceaccount` and `persistent-volume-claim.requests.storage` (`drivers/kubernetes.md`). [doc] |
| BuildKit Kubernetes manifests | Self-hosted. `Pod`, `Deployment` with `Service`, `StatefulSet`, `Job`, with `privileged`, `rootless` and `userns` variants. mTLS with `create-certs.sh`. | `examples/kubernetes/README.md` at `v0.35.0`. [doc] |
| Helm chart for BuildKit | I found no official chart in `moby/buildkit` at `v0.35.0`. The repo lists manifests only. UNVERIFIED for third-party charts. | - |
| Docker Build Cloud (`cloud` driver) | SaaS. Needs Buildx `v0.37.0` or newer and a Docker account. Each builder is "completely isolated to a single Amazon EC2 instance", in US East only. | The firewall must allow `3.211.38.21`, `auth.docker.io`, `build-cloud.docker.com` and `hub.docker.com` (`build-cloud/setup.md` lines 91 to 99 and `_index.md` lines 44 to 50). A raw IP address is in the list, so it is not only HTTPS by host name. [doc] |
| Depot | SaaS. `depot build` or a Docker CLI plugin. Builders are ephemeral EC2 instances running "an optimized version of BuildKit". | "The CLI requests a builder from the Depot API ... The API returns mTLS certificates, and the CLI then directly connect[s] to the builder instance." So it needs direct mTLS to the builder, like point 5. Firewall rules are not on the page I read (`depot.dev/docs/container-builds/overview`). [doc] |

Both SaaS options are an outward dependency with a paid plan and an account token. The account token that starts a build is a credential in the sandbox. [inference]

### 8. How this fits krun and gVisor

For each design: (a) where the client runs, (b) where `buildkitd` runs, (c) what changes versus `build.sock`, (d) what it gives up.

**gVisor (the current design).**

- Remote TCP builder (B).
  - (a) `buildctl` in the sandbox, with `--addr unix:///run/sandbox/proxy/buildkit.sock`.
  - (b) `buildkitd` on another host or a k3s pod, with mTLS.
  - (c) The Go listener, `crane` and the context registry are replaced by two stock units: `buildkit-bridge.socket` and `buildkit-bridge.service` that run `systemd-socket-proxyd BUILDER:1234`. The TLS client key lives on the sandbox side, or you end TLS in the bridge with `socat OPENSSL:` (stock) and keep the key on the host. [inference]
  - (d) The agent has code execution on the builder. The builder needs its own isolation and its own egress control. You lose the per-build ephemeral container, the input checks and the 64 MB limit. You gain cache, parallel builds and no listener code.
- Local sibling builder (F, new here).
  - (a) `buildctl` in the sandbox.
  - (b) `moby/buildkit` rootless in a second `runsc` container with `--network=none`, no host listener.
  - (c) No host process at all. The builder container makes the socket in a shared folder.
  - (d) You depend on BuildKit working in `runsc`. UNVERIFIED. The builder also needs an egress path, which needs a relay such as `socat` (a derived image) or a shared network namespace. UNVERIFIED.

**krun (a microVM guest, own kernel).**

- Remote builder.
  - (a) `buildctl` in the guest.
  - (b) A remote host.
  - (c) A host Unix socket does not work in the guest, so the bridge pattern is gone. The guest needs a TCP route. With `--network=none` it has no route to the host loopback. With `pasta` it reaches the internet and not the host loopback. With `pasta --map-host-loopback` it reaches the proxy and also keeps the internet open. [repo] The libkrun security model says that TSI calls "use the VMM's host network context". It tells you to run the VMM in a dedicated network namespace (`docs/security-model.md`). [doc]
  - (d) You must write an egress rule that allows one `HOST:PORT` for the VMM uid and nothing else. A user-scope `IPAddressDeny=` does nothing in a user manager. A `nft` rule by uid works (your gVisor design uses one). [repo] This is the "network wall" that made krun complex. Your lessons say the same: "With Podman and krun the proxy is a separate part, and the network wall becomes the complex part." (`podman-plain-sandbox.md` line 154). [repo]
- `buildkitd` inside the sandbox guest (D).
  - (a) and (b) both in the guest. `buildctl` talks to a Unix socket in the guest.
  - (c) No `build.sock`, no listener, no bridge, no second network path. The only egress stays the proxy.
  - (d) Spike N1 shows nested Podman works in the guest as non-root with native overlay, if the storage is on `tmpfs` or an ext4 loop image. [repo] The kernel has the needed options. [src] Rootless BuildKit is not tested. UNVERIFIED. The guest has full capabilities and no seccomp, and an agent that runs as guest root can do what a build does anyway. So the build adds no new power inside the VM. [inference] But the agent and the `RUN` steps share one VM. A malicious `RUN` step is as strong as the agent. The VM is the only boundary. The build cache is also inside the sandbox. You also keep every krun cost your docs list: no `podman exec`, no native SPIFFE identity, and the host loopback problem for the proxy. [repo]

## Comparison

Rows A to E are the options you named. Row F is the extra option from this research.

| Option | Custom code | What an attacker in the sandbox can do on the builder | Network allowance | Credential exposure | Works with krun | Works with gVisor | Maturity |
|---|---|---|---|---|---|---|---|
| A. `build.sock` and the Go listener | A Go listener (about nine steps), a contract, checks, tests | Can send one checked request. Cannot choose the `RUN` steps beyond the context. Builder is a new disposable `runsc` container. | A host Unix socket. None for the builder yet. | Registry token swapped by the proxy. Push not tested. | No. A host Unix socket gives `ECONNREFUSED` in the guest. [repo] | Yes (current design). | Code not written yet. Contract is clear. |
| B. Remote `buildkitd` over mTLS on TCP | None for the daemon. Two stock units if you bridge. Certificates with `openssl`. | Run any `RUN` step on the builder. Reach what the builder network reaches. Prune the shared cache. Send crafted LLB to the daemon (see advisories). | One `HOST:PORT` for gVisor (bridge). For krun, a TCP route plus a firewall rule. The iron-proxy tunnel does not work (MITM). | The client key and cert in the sandbox. Registry token goes to the daemon. | Only with a route and a uid firewall rule. | Yes, with a bridge. | BuildKit `v0.35.0` is mature. The untrusted-client use is not a documented target. |
| C. Remote `buildkitd` over the `buildx` `ssh://` driver | None. Needs an `ssh` client and a key in the sandbox. | An SSH shell on the builder, unless you force `command=` (inference). Same `RUN` power as B. | TCP 22 to the builder. iron-proxy cannot pass SSH. | SSH key in the sandbox. | Only with a TCP route. | Only with a TCP bridge to port 22 and an SSH client. | The helper is in BuildKit. Weak fit. |
| D. `buildkitd` inside the sandbox (rootless in the krun guest, or in gVisor) | None for the daemon | Runs `RUN` steps in the same VM as the agent. In krun the VM is the boundary. In gVisor the sentry is the boundary, and the agent would need the caps for `newuidmap`. | None new. The proxy stays the only egress. | Same as today. | Likely yes. UNVERIFIED. Kernel options exist. Storage must be `tmpfs` or ext4 loop. | The sandbox would need `SETUID`, `SETGID`, `SYS_CHROOT` and a writable root, which your design removed on purpose. | BuildKit rootless is documented. Neither combination is tested. |
| E. Hosted builder (Depot, Docker Build Cloud) | None | Runs `RUN` steps on the vendor fleet. Isolation per project or builder (vendor claim). | Direct mTLS to the vendor. Docker lists an IP address. The tunnel does not work (MITM). | A vendor account token. | Only with a TCP route. | Yes, with a bridge. | SaaS. Mature. Outward dependency. |
| F. Stock `buildkitd` as a sibling `runsc` container, shared socket folder (new) | None for the daemon. A derived image if you need a `socat` relay. | Runs `RUN` steps in a gVisor builder with no network or proxy-only egress. Limited to what that container can reach. | None new for the sandbox. Builder egress is a separate decision. | No registry token in the sandbox if the builder pushes through the proxy. Placeholder problem in point 5. | No (needs a host Unix socket). | Yes if BuildKit runs in `runsc`. UNVERIFIED. | BuildKit is mature. The `runsc` combination has no source. |

## How this works for you

### Recommendation

Stay on gVisor. Do not go back to krun for the sake of the builder. Replace the Go listener with stock `buildkitd` that runs as a sibling builder container (row F), and share its Unix socket with the sandbox. Treat a remote TCP builder (row B) as the later "scale" step on k3s or EKS.

Reasons:

- Your goal is no custom code. Row F needs none for the daemon. It removes the listener, the contract, the checks, `crane`, the context registry, the 64 MB limit and the `build.just` change. [inference]
- It keeps the `runsc` wall that you already chose. The builder has no network, as the sandbox has none. [repo]
- It avoids the krun network wall. A remote builder under krun needs a TCP route and a firewall rule, which is the cost you rejected on 2026-11-09. [repo]
- `buildkitd` has no authorization. A remote builder with mTLS gives every holder of the client key code execution on the builder. In your threat model the agent is hostile and holds that key. So the builder must be disposable, hold no secret and have its own egress control. That is a second sandbox. Row F makes it the same kind of sandbox that you already run. [inference]

Plain statements about your premise:

- "A remote sandboxed BuildKit that podman inside the sandbox can use" does not exist. `podman` cannot talk to BuildKit. The sandbox needs `buildctl`. [src]
- Your handoff says "The agent never holds a build capability" (`agent-image-build-system.md` line 16). With BuildKit, the agent holds no Linux capability. It does hold the authority to run any build on the builder. That is a different power. Decide if this is acceptable. [repo]
- With a persistent daemon you lose the "fresh container for each build". Cache and daemon live across builds. To keep one builder per build, run `buildctl-daemonless.sh` in a per-build container (`README.md` lines 809 to 844). That needs a launcher again. [doc] [inference]
- Krun is only a good fit for option D. Under krun, a remote builder brings back the network wall. [repo]

### Minimum viable setup (stock tools only)

Spike 1 is the lowest risk. It uses BuildKit's own example units on the host. It proves the client path, the Unix socket in gVisor and the output flow. It gives a weaker wall than row F, because the daemon runs as your host user.

Files from BuildKit `v0.35.0` (`examples/systemd/user/`): `buildkit.service`, `buildkit-proxy.socket`, `buildkit-proxy.service`. Change the socket path so that the sandbox can mount it:

```ini
# ~/.config/systemd/user/buildkit-proxy.socket (from examples/systemd/user)
[Socket]
ListenStream=%t/sandbox/buildkit.sock
SocketMode=0600
```

The daemon unit runs `rootlesskit --net=slirp4netns --copy-up=/etc --disable-host-loopback buildkitd --addr unix://%t/buildkit/rootless` (from the example). Install `buildkitd` and `buildctl` from the release tarball. Check the host with `newuidmap`, `/etc/subuid` and a kernel of 5.11 or newer.

In the sandbox image, add only `buildctl` (release tarball, pin the version and the sigstore bundle). Then run:

```sh
buildctl --addr unix:///run/sandbox/proxy/buildkit.sock build \
  --frontend=dockerfile.v0 --local context=. --local dockerfile=. \
  --output type=oci,dest=/tmp/out.tar
```

Spike 2 is the target (row F). Outline only. I did not run it. The image tag and the flags need a check.

```sh
# Builder container. runsc-builder is a second runtime entry with host-uds=create.
podman run -d --name sandbox-builder --runtime runsc-builder --network=none \
  --user 1000 --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID --cap-add=SYS_CHROOT \
  --volume sandbox-buildkit-state:/home/user/.local/share/buildkit \
  --volume "$XDG_RUNTIME_DIR/sandbox/buildkit:/run/buildkit" \
  docker.io/moby/buildkit@sha256:<DIGEST-OF-v0.35.0-rootless> \
  --addr unix:///run/buildkit/buildkitd.sock \
  --oci-worker-no-process-sandbox --oci-worker-snapshotter=native
```

The sandbox mounts `$XDG_RUNTIME_DIR/sandbox/buildkit` read-only at `/run/sandbox/buildkit` and uses `host-uds=open`, as it does for `proxy.sock`. It runs `buildctl --addr unix:///run/sandbox/buildkit/buildkitd.sock`. Pin the builder image by digest. For builder egress, set `HTTPS_PROXY` for `buildkitd` to a relay that reaches iron-proxy, and decide between `proxyNetwork = true` and `RUN --network=none`. Registry secrets: use `GHCR_PUSH_TOKEN` by name only. The proxy holds the value.

Later, for a remote builder (row B), use the README commands with certificates from `examples/kubernetes/create-certs.sh`:

```sh
buildkitd --addr tcp://0.0.0.0:1234 --tlscacert ca.pem --tlscert cert.pem --tlskey key.pem
buildctl --addr tcp://BUILDER:1234 --tlscacert ca.pem --tlscert clientcert.pem --tlskey clientkey.pem build ...
```

Run it behind a host bridge (`systemd-socket-proxyd BUILDER:1234`). Never expose TCP without `--tlscacert`.

### Open questions and spikes, each with a check

1. **Does the client path work in your gVisor sandbox?** Run spike 1.
   - check: `buildctl debug workers` lists a worker as the user `agent`. A build with a `RUN` step ends with exit 0. A second user on the host cannot open the socket.
2. **Does `buildkitd` run in `runsc` (row F)?** Run spike 2 in a renamed container.
   - check: `buildctl debug workers` lists a worker. A `RUN apk add` build passes with `no-new-privileges` on or off. Record which of the three capabilities it needs. If `newuidmap` fails, test `no-new-privileges=false` as in your buildah spike.
3. **Which snapshotter works in `runsc`?**
   - check: a build with `--oci-worker-snapshotter=native` passes. Try `overlayfs` and record the error text.
4. **Builder egress.** `buildkitd` and `RUN` steps need the proxy. The proxy is on the host loopback. A relay needs `socat`.
   - check: a base-image pull from the allowed host passes through iron-proxy. A pull from a host that is not allowed gets 403. A `RUN wget https://example.com` step fails or goes through the proxy, never direct.
   - TODO: test `proxyNetwork = true` with `HTTPS_PROXY` for the daemon. The check is the audit log of iron-proxy for the two hops. The feature is new (`docs/proxy.md`, CVE-2026-93315).
5. **Registry push with no real token in the sandbox.**
   - check: `buildctl ... push=true` to `ghcr.io` works, `env` in the sandbox holds only the placeholder, and the proxy audit log shows the swap. A push to a path outside `/v2/raghav19/sandbox-builds/**` gets 403. If the basic-auth case fails, use `--output type=oci` and push from the sandbox through the proxy.
6. **Build context size and symlinks.** BuildKit streams the context from the client.
   - check: a context with an absolute symlink and a 100 MB file builds with no host file read. The advisories on local source upload give the risk class.
7. **Daemon hardening.** The daemon is exposed to a hostile client.
   - check: `buildkitd` is `v0.35.0` or newer (all 2026 advisories listed here are fixed in `v0.34.1` or `v0.32.2` and later). The builder holds no secret. Its state volume is on a named volume that you can remove. `buildctl prune` from the sandbox only affects the agent's own cache.
8. **krun with `buildkitd` in the guest (option D).** Only if you want krun for other reasons.
   - check: in the krun guest, `rootlesskit buildkitd` runs as `agent` with the state directory on `tmpfs` or the ext4 loop image. A `RUN apt-get` build passes. The same build fails when the state directory is on virtiofs. This repeats your N1 finding.
9. **A remote builder through iron-proxy.**
   - TODO: test a gateway (Envoy or agentgateway) in front of `buildkitd` with a JWT check, and `buildctl --addr tcp://GATEWAY:443 --tlscacert <iron-proxy-ca>` through `HTTPS_PROXY`. Check: `buildctl debug workers` works, a build with a `RUN` step finishes, a missing token gets 401, and the iron-proxy audit log shows `/moby.buildkit.v1.Control/Session` with a swapped token. The risk is long bidirectional gRPC streams through the MITM path. This approach may fit your design better than a TCP bridge, and nobody tested it.
10. **A dedicated host user for the builder.** Your gVisor handoff lists this as open decision 1. A sentry escape from the builder reaches the host user that runs it.
    - check: the builder `runsc` process runs as a user that owns no other data.

## Spike results

I ran these tests on the host of the owner on 2026-11-18. Versions: Podman 6.1.4, `runsc` release-20261102.0, `moby/buildkit:v0.35.0-rootless`. The builder was a rootless container with the runtime `runsc-builder` (`ignore-cgroups`, `network=none`, `host-uds=create`). The client was a second `runsc` container with `host-uds=open`. [repo]

| Test | Result |
|---|---|
| `buildkitd` in `runsc` with `tmpfs` state, `--oci-worker-no-process-sandbox` and the native snapshotter | It runs. `buildctl debug workers` lists one worker. |
| Capabilities | `SETUID`, `SETGID` and `SYS_CHROOT` are enough. |
| `no-new-privileges` on | `rootlesskit` hangs. No log and no socket. Keep it off for the builder. |
| Socket folder owned by the host user | `buildkitd` fails with `permission denied`. The folder must belong to the subuid of the container user 1000. `podman unshare chown 1000:1000` does this. |
| The socket in the shared host folder | `buildkitd` makes it. The client in a second `runsc` container connects through a read-only mount. |
| A build with `COPY` and a build with a `RUN` step | Both pass with `--output type=oci,dest=...`. The tar arrives in the client. The base image came from `--oci-layout`, because the builder has no network. |
| A stop and a start | `buildkitd` removes the socket at a stop. A restart does not need a clean-up of the socket. |
| `sandbox.service` with `Requires=` and `After=` | A start of the sandbox starts the builder. A restart gives a new builder container. A stop removes it. |
| Exit code on stop | `buildkitd` exits with code 1 for SIGTERM and for SIGINT. systemd shows the unit as `failed` after a stop. |
| A runtime name with a relative path (`runsc-builder = ["runsc"]`) | Podman says the runtime is not found. Use the full path. |

Not tested yet:

- A `FROM` pull through iron-proxy.
- A push to a registry.
- The `socat` relay for the builder.
- `network=none` for the sandbox container.
- `buildctl` in the real sandbox image.

## What was not found

- No official gVisor or BuildKit statement about running `buildkitd` in `runsc`. A web search for `google/gvisor` issues with "buildkit" found no issue about BuildKit itself. It found third-party repositories only. I did not use them as evidence.
- No official statement about running `buildkitd` in a libkrun microVM. I found only the kernel options in the `libkrunfw` config and your own spike N1.
- No official Helm chart for BuildKit in `moby/buildkit` at `v0.35.0`.
- No maintained MCP server for BuildKit or `buildctl` (one search, `github.com` only).
- No firewall or proxy requirement page for Depot in the page I read.
- No statement that iron-proxy supports long gRPC streams, or a per-host TLS passthrough for the tunnel listener.
- No test of BuildKit `proxyNetwork` with an upstream proxy. I read only the documentation.
- The tag name of the rootless image (`moby/buildkit:v0.35.0-rootless`) is not verified. The README names `moby/buildkit:rootless` and `moby/buildkit:master-rootless` (lines 773 to 775).
- The mise package name for `buildctl` and `buildkitd` is not verified. The aqua registry has a `moby/buildkit` entry that installs `buildctl` only (`pkgs/moby/buildkit/registry.yaml`). Check `buildkitd` separately.

## Sources

- https://github.com/moby/buildkit/blob/v0.35.0/README.md (lines 117 to 152, 195 to 320, 423 to 520, 732 to 845)
- https://github.com/moby/buildkit/blob/v0.35.0/PROJECT.md (lines 133 to 171, "Security boundary")
- https://github.com/moby/buildkit/blob/v0.35.0/.github/SECURITY.md
- https://github.com/moby/buildkit/blob/v0.35.0/docs/rootless.md
- https://github.com/moby/buildkit/blob/v0.35.0/docs/buildkitd.toml.md
- https://github.com/moby/buildkit/blob/v0.35.0/docs/proxy.md
- https://github.com/moby/buildkit/blob/v0.35.0/cmd/buildkitd/main.go (lines 232 to 237, 365, 432 to 448, 722, 775 to 856)
- https://github.com/moby/buildkit/blob/v0.35.0/cmd/buildctl/build.go (lines 190 to 199)
- https://github.com/moby/buildkit/blob/v0.35.0/client/client.go (lines 43 to 160, 306 to 336)
- https://github.com/moby/buildkit/blob/v0.35.0/client/connhelper/ssh/ssh.go
- https://github.com/moby/buildkit/blob/v0.35.0/util/network/netproviders/network.go and `network_unix.go`
- https://github.com/moby/buildkit/blob/v0.35.0/util/resolver/resolver.go (line 202)
- https://github.com/moby/buildkit/blob/v0.35.0/session/auth/authprovider/authprovider.go
- https://github.com/moby/buildkit/blob/v0.35.0/api/services/control/control.proto
- https://github.com/moby/buildkit/tree/v0.35.0/examples/kubernetes (README and manifests)
- https://github.com/moby/buildkit/tree/v0.35.0/examples/systemd/user
- https://github.com/moby/buildkit/releases/tag/v0.35.0 (assets `buildkit-v0.35.0.linux-*.tar.gz` and `.sigstore.json`)
- https://github.com/moby/buildkit/security/advisories (GHSA-w26x-xg27-7qjc, GHSA-f2v9-hprr-32q3, GHSA-2f5p-x9ph-g97x, GHSA-7236-3392-c5c6, read through the GitHub API on 2026-11-18)
- https://github.com/docker/buildx/tree/v0.39.0/driver/remote (`factory.go`, `driver.go`, `util/dialer_unix.go`, `util/endpoint.go`)
- https://github.com/docker/docs/blob/main/content/manuals/build/builders/drivers/remote.md, `kubernetes.md`, `cloud.md`, `_index.md`
- https://github.com/docker/docs/blob/main/content/manuals/build-cloud/_index.md and `setup.md`
- https://depot.dev/docs/container-builds/overview (vendor documentation)
- https://github.com/containers/podman/blob/v6.2.0/docs/source/markdown/podman-build.1.md.in and `podman-remote.1.md`
- https://github.com/containers/podman/blob/v6.2.0/pkg/api/server/register_images.go and `pkg/bindings/images/build.go`
- https://github.com/containers/buildah/blob/v1.46.1/imagebuildah/stage_executor.go
- https://github.com/containerd/nerdctl/blob/v2.4.2/docs/command-reference.md
- https://github.com/google/gvisor/blob/release-20261116.0/g3doc/user_guide/tutorials/docker-in-gvisor.md
- https://github.com/google/gvisor/blob/release-20261116.0/g3doc/user_guide/rootless.md
- https://github.com/google/gvisor/blob/release-20261116.0/runsc/config/config.go (lines 1073 to 1088)
- https://github.com/containers/libkrun/blob/main/docs/security-model.md and `networking.md` (main at `b7925e4`)
- https://github.com/containers/libkrunfw/blob/v5.6.4/config-libkrunfw_x86_64
- https://github.com/containers/crun/blob/1.31/src/libcrun/handlers/krun.c
- https://github.com/ironsh/iron-proxy/blob/main/README.md (commit `d303dcd`, lines 314, 386, 418, 710 to 745) and `internal/sshproxy/README.md`
- https://github.com/grpc/grpc-go/blob/master/Documentation/proxy.md
- https://github.com/systemd/systemd/blob/main/man/systemd-socket-proxyd.xml
- https://github.com/aquaproj/aqua-registry/blob/main/pkgs/moby/buildkit/registry.yaml
- In this repo: `docs/handoff/go-build-socket-listener.md`, `agent-image-build-system.md`, `podman-krun-sandbox.md`, `podman-gvisor-sandbox.md`, `podman-plain-sandbox.md`, `podman-sandbox-merged.md`, `spiffe-identity-podman-sandbox.md`, `agent-microsandbox-handoff.md`, `agent-sandbox-iron-proxy-handoff.md`, and `docs/research/podman-gvisor-caddy-sandbox.md`.
- Local clones, not kept in the repo: BuildKit `v0.35.0`, Buildx `v0.39.0`, Podman `v6.2.0`, Buildah `v1.46.1` and iron-proxy `main` under the session scratchpad.
