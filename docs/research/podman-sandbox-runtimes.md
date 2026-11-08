# Podman sandbox runtimes: krun, gVisor and Docker

Question: Can one Compose file replace the msb microVM? The first design had a rootless Podman sandbox container in gVisor (`runsc`) and a Caddy container as the only egress path. The spikes of 2026-11-08 tested three runtimes (Podman with `krun`, Podman with gVisor, Docker with gVisor) and iron-proxy as the egress proxy. The section "Update of 2026-11-08" has the results and the plan. The sections below it are the first research, before the spikes. The handoff is `docs/handoff/podman-krun-sandbox.md`. The configs and scripts of the spikes are in `docs/research/podman-sandbox-spikes/`.

Source: Primary sources only. gVisor tag `release-20261102.0` (source and `g3doc/`). Podman tag `v6.1.4` (source, docs, release notes). `containers/container-libs` `main` at `39ea91d`. Netavark and aardvark-dns `v2.1.0`. Caddy tag `v2.11.9` (source) and `caddyserver/website` `main` at `6b06285` (docs). `caddyserver/forwardproxy` `master` at `0aab84d` (last tag `1.0.1` is from 2019). `mholt/caddy-l4` `v0.1.2`. SPIRE `v1.16.0` (released 2026-11-05). `spiffe-helper` `v0.12.3`. crun `1.30.1`. libkrun `main` at `2fc56b5`. Kata `4.3.1`. `podman-compose` `v1.6.0`. `docker/compose` `v5.7.0`. `compose-spec` `main` at `3a4a699`. cosign `v3.1.4`. ORAS docs `1.3`. Flux CLI `v2.10.0`. Research date: 2026-11-08. Local repo state: `main` at `b257a19`.

Evidence tags: **[repo]** is a file in this repo. **[doc]** is an official documentation page. **[src]** is source code at the tag above. **[spec]** is a specification. **[issue]** is a GitHub issue or pull request. **[secondary]** is a blog or forum post. I use none as proof. **[inference]** is my own conclusion. **[spike]** is a test result. No spike ran (see "Not tested").

Host state, read with `command -v` and `podman info` on 2026-11-08 [repo]: Podman 6.1.4, runc 1.5.2, conmon 2.2.1, pasta 2026_10_02, netavark 2.1.0, aardvark-dns 2.1.0. Cgroup v2 with the systemd manager. No SELinux. `/dev/kvm` is mode 0666. `/etc/subuid` gives user `rana` 1441792 IDs. `newuidmap` exists. The user unit `podman.socket` is active. The default OCI runtime is runc. These tools are absent: `runsc`, `caddy`, `crun`, `krun`, `cosign`, `oras`, `spire-agent`. `flux` and `bws` come from mise.

## Update of 2026-11-08: spike results and revised verdict

Five spikes ran on the host on 2026-11-08. This section replaces the verdict and the plan below where they differ. The sections below stay as the background and the source list.

Versions in the spikes: Podman 6.1.4, `crun` 1.30.1 (Arch package), `podman-compose` 1.6.0, iron-proxy 0.56.0, SPIRE 1.16.0, cosign 3.1.4, oras 1.3.6, `registry:3`. All spikes used fake secrets. No spike called a real API. Evidence tags: **[spike-A]** `krun`. **[spike-B]** iron-proxy. **[spike-C]** hardening, mounts, volumes. **[spike-D]** SPIRE. **[spike-E]** artifact and signing. The raw result files were in the session scratchpad, which is temporary.

Host state change: the Arch `crun` 1.30.1 package shows `+LIBKRUN`. The text below that says "no `krun`" is out of date. `krun` is a symlink to `/usr/bin/crun`. The `libkrun` 1.19.6 and `libkrunfw` 5.6.2 packages are installed. `crun` loads `libkrun.so` with `dlopen` at run time. Keep both packages. [spike-A] [src] `krun.c:970`

### Revised verdict

Items 1, 5 and 6 changed after spikes G1 and G2. See "Runtime decision after spikes G1 and G2" below. Items 6 and 7 are closed by spikes N1 and N2. See "Results of spikes N1 and N2" below.

1. **Overall: feasible with changes.** Use rootless Podman with the `krun` runtime for the sandbox. Run iron-proxy in its own container as the only way out. Drop gVisor and Caddy.
2. **`krun` works rootless with no root install.** The guest kernel is 6.12.109. The host kernel is 7.2.15. A cold start takes about 0.85 s. Plain `crun` takes about 0.43 s. [spike-A]
3. **The egress wall holds under `krun`.** On an `--internal` network the guest has no `eth0` and no default route. `wget https://1.1.1.1` fails. A sibling container is reachable by name and by IP. [spike-A] [spike-B]
4. **iron-proxy passes every egress, swap, rotation and streaming test.** The tests used fake secrets and a local upstream. Real hosts and real tokens are not tested. [spike-B]
5. **The sandbox gets no SPIFFE identity.** A mounted host Unix socket gives `ECONNREFUSED` in a `krun` guest. Plain `crun` connects. The built-in SPIRE `docker` attestor works for `crun` containers, so the host and the proxy can hold identities. [spike-A] [spike-D]
6. **Blocker: nested Podman as the non-root `agent` user fails in the `krun` guest.** The error is `setting up pivot dir ... permission denied`. As guest root it works with `overlay` and `vfs`. The current sandbox runs Podman as `agent`. The cause is not found. [spike-A]
7. **Conflict to resolve: `--userns=auto` and `keep-id`.** The proxy needs `keep-id` to read a host-owned `ca.key`. `--userns=auto` fails while any `keep-id` container exists in the store, also a stopped one. The subuid range is large enough. [spike-B] [spike-C]
8. **Podman cannot be the signature gate.** Podman 6.1.4 rejects cosign v3 signatures. The host gate is a script: `cosign verify` and a pinned digest. [spike-E]
9. **Limits you must accept.** iron-proxy passes HTTP and TLS only, so no SSH and no raw TCP. Use https git remotes. Each tool must trust the proxy CA. There is no disk quota on btrfs. Hardening flags confine the VMM only, not the guest. [spike-B] [spike-C] [spike-A]
10. **Supply chain of iron-proxy is weak.** The releases 0.50 to 0.56 publish no signature. The image binary equals the release binary. Pin the image by digest. [spike-B]

### Runtime decision after spikes G1 and G2 (gVisor)

Two more spikes ran with `runsc` release-20261102.0. **[spike-G1]** is rootless Podman with gVisor and iron-proxy. **[spike-G2]** is the SPIRE identity of a gVisor sandbox. They change items 1, 5 and 6 of the revised verdict above.

1. **Podman with `runsc` and Podman with `krun` are both feasible.** Choose gVisor if the sandbox needs a native SVID. Choose `krun` if you need resource limits and a real guest kernel.
2. **gVisor meets the identity condition, with conditions.** The SPIRE 1.16.0 `docker` attestor with `use_rootless_podman = true` gives a `runsc` sandbox a native SVID. It needs no custom plugin and no Delegated Identity API. It needs `host-uds=open` and a start wrapper (see below). [spike-G2]
3. **Nested Podman works under gVisor as non-root, with a reduced setup.** Builds work with `--isolation=chroot --network=host`. Nested `podman run` needs `allow-suid`, `--storage-driver vfs`, `--network=host` and `--cgroups=disabled`. [spike-G1]

#### Results of spike G1: gVisor with iron-proxy

| Item | Result | Evidence |
|---|---|---|
| Working runtime config | PASS | Runtime flags `ignore-cgroups` and `network=sandbox`. The `rootless` flag is rejected. Without `ignore-cgroups`, start fails with `Interactive authentication required`. |
| Rootless netstack (`network=sandbox`) | PASS | Works with pasta, a netavark bridge and `none`. Issue 10359 did not reproduce. |
| `podman-compose` with `runtime: runsc` | PASS | Needs `x-podman.in_pod: false`. |
| Egress wall with iron-proxy | PASS | Holds in netstack and in host-network mode. In host mode the wall is the container network namespace and the internal bridge. |
| Swap, `require`, SSE, HTTP/2, audit log | PASS | All passed in both modes. |
| Egress self-test | PASS | 11 of 11. Run it with `-e HOME=/home/h --tmpfs /home/h`. Otherwise `grep -r` walks `/proc` and hangs. |
| Caps, `no-new-privileges`, read-only root, `:ro` binds, volume ownership, `tmpfs` size | PASS | Same as `crun`. |
| `/proc/self/mountinfo` | PASS | No host paths. This is better than `crun`. |
| `pids_limit`, `mem_limit`, `cpus` | FAIL | Not enforced. 60 processes ran under a limit of 20. 400 MB was allocated under a limit of 64 MB. Rootless Podman cannot use the cgroup manager. |
| Nested Podman as non-root | PASS, reduced | Needs `allow-suid`, `vfs`, `--network=host` and `--cgroups=disabled`. `no-new-privileges` must stay off. |
| Nested Podman as root, `--network=none`, a private network namespace | FAIL | `mount sysfs: Operation not permitted`, `SIOCSIFFLAGS`, `failed to bind mount ns`. |
| Real image `dev-sbx` | PASS | `mise`, `git`, `ssh`, `claude` 2.1.318, `terraform` 1.16.7 and `node` run, as root and as `agent`. |
| Cold start | PASS | gVisor 0.32 to 0.39 s. `crun` 0.35 to 0.46 s. `krun` 0.85 s. |
| 20 new TLS connections through the proxy | NOTE | gVisor 1587 ms. `crun` 730 ms. |
| Host memory per container | NOTE | About 37 MB for gVisor. `podman stats` shows a wrong value. |

Not done: the systemd test, `directfs=false` (a prewarmer "permission denied", not investigated), and a test that `platform=kvm` was in use.

#### Results of spike G2: SPIRE identity of a gVisor sandbox

| Item | Result | Evidence |
|---|---|---|
| Sandbox connects to the SPIRE agent socket with `host-uds=open` and a mounted socket folder | PASS | An SVID is issued. Without `host-uds=open`: `connection refused`. |
| What the SPIRE agent sees | NOTE | The peer is `runsc-gofer` at host uid 1000, in conmon's cgroup. The identity is valid only if that cgroup path holds the 64-hex container ID. |
| Plain `podman run --runtime runsc` | FAIL | With `--ignore-cgroups`, conmon and the gofer stay in the caller's cgroup. No `docker:` selector, and `No identity issued`. This disproves section 5.2, which predicted a `libpod-conmon-<ID>.scope` path. |
| Quadlet or `--cgroups=split` as a plain service | FAIL | The same cause. A Quadlet unit cannot name its scope. It needs a wrapper in `ExecStart`. |
| Start in a scope named for the container ID | PASS | `podman create`, then `systemd-run --user --scope --unit=libpod-<ID> podman start`. The cgroup path then holds the ID. |
| With that wrapper: `--cgroups=split`, `--cgroupns=host`, internal network with `--read-only` and `--cap-drop=all`, `podman-compose` with `runtime: runsc` | PASS | The selectors and the entry format are the same as for `crun`. |
| Two sandboxes at once | PASS | Different gofer PIDs, different cgroup paths, different SVIDs. |
| `api watch` streaming and rotation | PASS | With a 60 s entry TTL, 6 updates came in 150 s. Envoy SDS was not tested. |
| Non-root user in the sandbox | FAIL | Only in-sandbox root gets an SVID, because root maps to host uid 1000. `--user 12345`, `--userns=keep-id --user 1000` and `su nobody` are refused. The error is `Unauthenticated: process uid ... does not match original caller ...`. |
| A same-uid container sets another workload's label | WEAK | It gets that workload's SVID (tested). |
| A host process with uid 1000 forges the cgroup path | WEAK | From spike D. Not run again. |

#### Conditions and gaps for gVisor

- **Start wrapper:** each sandbox must start inside a scope named `libpod-<container ID>`. Write it once as a recipe. This is small custom code, but it is not a plugin.
- **Root-only identity:** the non-root `agent` user cannot get the SVID. A root-owned helper inside the sandbox must hold it, for example Envoy, as in the old `msb` design. The key must stay unreadable to `agent`. Not tested.
- **No resource limits:** the same wrapper can set limits on the scope, for example `-p MemoryMax=` and `-p TasksMax=`. Not tested. [inference]
- **`allow-suid` is a global runsc flag.** Define two runtime entries with different flags. Use the one without `allow-suid` for the sandbox. Use the other only for a builder container. Not tested. [inference]
- **Same weak points as `crun`:** a same-uid process can forge labels or the cgroup path. Use a dedicated host user.

#### Plan changes after G1 and G2

If you choose gVisor, replace Phase 1 of the revised plan with these steps. Steps N3 to N6 stay.

1. **N1g: start wrapper.** Write the recipe that creates the container and starts it in a scope named `libpod-<ID>`. Use it for the compose project.
   - verify: two sandboxes get two different SVIDs with `docker:label` and `unix:uid` selectors.
2. **N2g: limits on the scope.** Add `MemoryMax`, `TasksMax` and `CPUQuota` to the wrapper.
   - verify: a 400 MB allocation fails under a 64 MB limit. 60 processes fail under a limit of 20.
3. **N7g: identity helper.** Run a root-owned Envoy, or another helper, inside the sandbox. The `agent` user must not read its key.
   - verify: Envoy gets an SVID over SDS. `agent` cannot read the key. A call to a test gateway shows the expected SPIFFE ID.
4. **N8g: two runtimes.** Define `runsc` without `allow-suid` for the sandbox and a second entry with `allow-suid` for a builder container.
   - verify: the sandbox keeps `no-new-privileges`. The builder runs `podman build --isolation=chroot --network=host` and `podman push` to a local registry.

If you choose `krun`, keep N1 (nested Podman as non-root) and drop the identity from the sandbox.

### Results of spikes D1 and D2 (rootful Docker with gVisor)

**[spike-D1]** is the SPIRE identity, the limits and the host exposure. **[spike-D2]** is iron-proxy, `docker compose`, nested Podman and the real image. Both ran with Docker 29.9.2, Docker Compose 5.6.1 and `runsc` release-20261102.0. The runtimes `runsc`, `runsc-uds` (`--host-uds=open`) and `runsc-suid` (`--host-uds=open --allow-suid`) were registered in `/etc/docker/daemon.json` by the owner.

#### Results of spike D1: identity, limits, exposure

| Item | Result | Evidence |
|---|---|---|
| Native SVID without a wrapper | PASS | Plain `docker run --runtime runsc-uds --label k=v` gets an SVID from the SPIRE 1.16.0 `docker` attestor with default settings. Docker puts the gofer in `/system.slice/docker-<ID>.scope`. `docker compose` with `runtime: runsc-uds` also works. |
| Runtime `runsc` without `host-uds` | FAIL (expected) | `connection refused`. |
| `--internal` network, `--read-only`, `--cap-drop ALL`, `--cgroupns=host`, `--init`, two containers at once | PASS | Different SVIDs for two containers. |
| Who can get the SVID | LIMIT | Only in-sandbox root (uid 0, also with `--cap-drop ALL`). `--user 1000`, `--user 12345` and `su nobody` are refused: `process uid 0 does not match original caller 1000`. The same limit as with rootless Podman. |
| A container sets another workload's label | WEAK | It gets that SVID. Anyone with Docker API access can do this. The sandbox cannot, because the socket is not mounted. |
| `api watch` rotation | PASS | With a 60 s TTL, updates arrived every 30 s for 95 s. |
| Memory limit | PASS, crude | `--memory 64m` sets `memory.max`. A 400 MB allocation kills the whole sandbox (`OOMKilled`, exit 137). |
| CPU limit | PASS | `--cpus 0.5` held two busy loops at 49.9%. Without it: 200%. |
| Process limit | PASS, crude | `--pids-limit` counts host threads of the sentry. It is about 28 idle and 3 to 4 per guest process. `--pids-limit 20` stops the start. 30 or more starts. When the limit is exceeded, the whole sandbox dies. |
| Host user of the sentry | EXPOSED | The sentry and gofer run as host uid 0, with no user namespace (`uid_map 0 0 4294967295`). Sentry `CapEff` is `0x8001f` (chown, dac_override, dac_read_search, fowner, fsetid, sys_ptrace). Gofer `CapEff` is `0x400df` (adds setuid, setgid, sys_chroot). Both have `NoNewPrivs` 1 and seccomp 2. The sentry mount root is an empty `tmpfs`. The shim `containerd-shim-runc-v2` is unconfined. |
| `:ro` binds, remount, `docker.sock`, `mountinfo` | PASS | All writes denied. No host path leak (roots are `9p` or directfs). |
| Egress self-test | PASS | 7 PASS, 3 SKIP, 0 FAIL. |

An escape from the sentry gives host root under rootful Docker. It gives an unprivileged uid under rootless Podman with gVisor, and under `krun`. Do not set `discover_workload_path = true` on the `unix` attestor. The agent as user `rana` cannot read `/proc/<gofer>/exe` of root processes, and it loses all `unix:` selectors. Use only the `project` and `service` compose labels in entries. Other labels put the host config path into the selectors.

#### Results of spike D2: proxy, Compose, nested Podman

| Item | Result | Evidence |
|---|---|---|
| iron-proxy under `docker compose` | PASS | The egress wall holds. The self-test passes 10 of 10. |
| `dns:` steering for a gVisor client | FAIL, with a fix | The embedded resolver `127.0.0.11` is refused inside a gVisor sandbox. The client has no resolver. The fix: bind-mount `/etc/resolv.conf` with `nameserver 10.90.2.2`. A `runc` client works with `dns:` alone. |
| Proxy DNS | NOTE | The proxy needs `dns: [1.1.1.1]`. The daemon DNS `172.17.0.1` times out from user bridges. |
| File secrets with `uid`, `gid`, `mode` | FAIL | Compose ignores them. `configs` are plain host bind mounts. Secrets from `environment:` honor `uid` and `mode`, but Compose refuses them for a `read_only` service. The working fix: `setfacl -m u:65534:r ca.key` on the host file. |
| Limits | PASS | `mem_limit`, `pids_limit` and `cpus` work under gVisor. `docker stats` shows real memory. The memory limit is loose: 300 MB passed a 256 MB limit. |
| Nested Podman as non-root `agent` | PASS, reduced | Needs `runsc-suid`, `vfs`, `--network=host` and no `no-new-privileges`. `--cgroups=disabled` is no longer needed. A private network namespace, `--network=none` and overlay storage still fail. |
| Nested Podman as root | PASS | With `--cap-add SYS_ADMIN --ulimit nofile=1048576:1048576`, plain `runsc` runs, builds and pushes. It needs no `allow-suid`. `no-new-privileges` is allowed. Push by registry name fails (embedded DNS), so use `--add-host`. |
| Real image `dev-sbx` | PASS | Runs as root and as `agent`. Every tool works. The `terraform version` plugin-cache error as root also occurs under `runc`. |
| Cold start | NOTE | `runc` about 0.65 s. `runsc` 0.64 to 0.75 s. `runsc-uds` 0.74 to 0.80 s. Podman with `crun` 0.35 s. |
| TLS handshake and first byte | NOTE | Handshake 8.8 ms against 4.2 ms on `runc`. First byte 0.035 to 0.22 s against about 0.026 s on `runc`. |
| `docker compose publish` | PARTIAL | It needs a TLS registry. The artifact holds `compose.yaml` only. References to `configs` and `secrets` stay. Relative bind sources are not bundled. `--with-env` embeds env values in plaintext. It was signed and verified with cosign 3.1.4. `compose -f oci://` fails for v1 (dangling `env_file` hash). v2 passed `config` and `up --dry-run` only. |
| Rules of `iptables` and `nft` | NOT READABLE | They need root. The evidence is behavioral: the client times out to every host port, and only the gateway answers ICMP. |

Left on the host: the Docker images `localhost/stage10-verify:local`, `dev-sbx:b257a198...` (7.2 GB) and `ironsh/iron-proxy@sha256:727da0cc...`.

#### Three-way comparison

| | Podman + `krun` | Podman + gVisor (rootless) | Docker + gVisor (rootful) |
|---|---|---|---|
| Native sandbox identity | No | Yes, with a start wrapper (root only) | Yes, no wrapper (root only) |
| Resource limits | VM size by annotation | Not enforced | Enforced, crude |
| Escape gives | Unprivileged uid (100000 range) | Unprivileged uid 1000 | Host root |
| Nested Podman | Native overlay as non-root (fix A or B) | Non-root with `allow-suid`, `vfs`, host network | Non-root reduced as well. Root works with `SYS_ADMIN`. |
| Host daemon | None | None | Root daemon. `docker.sock` access is root-equivalent. |
| Compose | `podman-compose` traps | `podman-compose` traps | `docker compose`. Secret `uid` and `mode` are still ignored. |
| DNS steering to iron-proxy | `x-podman.disable_dns` | `x-podman.disable_dns` | Bind-mounted `resolv.conf` for gVisor clients |
| `podman exec` or `docker exec` | Not supported under `krun` | Works | Works |
| Cold start | 0.85 s | 0.32 to 0.39 s | 0.64 to 0.80 s |
| OCI artifact | `podman artifact` or `flux push` (spike E) | The same | `docker compose publish` (`compose.yaml` only), or the same tools |

### Results of spikes F1 and F2 (Docker with gVisor, the final design)

**[spike-F1]** is the identity of the sandbox container at start. **[spike-F2]** is the daily developer flow. Both ran on rootful Docker 29.9.2 with the runtime `runsc-suid`. The sandbox container is the workload. The agent inside it runs as non-root `agent`. F2 stopped early at the request of the owner.

#### Results of spike F1: the sandbox container gets its SVID at start

| Item | Result | Evidence |
|---|---|---|
| Root entrypoint gets the SVID at start | PASS | Plain `spire-agent api fetch x509` as in-sandbox root. No wrapper, no plugin. The agent log shows the peer `runsc-gofer` (host uid 0) in `/system.slice/docker-<id>.scope`. The entry `spiffe://spk-f1.test/sandbox/demo` was issued. |
| Selectors the host verifies | PASS | `docker:image_config_digest` plus the compose `project` and `service` labels. With the containerd image store, `image_config_digest` is the image index digest. `docker:image_id` is only the tag text. Do not use it. |
| Entry fails closed | PASS | No SVID gives exit code 1. No `agent` shell starts. |
| Negative tests | PASS | No label, wrong service, wrong project, alpine with the labels, runtime `runsc` without `host-uds` and `--user 1000` all gave no identity or a refusal. |
| Rotation | PASS | A root supervisor renews it every 10 s. With a 60 s TTL, 8 serials appeared in 200 s with no restart. |
| Use of the SVID without the key in `agent` reach | PASS | A root-owned relay (perl and curl on `127.0.0.1:8443`) does mTLS with the current SVID. As `agent`, `curl http://127.0.0.1:8443/` returned the SPIFFE ID of the sandbox from a fake gateway. |
| `agent` cannot reach the identity | PASS | `/run/priv` and `/run/identity` are mode 0700 root. `/proc/<root pid>/*` is denied. `kill` and `ptrace` give `EPERM`. The root filesystem is read-only. A uid 1000 caller is refused by SPIRE even with the socket visible. |
| Setuid binaries with `allow-suid` | NOTE | `su` ran with uids `1000 0 0 0`. The spike found no path to real root. Keep the setuid bit only on `newuidmap` and `newgidmap`. |
| Forged label | WEAK | Anyone with Docker API access can run `docker run --label ...` of the same image and get the SVID. It also works under `runc`. The digest pins the image only. The trust anchor is access to the Docker socket. |
| Minimum capabilities | PASS | The entry needs `SETUID` and `SETGID`. Nested Podman as `agent` needs `SETUID`, `SETGID` and `DAC_OVERRIDE`. |
| Watchdog | NOT TESTED | If the supervisor dies, the container stays up. The gateway answers `certificate expired` after about 60 s. |
| `no-new-privileges`, Docker daemon restart | NOT TESTED | |

Traps and image changes from F1:

- The `spire-agent` of mise and `/opt/mise` belong to `agent`. Root must use its own root-owned copy in `/usr/local/bin`.
- The image has no `python3`. The relay uses perl and curl.
- The supervisor becomes a zombie, because an `agent`-owned process is its parent.
- Put `/entry.sh`, the supervisor and the relay in `/usr/local/sbin`. Run `chmod u-s` on `chfn chsh gpasswd mount newgrp passwd su umount fusermount3 ssh-keysign`.

#### Results of spike F2: build, push and publish as `agent`

| Item | Result | Evidence |
|---|---|---|
| `podman build` (3 `RUN` steps with `apk add`), `login`, `push`, `pull` and `run` | PASS | Run as non-root `agent` with only `PLACEHOLDER-REGISTRY` in the sandbox. |
| `flux push artifact`, `oras push`, `podman artifact add` and `push` | PASS | The registry received all of them. The digests equal the registry digests. |
| Secret swap | PASS | Each authenticated request shows `swapped` in the proxy log. The real password appears nowhere: not in `env`, PID 1 `environ`, a grep of `/` as root and as `agent`, `docker inspect` or the proxy log. `auth.json` holds only the placeholder. |
| Egress self-test | PASS | 9 PASS and 1 SKIP (no `dig`). The direct registry IP, `1.1.1.1` and UDP DNS fail. |
| Setuid-stripped image (only `newuidmap` and `newgidmap`) | PASS | The flow ran. |
| Nested Podman under plain `runc` as `agent` | FAIL | It needs a privileged container. gVisor is what makes it possible. |
| Real GHCR bearer-token exchange | NOT TESTED | Only Basic auth and its 401 challenge were tested through the proxy. |
| Volume persistence, `tmpfs` size limit, `certs.d` CA path | NOT TESTED | A volume survived a force-recreate. `down -v` removed it. |

Minimum config from F2:

- Runtime `runsc-suid`. A root entry, then `setpriv` to `agent`.
- `cap_drop: [ALL]` plus `CHOWN`, `SETUID`, `SETGID` and `DAC_OVERRIDE`. `DAC_READ_SEARCH` instead of `DAC_OVERRIDE` fails at `newuidmap`.
- No `no-new-privileges`. `read_only: true` with `tmpfs` on `/tmp` and `/run`. A named volume on `~/.local/share/containers`.
- Podman with `vfs` storage, `--network=host` (netns host) and `cgroupfs`. Set `TMPDIR=/dev/shm` and `XDG_CACHE_HOME=/tmp/cache`.
- A bind-mounted `resolv.conf` with the proxy IP. A CA bundle bind-mounted over `/etc/ssl/certs/ca-certificates.crt`.

Traps from F2:

- `read_only: true` breaks `podman build --isolation=chroot`. Use the default `oci` isolation. It works.
- The iron-proxy CA needs `keyUsage` `keyCertSign`. The `management:` block needs its API key variable.
- A CA bundle alone fails for `python` `ssl` (no hashed link). Node needs `NODE_OPTIONS=--use-system-ca`. `requests` needs `REQUESTS_CA_BUNDLE`. `git` needs `GIT_SSL_CAINFO`.
- Bulk HTTPS downloads from `dl-cdn.alpinelinux.org` through iron-proxy are about 30 times slower, also with `runc` clients. Plain HTTP is fast. Use HTTP `apk` repositories.

Time, gVisor against `runc` (privileged):

| Step | gVisor | `runc` |
|---|---|---|
| Cold build | 6.0 s | 4.6 s |
| Pull | 0.83 s | 0.51 s |
| Cached rebuild | 0.55 s | 0.16 s |
| Push, `flux push`, `oras push` | 0.85 s, 0.24 s, 0.15 s | The same |

A medium build (`build-base` and `make -j8`) passed with `pids_limit` 128 and `mem_limit` 512m. These were the lowest values tested. The `vfs` storage used 655 MB for such an image. The proxy allowlist needed `registry.example.test`, `dl-cdn.alpinelinux.org`, and for Docker Hub base images `registry-1.docker.io`, `auth.docker.io` and `production.cloudfront.docker.com`.

### Results of spikes N1 and N2 (`krun` path)

**[spike-N1]** is nested Podman as non-root in the `krun` guest. **[spike-N2]** is the user namespace and the secret of the proxy. Both ran after the gVisor spikes. The owner then chose Podman with `krun` for the sandbox, because Podman must work natively inside it. gVisor stays as the fallback. The blocker in item 6 of the revised verdict is closed. The conflict in item 7 is closed.

#### Results of spike N1: nested Podman as `agent`

| Item | Result | Evidence |
|---|---|---|
| Cause of the `pivot_root` failure | FOUND | The libkrun virtiofs server runs each file operation with the uid of the caller and no capabilities. `CAP_DAC_OVERRIDE` of the user-namespace root does not apply there. `mkdirat("./.pivot_root...", 0700)` gives `EACCES` in a layer `diff` folder of mode 0555. The same test passes on guest `tmpfs` and as guest root. The root mount is not `nosuid`. `newuidmap` and the user-namespace mapping work. |
| Fix A: storage on the container rootfs, not persistent | PASS | Set `[storage.options.overlay] force_mask = "0700"` in `~agent/.config/containers/storage.conf`. `run`, `build` (with `apt-get`, `useradd` and `chown` in `RUN`) and `push` to a local registry pass with native overlay. A pull and run of `alpine` takes about 4 s. A 3-line build takes about 2 s. A Debian `apt` build takes about 22 s. A push takes about 0.5 s. |
| Fix B: persistent storage | PASS | Guest root mounts an ext4 loop image at `~/.local/share/containers` and gives it to `agent`. The image is a file on a host named volume. Use plain overlay, with no `force_mask`. `tmpfs` storage also works. |
| A named volume or a bind mount directly as the storage folder | FAIL | It fails also with `force_mask`. `dpkg` in a nested build gives `eipp.log.xz File exists`. The cause is not found. |
| `ignore_chown_errors`, `fuse-overlayfs`, `vfs` | FAIL | The same error. |
| `buildah` | NOTE | It needs `TMPDIR=/dev/shm`, or `--isolation=chroot`. Its temporary folder on virtiofs hits the same error. |
| Host flags | PASS | None is needed. `no-new-privileges`, `--pids-limit` and the default seccomp profile are fine. `--cap-drop=all` breaks `agent` access to `/home/agent`. Add back `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID` and `SETGID`. |
| Registry reachable from the guest | NOTE | Put the registry on the same Podman network and use its name. `host.containers.internal` to a loopback publish is refused from the guest. |
| Plain `crun` control with the default userns | NOTE | It fails earlier, at `newuidmap` with `EPERM`. |

What `.msb/image` already has: the uid map, `subuid`, the setuid `newuidmap`, the `chgrp` of `/dev/fuse` and `/dev/net/tun`, and `mount --make-rshared /`. What must change for `krun`:

- Add a `storage.conf` with `force_mask`, or the loop mount in `sandbox-boot`.
- Set `TMPDIR=/dev/shm`.
- Boot as guest root through the container `command:`, because `krun` has no `podman exec`.
- Remove `fuse-overlayfs`.

Not tested: `--runtime runc` in the guest, the `krun.*` annotations, `--cgroups=disabled`, nested `--network=host`, a push through iron-proxy to a real registry, and the loop mount in `sandbox-boot`.

#### Results of spike N2: user namespaces and the proxy secret

| Item | Result | Evidence |
|---|---|---|
| `--userns=auto` with `krun` | PASS | The VMM runs as host uid 100000 or 165535, not 1000. `auto:size=65536` also works. The earlier failure came from `keep-id`. One stopped `keep-id` container breaks every `auto` run. Removing it fixes it. |
| Proxy without `keep-id`, with a Podman secret | PASS | Use `--secret NAME,uid=65534,gid=65534,mode=0400,target=/etc/iron-proxy/ca.key`. `podman-compose` 1.6.0 ignores `uid`, `gid` and `mode` on file secrets. Use `external: true` with `podman secret create`. Quote the mode as `"0400"`. Unquoted, it becomes decimal 256. |
| Proxy without `keep-id`, with `:U` on a copy of the CA folder | PASS, with a cost | It changes the owner of the host folder. You lose access to the key. |
| Proxy, `krun` sandbox and echo server in one store | PASS | The sandbox reached the proxy over the `--internal` network. The audit log shows `swapped CLAUDE_TOKEN`. A blocked host got 403. Direct internet failed. It needs `x-podman: in_pod: false`. |
| `userns_mode: auto` and `x-podman.uidmaps` with `runtime: krun` | PASS | `userns_mode: private` gives an error. |
| Separation | PASS | A bind-mounted host uid-1000 folder shows as `nobody` in the guest. A 0600 file is unreadable. A 755 folder is not writable. `cat /proc/<proxy pid>/environ` as `rana` is denied when the proxy runs as 65534. |
| Access of the VMM to the Podman socket and `/run/user/1000` | NOT TESTED | Reasoned from file modes only. [inference] |
| Entry pattern (root start, `chown`, `setpriv` to `agent`) | PASS, more caps | `CHOWN`, `SETUID` and `SETGID` fail on `touch`. `FOWNER` fixes fresh volumes only. `FOWNER` plus `DAC_OVERRIDE` passes everywhere. In a separate user namespace these caps cover only the mapped ids of the VMM, not your files. |
| `podman exec` under `krun` | NOT SUPPORTED | Use `command:` scripts and `podman logs`. |
| `unshare -Ur` in the guest | PASS | Works as root and as uid 1000. A `tmpfs` mount namespace works. |

Hazards:

- **Auto ranges shift.** A volume written in one auto range shows as `nobody` and is not writable in another. Use static maps: `x-podman.uidmaps: ["0:100000:65536"]` for the sandbox and `["0:200000:65536"]` for the proxy.
- Use size 65536. The default size 1024 makes `chown 1234` fail with `EINVAL`.
- Do not put the proxy in the default user namespace next to an auto sandbox. The ranges overlap.

#### Decision and plan for the `krun` path

Use rootless Podman with `krun` for the sandbox and iron-proxy as the only way out. The remaining steps replace Phase 1 of the revised plan:

1. **N3: CA trust in the real image.** Same as before.
2. **N4: full stack under `krun`.** Use the static uid maps, the Podman secret for `ca.key`, the entry caps (`CHOWN`, `SETUID`, `SETGID`, `FOWNER`, `DAC_OVERRIDE`) and the storage fix B (loop image).
   - verify: the egress self-test passes. `claude`, TTT and Herdr start. As `agent`, `podman build` with a `RUN` step and `podman push` to a registry through iron-proxy work.
3. **N9: access to the sandbox without `podman exec`.** Test TTT or a shell as the foreground process (`podman run -it` or `podman attach`). Test more shells through TTT and Herdr. Test `sshd` in the guest.
   - verify: you can open an editor and two shells in the sandbox from the host terminal.
4. **N10: storage choice.** Compare fix A (not persistent) with fix B (loop image). Find the cause of the `dpkg` error on a direct named volume.
   - verify: the Podman image storage persists after `down` and `up`.
5. **N5, N6:** real traffic (you run it) and https git remotes. Same as before.
6. **N11: SPIFFE for the microVM.** The owner decides later. There are three options. First, a vsock port mapped to the agent socket (needs a `crun` patch). Second, a root-owned helper in the guest. Third, an Envoy sidecar that holds the SVID. Spike G2 showed that gVisor can do it natively. Spikes A and D showed that stock `krun` cannot.

### Results of spike A: `krun` under rootless Podman

| Item | Result | Evidence |
|---|---|---|
| `krun` as a symlink to `crun` with a private `CONTAINERS_CONF` | PASS | `uname -r` in the guest prints 6.12.109. |
| `podman-compose` with `runtime: krun` | PASS | The service starts. |
| `krun.cpus=2`, `krun.ram_mib=1024` | PASS | `nproc` is 2. `free -m` shows 1020 MiB. |
| `--internal` network blocks egress | PASS | `Network unreachable`. The guest has no `eth0`. |
| Sibling container on the internal network | PASS | Reachable by name and by IP. |
| `--cap-drop=all`, `no-new-privileges`, `--read-only`, `--pids-limit`, default seccomp | PASS | The VM starts. The flags confine the VMM. Guest processes keep `CapEff 1ffffffffff`. |
| `--read-only` root, `:ro` bind, named volume persistence | PASS | Writes fail on `:ro`. Data persists. |
| The VMM on the host | PASS | Uid 1000. The cgroup path holds the container ID. |
| Mounted host Unix socket | FAIL | `ECONNREFUSED`. Plain `crun` connects. |
| `krun.use_passt=1` | FAIL | `crun` 1.30.1 calls `passt --socket-fd`. `passt` 2026_10_02 has only `--fd`. |
| Nested Podman as non-root `agent` | FAIL | `pivot_root` error on rootfs, tmpfs and volume. |
| Nested Podman as guest root | PASS | `overlay` and `vfs` work. `fuse-overlayfs` does not. |
| `--userns=auto` | FAIL here | Cause found by spike C: a `keep-id` container in the store. |

Gotcha: run `unset NOTIFY_SOCKET` before nested pulls. Otherwise they fail with `connection refused`.

### Results of spike B: iron-proxy

| Item | Result | Evidence |
|---|---|---|
| Image `docker.io/ironsh/iron-proxy@sha256:727da0cc35a6d73ed2913a38d56c4b9b4476c075149492e4fbf75552e83361ff` | PASS | The binary equals the GitHub release `v0.56.0` tarball. |
| Signature of the release | NOT VERIFIABLE | No `checksums.txt.asc` for 0.50 to 0.56. |
| Egress wall | PASS | No route. `curl 1.1.1.1` and `dig @1.1.1.1` fail. An unlisted host gets 403. SNI and `Host` mismatches give 400 or 403. |
| Glob allowlist | PASS | `*.example.org` also matches `example.org`. |
| Bearer swap, `match_headers`, `match_query`, `match_body`, WebSocket upgrade | PASS | The upstream saw the real value. The client never held it. |
| `require: true` | PASS | A missing token, or a token in a wrong header, gives 403. |
| Placeholder sent to a host with no rule | PASS | Passes unchanged. |
| Basic auth | PASS | iron-proxy decodes base64 itself. Use a raw `proxy_value`. The full-string base64 workaround fails. |
| Rotation | PASS | A `file` source plus `POST /v1/reload` changes the value on the same HTTP/2 connection. `ttl: 3s` also works. Bad YAML gives 422 and keeps the old pipeline. |
| SSE and HTTP/2 | PASS | Events arrive about 200 ms apart. HTTP/2 is used on both sides. |
| CONNECT and SOCKS5 listener | PASS | The allowlist applies. |
| Raw TCP, SSH | FAIL (limit) | Non-HTTP bytes get `400 Bad Request`. |
| Audit log | PASS | Secret names and locations only. No real value in 50 lines. |
| Hardened run | PASS | Uid 65534, `cap_drop: [ALL]`, `cap_add: [NET_BIND_SERVICE]`, `read_only`, `no-new-privileges`. |
| Speed and memory | PASS | First byte in 39 to 195 ms. 18 MB of memory. |

Settings that the spike proved:

- Set `x-podman.disable_dns: true` on the inner network. Otherwise the client resolver points at aardvark and `dns:` is ignored.
- Set `metrics: {listen: "127.0.0.1:9090"}`. The default binds all interfaces, and the client can reach `/healthz`. The README does not document this.
- Mount the config directory, not one file. A single-file mount goes stale after `sed -i`.
- Without `NET_BIND_SERVICE`, the bind fails and the container exits with code 0. A restart policy of `on-failure` does not restart it.
- Query swap needs `match_query: true`. The README says that query is always scanned. This is wrong.
- The management API stays on the loopback of the proxy container. The client cannot reach it.
- `env` secrets show in `podman inspect`. Use `file` sources or Podman secrets.

### Results of spike C: hardening, mounts, volumes

| Item | Result | Evidence |
|---|---|---|
| Compose keys: internal network, `ipv4_address`, `dns`, `cap_drop`, `cap_add`, `no-new-privileges`, `read_only`, `tmpfs`, `pids_limit`, `mem_limit`, `cpus`, `sysctls`, `user`, `runtime`, `devices`, `secrets`, `x-podman.uidmaps` | PASS | All work in `podman-compose` 1.6.0. |
| Top-level `configs:` | IGNORED | Silent. |
| `:U` on a named volume | IGNORED | Works on a bind mount. It then changes the owner of the host folder. |
| One pod for all services | TRAP | A pod shares one network namespace. Set top-level `x-podman: {in_pod: false}`. |
| `:ro` bind mount | PASS | Every write fails as root and as uid 1000. Tried: symlinks, `..`, `/proc/self/root`, `/proc/1/root`, `mount`, `remount`. |
| Host paths visible in the container | PASS, one leak | No host path, socket or `/run/user`. With `crun`, `/proc/self/mountinfo` shows host paths. `krun` does not. |
| `krun` guest root remounts a path read-write | NOTE | Writes still fail, because the host enforces `:ro`. |
| Minimum caps for the entrypoint (root start, `chown`, drop to `agent`) | PASS | `CHOWN`, `SETUID`, `SETGID`. `krun` also needs `FOWNER`. Add `DAC_READ_SEARCH` if `/home/agent` is mode 0700. |
| Size limit on volumes | PARTIAL | Only `tmpfs` enforces a size. `o=size` fails on btrfs. |
| Lifecycle | PASS | `down` keeps volumes. `down -v` removes them. `podman rm --volumes` does not. |
| KVM ioctls under the default seccomp profile | PASS | `CREATE_VM` works. |
| Egress self-test script | PASS | Tested on an internal network. It fails on a leaky container. |

Rules from spike C:

- The container uid 1000 appears as host uid 100999 by default. It appears as 1000 with `keep-id`.
- `podman exec` runs as root with the added caps. Use `exec -u agent`.
- The image must create `/home/agent/.local` and `.local/share` as `agent`. Otherwise `crun` creates them as root.
- Put caches on `tmpfs`. Leave other volumes without a limit and watch them with `du`.
- Do not mix `--userns=auto` and `keep-id` in one store.

### Results of spike D: SPIRE 1.16.0 with Podman

| Item | Result | Evidence |
|---|---|---|
| `docker` attestor with `use_rootless_podman = true`, `crun` container | PASS | Entries `docker:label:*` plus `unix:uid:1000` return an SVID. |
| Wrong label, wrong uid | PASS | No SVID. The agent sees host uid 112344 for `--user 12345`. |
| Default cgroups, `--cgroups=split`, `--cgroupns=host` | PASS | The container ID resolves in each case. |
| `podman-compose` labels as selectors | PASS | `io.podman.compose.project` and `io.podman.compose.service` work. |
| Internal network, `--read-only`, `--cap-drop=all` | PASS | The socket works. |
| Podman API socket missing | PASS (fails closed) | No identity is issued. |
| `krun` guest connects to the agent socket | FAIL | `connection refused`. |

Weak points of the trust chain:

- A container that sets the label itself, with the same uid, gets the identity of another workload.
- A host process with the same uid can fake the cgroup path of any container.
- The real boundary is the uid. Run the sandboxes under a dedicated host user and pin `unix:uid`. This is not tested.
- SPIRE 1.16.0 publishes no signature. The checksum matched.

### Results of spike E: artifact and signing

| Item | Result | Evidence |
|---|---|---|
| `podman artifact add` and `push`, `flux push artifact`, `oras push` | PASS | Each gives a pinnable `@sha256:` digest. Podman pulls all three. |
| `podman artifact add` with a directory | LIMIT | It is flat. A directory argument fails. Subdirectory files lose their path. |
| `flux push artifact` layout | NOTE | One tar.gz layer. `podman artifact extract` returns the tarball. |
| Pull by tag after an attacker overwrites the tag | WARNING | Returns the new content. |
| Pull by pinned digest after the overwrite | PASS | Returns the original. |
| `cosign sign` by digest, `cosign verify --key` | PASS | The attacker digest and the tag fail. cosign v3 needs an empty signing config and `--insecure-ignore-tlog` for key-only verify. |
| Podman 6.1.4 policy with cosign v3 bundle | FAIL | `A signature was required, but no signature exists`. |
| Podman 6.1.4 policy with the legacy `.sig` format | PARTIAL | It works for images with a `registries.d` file. |
| `podman artifact pull` with a legacy-signed artifact | FAIL | `Pushing signatures for OCI images is not supported`. |
| End-to-end flow | PASS | Publish 0.87 s. Host `cosign verify` and pin test 0.41 s. |

Rules from spike E:

- The host gate is `cosign verify` plus the pinned digest. Podman policy is not usable for artifacts.
- The pin file in git needs your review. That review is the real gate.
- The signing key and the push token must stay out of the sandbox.
- Key-only verification has no replay protection.
- Each publish gives a new digest, because of the `created` annotation.

### Claims in the sections below that the spikes changed

| Earlier claim | Now |
|---|---|
| No `krun` or `crun` on this host | Both are installed. `crun` shows `+LIBKRUN`. |
| Spike A said `--userns=auto` needs a larger subuid range | Wrong. The cause is a `keep-id` container in the store. |
| Caddy is the egress proxy | iron-proxy replaces it. Caddy was not tested. |
| A basic-auth swap needs a full-string base64 `proxy_value` | Wrong. iron-proxy decodes Basic auth. |
| The sandbox may get a SPIFFE identity | No. The guest cannot reach a mounted socket. |
| Podman policy can verify the signed artifact | No. Use `cosign verify` and a pin. |
| `krun` is unproven | It works. Nested Podman as non-root and `passt` fail. |

### Revised plan

All steps keep `.msb/` unchanged until the switch. Spikes A to E are done.

**Phase 1: close the open problems (more spikes)**

1. **N1: nested Podman as `agent` in the `krun` guest.** Test with the real image from `.msb/image`. Try a named volume, a `tmpfs`, a different storage driver, `newuidmap` and `subuid` entries in the guest, and `strace` on the failing call.
   - verify: `podman run --rm alpine true` works as `agent` in the guest.
   - If it fails, test a block-backed volume. Compare with how `msb` backs `podman-storage`.
2. **N2: userns.** Run the sandbox with `--userns=auto` and the proxy without `keep-id`. Give the proxy `ca.key` through a Podman secret or a copied file with the right owner.
   - verify: both containers start in one store, and the proxy reads the key.
3. **N3: CA trust in the real image.** Test `curl`, `git`, `node`, `python` (`requests`, `uv`), `go`, `terraform`, `mise`, `gh`, `claude` and `qwen`.
   - verify: each tool completes an https call through the proxy with no certificate error.
4. **N4: full stack under `krun`.** Run the spike B layout with `runtime: krun` on the sandbox and the spike C self-test.
   - verify: the self-test passes. `claude`, TTT and Herdr start.
5. **N5: real traffic (you run it).** Use `bws run` with the real tokens, one at a time. Test four things. First, the Claude API with a long SSE stream and a large body. Second, GitHub with a Basic auth `git` clone and push. Third, `ghcr.io` with a scoped token. Fourth, the Qwen endpoint.
   - verify: each call works. The audit log shows the swap. No real token appears in the sandbox `env` or files.
   - Test the `max_request_body_bytes` limit (1 MiB). A placeholder in a larger body is not swapped.
6. **N6: SSH.** List the remotes that use SSH. Change them to https.
   - verify: `git` works with https remotes only.

**Phase 2: build the bundle in a worktree** (use `herdr worktree create`)

7. Create `.sandbox/` with `compose.yaml`, `iron-proxy.yaml` (secret names and placeholders only), the image files, a `justfile`, a README and the egress self-test.
   - verify: `podman-compose config` passes. The self-test passes on `up`.
8. Add a review rule for `.sandbox/` (CODEOWNERS). Add a CI test that the compose file has no `privileged`, no `network_mode: host`, no socket mount and no extra `devices`.
   - verify: a test change that adds `privileged: true` fails CI.

**Phase 3: publish and gate**

9. Pin every image by digest. Publish with `podman artifact` or `flux push artifact`. Sign by digest with `cosign`. Keep the key on the host only.
   - verify: `E-verify-pinned.sh` and `cosign verify` pass on the host and fail on an unsigned digest.
10. Give the sandbox no token that can push to the package. Scope the `ghcr.io` token to its own package.
    - verify: a push from inside the sandbox to the bundle package fails.

**Phase 4: switch**

11. Run the new stack next to `msb` for one week of real work.
    - verify: the audit log has no blocked host that you needed. Compare start time, memory and tools.
12. Switch the daily command to the new recipe. Keep `.msb/` for two more weeks.
    - rollback: run `just msb run`.
13. Remove `.msb/` after the rollback window.

**Not tested after the spikes**

- Real hosts and real tokens (N5).
- `dns.records`, `dns.passthrough`, TPROXY and the `nftables` layer of iron-proxy.
- A second real host user for SPIRE.
- Disk quotas on xfs or ext4.
- GitHub Container Registry tag immutability and token scope.
- Long-running behavior. Each spike ran for under one hour.

## Verdict before the spikes

1. **Overall: feasible with changes.** The design works on paper for each part. Three parts have no proof yet: rootless gVisor networking, the SPIRE socket from inside gVisor, and the secret swap for SSE streams. Run the spikes before any switch.
2. **gVisor does not fit this sandbox well.** The sandbox runs Podman builds, uses a full shell session and keeps long-lived state. gVisor loses nested Podman (host network and `vfs` only), cgroup limits from Podman, systemd and any nested KVM. [doc] [issue]
3. **Podman with the `krun` runtime fits better.** It keeps a real guest kernel and the microVM boundary. It keeps Compose, Caddy and the SPIRE container attestor. It is unproven on this host. [doc] [src] [inference]
4. **The SPIFFE simplification comes from the container packaging, not from gVisor.** SPIRE 1.16.0 attests a rootless Podman container by its cgroup. That needs no `msbvm` plugin and no delegate. [doc] [src]
5. **A sandbox identity adds little.** The only documented use is mTLS to the MCP gateway. Caddy can hold that SVID and present it. The sandbox then holds no identity and no key. [repo] [inference]
6. **Caddy cannot be a MITM forward proxy.** Caddy core v2.11.9 has no forward-proxy handler. The workable model is a reverse proxy per allowed host with an internal CA. Caddy then swaps the header placeholder with `header_up`. [src]
7. **Caddy lacks several msb secret features.** Query and body swap, the violation action, wildcard DNS aliases, Basic-auth decoding and non-HTTP names are missing or partial. Caddy rotates a file secret per request, which msb does not. See section 4.
8. **Caddy can be the only route out and out of reach.** Use an internal Podman network (no gateway). Put the sandbox and Caddy in two separate containers, not in one pod. Do not mount any Podman socket. [doc] [src]
9. **Compose is possible with `podman-compose` v1.6.0 and not with the `docker-compose` provider.** `podman-compose` passes `runtime:` for each service. The Podman compat API has no code that reads `HostConfig.Runtime`. `podman-compose` ignores top-level `configs`. [src] [inference]
10. **The OCI artifact is easy.** Use `podman artifact` (stable since 5.6) or `flux push artifact` (already in this repo), plus `cosign sign` on the digest. [doc] [repo]
11. **Smallest alternative: keep msb.** Drop only the sandbox SPIFFE identity. Give the identity to a host-side proxy. This removes the delegate flow and changes no VM. [inference]

Recommendation: run spikes S1 to S7. If S1 to S4 pass, build Podman + runsc + Caddy. If S4 fails, give the identity to Caddy. If S1 fails or the nested-Podman gap hurts, test Podman + krun + Caddy (S5). If both fail, keep msb and drop the sandbox identity.

| Component | Verdict | Main reason |
|---|---|---|
| Rootless Podman + `runsc` | feasible with changes | Needs `ignore-cgroups` and a network mode that works rootless. CI covers only `echo`. |
| gVisor netstack in rootless | not proven | Issue 10359 is open. The rootless guide and the CI say it can work. |
| Caddy only egress | feasible | Internal network, no gateway, no pod. |
| Caddy secret swap | feasible with changes | Reverse-proxy model only. Several msb features are missing. |
| Caddy allow list with wildcards | feasible with changes | Needs a DNS answerer with wildcards. aardvark-dns has none. |
| SPIFFE for the sandbox | not proven, low value | The gofer is the socket peer. The cgroup depends on Podman settings. |
| SPIFFE for Caddy | feasible with changes | Normal container. Caddy needs a reload to load a new SVID. |
| One Compose file | feasible with changes | `podman-compose` only. Bind-mount the Caddyfile. |
| OCI artifact and signing | feasible | Tools exist. The image signature policy has no test. |
| Podman + `krun` + Caddy | feasible, unproven | No `krun` on this host. TSI uses the VMM netns. |
| Replace all msb features | feasible with gaps | See section 7. |

## 1. What the current setup does

| Item | Fact | Source |
|---|---|---|
| VM | One microsandbox VM (libkrun) declared in `sandbox.yaml`. 4 CPUs, 3 GB, image pinned by digest. | [repo] `.msb/vm/sandbox.yaml` |
| Secrets | The VM holds placeholders. The host replaces them in requests to listed hosts. Four secrets and `K8S_TOKEN`. | [repo] `.msb/README.md` |
| Egress | `network.allow` lists about 60 hosts, with wildcards. msb blocks other hosts at DNS. | [repo] `.msb/vm/sandbox.yaml` |
| TLS | msb intercepts TLS. `spire.localhost` bypasses it. | [repo] `.msb/vm/sandbox.yaml` |
| Identity | A SPIRE agent in the VM, a host agent, the `msbvm` plugin, a delegate and node certificates. About 970 lines of Go. | [repo] `code/agent-workload-identity/` |
| Volumes | `claude-home`, `podman-storage`, `terraform-providers`, `herdr`, `qwen-home`, `headroom-home`. | [repo] `.msb/vm/sandbox.yaml` |
| Access | No sshd. `msb ssh serve` is the ssh proxy. `msb exec` stops output at about 1 MB. | [repo] `.msb/README.md` records 14 |
| Nested containers | Rootless Podman in the VM. FUSE and TUN devices. | [repo] `.msb/image/sandbox-boot` |
| Tooling | `just msb run`, `bws run`, `podman build` and push to ghcr.io with a digest pin. | [repo] `.msb/justfile` |
| Dev container | No `devcontainer.json` in the tree. The tag `docker-sbx` holds `.sbx/` and has none. | [repo] `git ls-files`, `git ls-tree docker-sbx` |

## 2. Podman with gVisor, rootless (question A)

### 2.1 What works

| Claim | Tag | Source |
|---|---|---|
| gVisor has a rootless guide with three methods. Podman and Docker use method 2: the engine makes the user namespace, then calls `runsc` as UID 0 inside it. The guide dates from 2026-04-01. | [doc] | `g3doc/user_guide/rootless.md`, release-20261102.0 |
| Method 2 maps many UIDs through `newuidmap`. It needs a private network namespace to protect abstract Unix sockets. | [doc] | same file |
| The gVisor CI runs `podman run --rm --runtime <wrapper> alpine echo` as a normal user. The wrapper adds `--ignore-cgroups`. Two jobs set `--directfs=false` and `--directfs=true`. | [src] | `test/podman/run.sh`, `.buildkite/pipeline.yaml:683-686` |
| `--runtime` and `--runtime-flag` are global Podman options. `--runtime-flag` drops the leading `--`. A flag list per runtime goes in `[engine.runtimes_flags]` of `containers.conf`. The runtime path goes in `[engine.runtimes]`. | [doc] [src] | `podman.1.md`, `libpod/oci_conmon_common.go:85-88` |
| `runsc` is a known runtime name in Podman. It is in `runtime_supports_json`. It is not in `runtime_supports_nocgroup`. | [src] | `container-libs/common/pkg/config/containers.conf:720-728` |
| Rootless `--userns=auto` uses the ranges in `/etc/subuid`. Each container gets a separate range. | [doc] | `podman-run` option `--userns` |

### 2.2 Steps

1. Download `runsc` and its checksum from the gVisor release. Put `runsc` in `~/.local/bin`. [inference]
2. Add `~/.config/containers/containers.conf.d/runsc.conf`:

```toml
[engine.runtimes]
runsc = ["/home/rana/.local/bin/runsc"]

[engine.runtimes_flags]
runsc = ["ignore-cgroups", "network=host", "host-uds=open"]
```

3. Run `podman run --rm --runtime runsc alpine dmesg`. The output starts with `Starting gVisor...`. [issue] 11543 shows this output.
4. Choose the network flag by spike S1. Values are `sandbox` (default), `host` and `none`. [src] `runsc/config/flags.go:172`
5. Choose the platform. `systrap` is the default. `kvm` is best on bare metal. `/dev/kvm` is mode 0666 here. [doc] `g3doc/architecture_guide/platforms.md`

Why each flag:

| Flag | Reason | Source |
|---|---|---|
| `ignore-cgroups` | Without it, `runsc` asks systemd for a scope and fails with "Interactive authentication required". | [issue] 11543 |
| `network=host` | Uses the host kernel TCP/IP stack inside the container netns. Raw sockets stay off (`--net-raw` defaults to false). | [src] `flags.go:172-175` |
| `host-uds=open` | Lets the sandbox connect to a Unix socket that you bind-mount. Default is `none`. | [src] `flags.go:156` |
| `overlay2` | Default is `root:self`. The root filesystem changes stay inside the container. | [doc] `g3doc/user_guide/filesystem.md` |

Do not pass `--runtime-flag` on the command line and also set `runtimes_flags`. A flag on the command line replaces the config list. [src] `oci_conmon_common.go:85`

### 2.3 What does not work or is not proven

| Item | Fact | Tag | Source |
|---|---|---|---|
| Netstack (`network=sandbox`) in rootless | The gVisor team says it needs `CAP_NET_ADMIN` on host namespaces. Work to attach netstack to a Unix socket began on 2026-09-02. The guide says netstack works with a TAP device and a user-mode stack. One user got "cannot run with network enabled in root network namespace" with pasta. Another user says pasta works now. These reports conflict. | [issue] [doc] | issue 10359, issue 11543, `rootless.md` |
| `network=plugin` / `--network-proxy-path` | Experimental. The sentry writes IP packets to a `SOCK_SEQPACKET` socket of an external peer. The proxy serves only the primary interface. | [doc] | `g3doc/user_guide/networking.md` |
| Cgroup limits | Podman `--memory` and `--cpus` have no effect with `ignore-cgroups`. gVisor enforces limits only through a host cgroup. | [doc] [inference] | `compatibility.md` |
| SELinux | `runsc` refuses to run in any SELinux context except unconfined. This host has no SELinux. | [issue] | issue 11543 (comment of 2026-10-26) |
| Runtime arguments | `runsc` fails on `--no-new-keyring` and `--preserve-fds=` from Podman. Issue 15774 is open. | [issue] | issue 15774 |
| Nested Podman | Works only with host network and the `vfs` driver. `newuidmap` needs `--allow-suid`. Issue 13944 is open. | [issue] | issue 13944 |
| Systemd in the container | Not reliable. A NixOS boot failed. | [issue] | issue 11904 (closed) |
| Docker DNS rules | The Docker `127.0.0.11` NAT rules are not copied. This affects Docker, not Podman. | [issue] | issue 7469 |
| k3s, kind | Issue 14637 "Run stock k3s in gVisor" is open. | [issue] | issue 14637 |
| Block devices, KVM in the sandbox | Not supported. | [doc] | `compatibility.md` |
| `io_uring` | Off by default. | [doc] | `compatibility.md` |
| ssh into the sandbox | The sandbox needs no sshd. Use `podman exec -it`. | [inference] | |

### 2.4 Minimum versions

No source states a minimum Podman or `runsc` version for this use. These are the versions that I read or that the design needs.

| Tool | Version | Reason |
|---|---|---|
| Podman | 6.1.4 (installed). 5.6 or newer for stable `podman artifact`. 6.0 for `--route` blackhole. | [doc] release notes 5.6.0, 6.0.0 |
| Netavark, aardvark-dns | 2.1.0 (installed). Podman 6.0 needs 2.0.0 or newer. | [doc] 6.0.0 notes |
| pasta | The only rootless network in Podman 6. Podman 6 removes `slirp4netns`. Old advice that names slirp4netns does not apply. | [doc] 6.0.0 notes |
| `runsc` | `release-20261102.0` (read). The rootless guide exists from 2026-04-01. Rootless directfs exists from 2023-05-13. | [src] commit history of the files |
| `podman-compose` | 1.6.0. `runtime` support exists from 1.1.0. | [src] `docs/Changelog-1.1.0.md` |
| SPIRE | 1.16.0 for the rootless Podman option `use_rootless_podman`. | [doc] SPIRE CHANGELOG 1.16.0 |
| Caddy | 2.11.0 for `SIGUSR1` reload and the automatic `Host` header to HTTPS upstreams. | [doc] `command-line.md`, `reverse_proxy.md` |

### 2.5 Compose, Quadlet and `podman kube play`

| Topic | Compose (`podman-compose`) | Quadlet | `podman kube play` |
|---|---|---|---|
| One file | Yes, `compose.yaml` | No. One file for each container, network and secret. | Yes, one YAML |
| Runtime for each container | Yes. `runtime:` becomes `--runtime`. [src] `podman_compose.py:1464` | `PodmanArgs=--runtime=runsc` or `ContainersConfModule=`. There is no `Runtime=` key. [doc] | No option. Use the global `podman --module runsc.conf kube play`. [doc] [inference] |
| Internal network, aliases | Yes. It supports `internal` and `aliases`. [src] `podman_compose.py:1077, 1185` | `.network` with `Internal=true`, `NetworkAlias=`. [doc] | Possible with `--network` |
| Inline `configs` | Ignored. Bind-mount the Caddyfile. [src] | `Volume=` or `.container` mounts | `ConfigMap` |
| Env secrets | Not supported at run time. File secrets work as bind mounts. [src] `podman_compose.py:825-835` | `Secret=` with `type=env` or `type=mount` | `Secret` kind |
| Boot start | Needs `podman-compose` systemd unit | Native systemd | `.kube` Quadlet |
| Separate netns for sandbox and Caddy | Yes | Yes, if you do not use `.pod` | No. A pod shares one netns, so the sandbox could reach Caddy on localhost. |
| Resource limits | None with `ignore-cgroups` | Set `MemoryMax=` and `CPUQuota=` on the service. Quadlet adds `--cgroups=split`. [src] `quadlet.go:681` [inference] | None |

The `docker-compose` provider (v5.7.0) sends `HostConfig.Runtime`. The Podman compat code in `pkg/api/handlers/compat/` has no use of that field. So the runtime is probably ignored. [src] [inference] `podman compose` picks `docker-compose` before `podman-compose` when both exist. [doc] `podman-compose.1.md.in` Set `PODMAN_COMPOSE_PROVIDER` to choose `podman-compose`.

Pick: Compose file with `podman-compose` for the bundle. Pick Quadlet when you want boot start and limits. Reject `kube play` and `.pod`, because they share one network namespace.

## 3. Caddy is the only way out, and out of reach (question B)

### 3.1 Network layout

```
 sandbox container --- inner network (internal, no gateway) --- caddy container --- outer network --- pasta --- internet
```

| Claim | Tag | Source |
|---|---|---|
| An `--internal` bridge network gets no default route. IP forwarding is off on the bridge. aardvark-dns resolves container names and aliases only. Other names get `NXDOMAIN`. | [doc] | `podman-network-create` option `--internal` |
| Netavark sets up no firewall rules for an internal network. | [src] | `netavark/src/network/bridge.rs:365-367` |
| aardvark-dns answers `NXDOMAIN` and does not forward when the requester is only on internal networks. | [src] | `aardvark-dns/src/dns/coredns.rs:215-222`, `backend/mod.rs:138` |
| A network alias on Caddy resolves for the sandbox. `--network-alias` can repeat. The alias has no wildcard form. | [doc] [src] | `options/network-alias.md`, `config/mod.rs:182-186` |
| A container can join two networks. | [doc] | `options/network.md` |
| No firewall rules on an internal network means no port forwarding to it. So `-p` on the sandbox does not work. Publish ports on Caddy instead. | [src] [inference] | `bridge.rs:365` |
| Podman 6 can add `blackhole`, `unreachable` and `prohibit` routes with `podman network create --route`. Use them on the outer network for RFC 1918 ranges. | [doc] | Podman 6.0.0 release notes |
| `--userns=auto` gives the sandbox a separate subuid range. If the sandbox escapes gVisor, it is not the host user. It then cannot ptrace Caddy or read its files. | [doc] [inference] | `options/userns.container.md` |

### 3.2 What the sandbox cannot reach

| Target | Why not | Tag |
|---|---|---|
| Podman socket | Nothing mounts it. | [inference] |
| Caddy admin API (port 2019) | Default bind is `localhost:2019` inside the Caddy netns. The sandbox has another netns. Set `admin off` or a Unix socket in a Caddy-only path. | [doc] `caddyfile/options.md` (`admin`) |
| Caddy config and env | Separate container, mount and PID namespace. Do not share `/data/caddy`. The CA private key is in `pki/authorities/local/`. Share only `root.crt`. | [doc] `running.md:134, 360` |
| Caddy secrets | Mount Podman secrets in Caddy only. | [inference] |
| Host loopback | `network=host` in `runsc` means the container netns, not the host netns. Never pass `--network=host` to Podman. | [doc] `options/network.md` |
| Internet by IP | No route on the inner network. | [doc] |
| Other containers | Only containers on `inner` are on-link. Podman 6 isolates networks by default. | [doc] 6.0.0 notes |

### 3.3 gVisor netstack and this design

With netstack, the sentry opens one `AF_PACKET` socket on the container device. The sentry makes no host sockets. [doc] `architecture_guide/networking.md` With `network=host`, the sandbox uses host sockets in the container netns. This lowers gVisor network isolation to the Linux network namespace. The route table and the bridge then enforce the policy. gVisor says that network policy belongs at the container level. [doc] `architecture_guide/security.md` The design already puts the policy there.

### 3.4 Bypass risks

| Vector | Result | Tag |
|---|---|---|
| DNS to another resolver | No route. Only the bridge IP answers, with `NXDOMAIN` for other names. | [src] |
| DoH, direct IPs, UDP | No route except to Caddy and the bridge IP. Caddy listens on TCP 80 and 443 only. | [inference] |
| IPv6 | The network has no IPv6 unless you add `--ipv6`. Also set `--sysctl net.ipv6.conf.all.disable_ipv6=1`. | [doc] [inference] |
| Raw sockets | `runsc` removes `CAP_NET_RAW` unless `--net-raw`. | [src] `flags.go:175` |
| Domain fronting through Caddy | Set `servers { strict_sni_host on }`. Caddy then answers `421` when SNI and `Host` differ. | [doc] `options.md` |
| Allowed host as a relay | Not solved. Any allowed host can receive stolen data. Token scope is the only limit, as in msb. | [repo] README record 2 |
| An allowed name that resolves to a private IP | Caddy dials it from the outer network. Add blackhole routes for private ranges on the outer network. | [inference] |
| `X-Forwarded-*` headers | Caddy adds them to the upstream request. Remove them with `header_up -X-Forwarded-*`. | [doc] `reverse_proxy.md` |
| Same host user | All rootless containers run as the same host user unless you set `--userns=auto`. A gVisor escape then reaches the Caddy container. | [inference] |

## 4. Caddy as egress proxy and secret swap (question C)

### 4.1 Caddy has no MITM forward proxy

Caddy v2.11.9 core has these HTTP handler modules only: `authentication`, `copy_response`, `copy_response_headers`, `encode`, `error`, `file_server`, `headers`, `intercept`, `invoke`, `log_append`, `map`, `push`, `request_body`, `reverse_proxy`, `rewrite`, `static_response`, `subroute`, `templates`, `timeouts`, `tracing`, `vars`. None handles `CONNECT`. [src] `grep` of `ID:` in `modules/caddyhttp/`. The `forward_proxy_url` field in `reverse_proxy` sets an upstream proxy. It is not a forward proxy. [src] `httptransport.go:94-98`

### 4.2 Options

| Option | Allow list | Header swap | Notes |
|---|---|---|---|
| 1. `forwardproxy` plugin | Yes. `acl` allows or denies by host, CIDR and file. | No. It tunnels `CONNECT`. It cannot read headers. | README says "EXPERIMENTAL". Last release tag is 2019. Master had a commit on 2026-03-21. The client talks to the proxy over HTTPS. [src] |
| 2. `caddy-l4` | Yes. Match `tls sni`. Use `proxy {l4.tls.server_name}:443` for any allowed name. | No. It passes TLS bytes. | v0.1.2. Matches `ssh`, `http` and `tls`. Also fits TLS to a host that has no secret. [src] `docs/examples/tls_sni_dynamic_upstreams.md` |
| 3. Reverse proxy for each host, internal CA | Yes. One site block for each host. | Yes. `header_up` with a regexp replacement. | Needs DNS aliases and CA trust in the sandbox. Standard modules only. |
| 4. mitmproxy | `allow_hosts`, `ignore_hosts`, `block_global`, `block_private`. HTTP/2 on. [doc] | Yes, with a Python addon. | Python runtime in the egress container. `stream_large_bodies` exists. SSE needs a test. |
| 4. Envoy | Yes, in config. | The credential injector filter sets a Basic or Bearer header from an SDS secret. It is for workload auth. | Envoy speaks SPIFFE through SDS. The old `.sbx` used Envoy. [repo] [src] `credential_injector.proto` v1.40.2 |
| 4. Squid `ssl_bump` | `peek`, `splice`, `bump`, `terminate`. | The doc page does not describe header rewrite. | Not verified. [doc] |

Pick: option 3 for hosts that carry a secret. Pick option 2 for other allowed hosts. A custom Caddy build (`xcaddy`) adds the `layer4` module. Option 3 alone is enough to start. [inference]

### 4.3 How option 3 works

1. The Caddy container has a network alias for each allowed host on the inner network. The sandbox resolves `api.anthropic.com` to Caddy.
2. Caddy has one site block for each host, with `tls internal`. The local CA issues a leaf certificate (default lifetime 12 hours). [doc] `tls.md`
3. The sandbox trusts the CA root. Set `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `GIT_SSL_CAINFO` and `CURL_CA_BUNDLE` in the image. [inference]
4. `reverse_proxy https://<host>` sends the request upstream. Since 2.11.0, Caddy sets `Host` to the upstream by itself. [doc]
5. `header_up` replaces the placeholder:

```caddy
{
	admin off
	servers {
		strict_sni_host on
	}
}

api.anthropic.com {
	tls internal
	reverse_proxy https://api.anthropic.com {
		header_up Authorization "^Bearer PLACEHOLDER_CLAUDE$" "Bearer {file./run/secrets/claude_token}"
		header_up -X-Forwarded-*
	}
}
```

| Claim | Tag | Source |
|---|---|---|
| Syntax: `header_up [+\|-]<field> [<value\|regexp> [<replacement>]]`. Two arguments after the field mean search and replace. The regexp is RE2. The replacement expands `$1`. | [doc] | `reverse_proxy.md:136, 503-505` |
| The Caddyfile three-argument form sets `SearchRegexp`. The replacement text goes through `repl.ReplaceKnown` at each request. So `{env.X}` and `{file./abs/path}` work in it. | [src] | `headers/caddyfile.go:269-284`, `headers/headers.go:313-314` |
| `{file.<abs path>}` reads the file at each replace call, and trims one final newline. | [src] | `replacer.go:368-385` |
| `{env.X}` reads `os.Getenv` at each request. | [src] | `replacer.go:457-461` |
| A secret that holds `$` breaks: `ReplaceAllString` expands it. Tokens used here have no `$`. | [src] [inference] | `headers.go:319` |
| `strict_sni_host on` answers `421` when SNI and `Host` differ. | [doc] | `options.md:1356` |
| Caddy flushes at once for `text/event-stream` responses. | [doc] | `reverse_proxy.md:441-445` |
| Caddy proxies WebSocket. A config reload closes WebSocket connections. `stream_close_delay` delays the close. | [doc] | `reverse_proxy.md:433-437, 455` |
| `SIGUSR1` reloads the config and can reload certificates from disk. | [doc] | `command-line.md:702-708` |
| gRPC works through `h2c` and `h2` transports. | [doc] | `reverse_proxy.md:188, 197` |
| Root CA path: `/data/caddy/pki/authorities/local/root.crt`. Caddy cannot install it in a container as non-root. | [doc] | `running.md:360`, `tls.md:456` |

Live rotation: msb applies a new secret only to new connections. [repo] `microsandbox-credential-injection.md` Caddy reads `{file.…}` at each request, so a rotation reaches open connections. This is an improvement. [src] [inference]

Claude API shortcut: Claude Code reads `ANTHROPIC_BASE_URL`. [repo] `sandbox-boot` sets it for Headroom. Point it at `http://caddy:8080` on the inner network. Then the Claude path needs no CA and no DNS alias. [inference]

### 4.4 Other traffic

| Traffic | Caddy result |
|---|---|
| HTTP/2, SSE, WebSocket, gRPC | Supported by `reverse_proxy`. SSE needs spike S3. |
| `git` over https | Works as HTTPS. Basic auth carries the token. See the Basic row below. |
| `git` over ssh | Not covered. `caddy-l4` can proxy one fixed `host:22`. It cannot choose by name. Keep https remotes. [src] [inference] |
| HTTP/3 (UDP 443) | Not needed. Caddy can serve it. Leave it off. |
| Hosts with no secret | Option 2 SNI pass-through. No CA needed for these clients. [inference] |

### 4.5 msb secret features that Caddy lacks

| msb feature | Caddy status |
|---|---|
| Auto placeholder `$MSB_<NAME>` and env var in the guest | Missing. You choose the string. A generator script writes both sides. |
| One host list for each secret, matched on SNI, `Host` and DNS pin | Partial. A site block and `strict_sni_host` cover SNI and `Host`. DNS pin is not needed: the sandbox resolves only Caddy. |
| Violation action (`block`, `log`, `passthrough`) and `passthrough` hosts | Missing. Write a `header_regexp` matcher with `respond 403` for each named header. Caddy cannot scan all headers. |
| Query swap | Partial. Use `rewrite` or `uri query` with the same placeholder. |
| Body swap (HTTP/1 up to 16 MiB) | Missing in core. Needs a plugin. Not tested. |
| Basic-auth swap that decodes base64 | Missing. Store the full base64 `user:token` as the secret. Replace the whole header value. |
| Wildcard hosts (`*.githubusercontent.com`) | Partial. A wildcard site block with on-demand `tls internal` works. DNS aliases have no wildcard. Add a DNS answerer. |
| Any TCP port by host name | Missing. Only `caddy-l4` SNI and HTTP matches. |
| TLS bypass for named hosts | Same as option 2 pass-through. |
| Per-connection snapshot of secrets | Different. Caddy reads at each request. Better for rotation. |
| Request log with the violation | Partial. Caddy JSON access log. Keep tokens out of logs. |
| Auto CA in the guest trust store | Missing. Bake the root into the image. |
| Host reachability `host.microsandbox.internal` | Replaced. Use `host.containers.internal` (pasta `--map-guest-addr 169.254.1.2`) from the Caddy container. [doc] `options/network.md` |

## 5. SPIFFE and SPIRE in this design (question D)

### 5.1 Attestors for rootless Podman

| Attestor | Fit | Source |
|---|---|---|
| `docker` with `use_rootless_podman = true` | Best fit. SPIRE finds the 64-hex container ID in the cgroup of the peer PID. It asks the user's Podman socket for labels. The default path template is `/run/user/%d/podman/podman.sock`. Pair it with `unix:uid`. New in 1.16.0. | [doc] [src] `plugin_agent_workloadattestor_docker.md`, `docker_posix.go` |
| `unix` | Works for any process. Gives UID, path, SHA-256. It cannot tell two containers apart. | [doc] |
| `systemd` | Does not fit. It uses the system D-Bus only. Rootless units sit under `user@1000.service`. The earlier spike found the same. | [src] `systemd_posix.go:104` [repo] |
| `k8s` | Does not fit. No kubelet. | [doc] |

The doc warns: the user controls the Podman socket, so a workload can present its own labels. Use `unix:uid` with the label selectors. [doc] SPIRE 1.16.0 removed the `mountinfo` fallback because it can be forged. [doc] CHANGELOG 1.16.0

### 5.2 KEY RISK: the peer of the socket under gVisor

| Claim | Tag | Source |
|---|---|---|
| When the sandbox connects to a Unix socket, the sentry asks the gofer to connect. The gofer calls `unix.Connect` on the host. The sentry gets the connected file descriptor. | [src] | `pkg/sentry/fsimpl/gofer/directfs_inode.go:878-885`, `runsc/gofer/fs/lisafs.go:902-930` |
| So `SO_PEERCRED` shows the gofer process, not the sandbox application. | [src] [inference] | same |
| The gofer can set its effective UID and GID to the application values before `connect`. So the peer UID can differ from the gofer UID. | [src] | `lisafs.go:937-994` |
| The connect needs `--host-uds=open` and a socket that a mount exposes. Default is `none`. | [src] | `lisafs.go:903-907`, `flags.go:156` |
| gVisor changed this code on 2026-10-21 ("Connect to host unix sockets with the application's supplementary groups"). | [src] | commit `37bbffde` |
| `runsc` starts the gofer inside the container cgroup when it makes the cgroup. With `--ignore-cgroups` it makes none. The gofer then stays in the cgroup of its parent. | [src] | `runsc/container/container.go:411-464` |
| The parent is the process that Podman started, with conmon. With the systemd manager, conmon sits in `libpod-conmon-<id>.scope`. This name has the container ID. The SPIRE regexp `\b[[:xdigit:]]{64}\b` finds it. The `libpod-` match selects the Podman socket. | [src] [inference] | `containerinfo/extract.go`, `docker_posix.go:26` |
| Quadlet adds `--cgroups=split`. Conmon then stays in the service cgroup, and its path has no container ID. The docker attestor then finds nothing. | [src] [inference] | `quadlet.go:681` |

Result: the Workload API socket probably works from inside gVisor, because the gofer connects for the sandbox. The identity that SPIRE sees is the gofer cgroup. It is the sandbox identity only when the cgroup holds the container ID. This works with `podman-compose` and `--ignore-cgroups`. It fails with Quadlet. [inference] Spike S4 decides.

### 5.3 Alternatives

| Option | Result |
|---|---|
| `spiffe-helper` writes the SVID files to a volume | Simple. The key is in the sandbox. This breaks the rule that the sandbox holds no key. `spiffe-helper` sends `SIGUSR1` by default, which Caddy accepts for reload. [src] `spiffe-helper/README.md`, `command-line.md` |
| TCP Workload API proxy | The SPIFFE spec allows TCP only with strong network proof. The agent sees the proxy, not the workload. [spec] [repo] `microvm-workload-attestation-spire.md` section 4 |
| **Caddy holds the SVID** | Best. Caddy is a normal container. Caddy uses `client_certificate_file` and `client_certificate_key_file` for the MCP gateway. It loads them at config load. A new SVID needs `SIGUSR1`. The sandbox has no identity. [src] `httptransport.go:749-809` |
| No identity | Smallest. |

Does a proxy speak SPIFFE mTLS? Envoy does, through SDS and a SPIFFE certificate validator. [src] `tls_spiffe_validator_config.proto` Caddy has no SPIFFE module. A search of GitHub found none. Caddy cannot match a SPIFFE URI SAN. It matches DNS names only. [inference]

### 5.4 What the sandbox identity does

The documented use is mTLS to the MCP gateway, so that the gateway sees which machine calls. The JWT carries the user. [repo] `mcp-client-workload-identity.md` The old design had Envoy hold the SVID. Caddy replaces Envoy in that role. The sandbox itself needs no identity for any other task in this repo. [repo] [inference]

### 5.5 Is it simpler than the msb flow?

| Part | msb flow | Podman flow |
|---|---|---|
| Custom code | `msbvm` plugin and delegate, 972 lines of Go | None, if the docker attestor works |
| Agents | Host agent and a second agent in the VM | Host agent only |
| Node certificate in the VM | Yes, mounted at `/run/sandbox/node` | No |
| Registration entries | Node entry, delegate entry, one entry for each VM | One entry for each container, with Podman labels and `unix:uid` |
| New host services | None | `podman.socket` for the agent, SPIRE 1.16.0 |
| Proof level | Spike on the host with a throwaway server | None yet |

Honest answer: it is simpler in parts and moves risk to the gofer cgroup. For a sandbox identity, SPIFFE adds little. For the Caddy identity, SPIFFE is a normal container case and is simple.

## 6. gVisor, libkrun, Kata (question E)

| Topic | gVisor (systrap or KVM) | libkrun microVM (msb, or `krun`) |
|---|---|---|
| Boundary | A user-space kernel (Sentry, pure Go) in a host process. No syscall passes to the host unchanged. The sentry has a small, fixed host syscall set. [doc] `security.md` | A guest Linux kernel behind KVM. The VMM serves virtio devices. [doc] libkrun `README.md` |
| Stops | Exploits of the host kernel System API from workload code. [doc] | Exploits of the host kernel from guest code. The guest kernel takes the syscalls. [inference] |
| Does not stop | Hardware side channels. Bugs in the sentry. Resource exhaustion without host cgroups. [doc] | Bugs in the VMM and devices. The VM boundary does not limit host resources that devices expose. [doc] libkrun `docs/security-model.md` |
| Official comparison | "one should not assume that the mere use of virtualization hardware makes a system more or less secure". [doc] `security.md` FAQ | Same |
| Platform | `systrap` default. `kvm` on bare metal. `ptrace` unsupported. [doc] `platforms.md` | KVM only |
| Compatibility | Partial Linux ABI. No nested KVM. Weak systemd. [doc] | Full guest kernel. Nested Podman works, as in msb. [repo] |
| Network | Netstack or host stack | TSI or virtio-net |

TSI (libkrun): the guest socket calls go over virtio-vsock to the VMM. The VMM runs them in "the VMM's host network context". The doc tells you to run the VMM in a dedicated network namespace. It supports `AF_INET`, `AF_INET6` and `AF_UNIX`, stream and datagram only. No raw sockets. Hijacking `AF_UNIX` lets the guest connect to host sockets that the VMM can reach. [doc] libkrun `docs/networking.md`, `docs/security-model.md`

Podman with `krun`:

| Claim | Tag | Source |
|---|---|---|
| `krun` is a name Podman knows. It is in `runtime_supports_kvm` and `runtime_supports_nocgroup`. | [src] | `containers.conf:720-728` |
| `krun` is `crun` with the libkrun feature on. | [doc] | `crun/krun.1.md` |
| crun adds `/dev/kvm` to the spec by itself. | [src] | `krun.c:837, 902` |
| Annotations set the VM: `krun.cpus`, `krun.ram_mib`, `krun.use_passt`, `krun.tap_name`. Default network is TSI. | [doc] | `krun.1.md` |
| crun calls `krun_start_enter` in the container process. So the VMM runs in the container namespaces and cgroup. | [src] [inference] | `krun.c:613` |
| crun sets no TSI flags. The libkrun default decides if the guest can hijack `AF_UNIX`. | [src] [inference] | `krun.c` |
| Because the VMM sits in the container cgroup, the docker attestor sees the container ID, also with Quadlet. | [inference] | |
| Host state: no `krun` or `crun` on this host. | [repo] | |

Kata: Kata runs the VMM as an unprivileged user for runtime-rs shims. The shim and `virtiofsd` still run as root. [doc] `docs/how-to/how-to-run-rootless-vmm.md` This is not rootless Podman. Kata does not fit this host. [inference]

Comparison:

| Feature | msb microVM | Podman + gVisor + Caddy | Podman + krun + Caddy |
|---|---|---|---|
| Boundary | libkrun VM | User-space kernel | libkrun VM |
| Rootless | Yes | Yes (needs config) | Yes (not tested) |
| One YAML | `sandbox.yaml` | `compose.yaml` | `compose.yaml` |
| Egress control | msb host rules | Caddy + internal network | Caddy + internal network |
| Secret swap | Built in | Caddy, partial | Caddy, partial |
| Live rotation | New connections only | Each request | Each request |
| Nested Podman | Yes | Host net, `vfs` only | Yes |
| k3s, systemd in sandbox | Yes | No | Yes |
| Resource limits | `cpus`, `memory` | Service cgroup only | `krun.cpus`, `krun.ram_mib` |
| Identity | Delegate flow | Gofer cgroup, unproven | VMM cgroup, unproven |
| Editor and shell | ssh proxy | `podman exec -it` | `podman exec -it` |
| Packaging | OCI image + yaml in git | OCI artifact | OCI artifact |
| Maturity | Beta v0.7 | CI covers `echo` | No data on this host |

## 7. Feature map from msb to Podman (question F)

| msb feature | Podman equivalent | Status |
|---|---|---|
| `image.oci` with digest | `image: ghcr.io/...@sha256:...` in `compose.yaml` | Same |
| `registry` login with `GITHUB_TOKEN` | `podman login ghcr.io` or `bws run -- podman login` | Same |
| `cpus`, `memory` | `krun.*` annotations, or systemd limits on a Quadlet service. None with gVisor and Compose. | Gap with gVisor |
| `env` | `environment:` | Same |
| `network.allow` | Generated Caddyfile and aliases | Changed |
| Wildcard hosts | Wildcard site block and a DNS answerer | Gap |
| `secrets` with `allow` | Caddy `header_up` rules | Partial (section 4.5) |
| `passthrough` | Matcher rules | Gap |
| `network.tls.bypass` | `caddy-l4` pass-through | Changed |
| `network.ports` (8787) | `-p 127.0.0.1:8787:8787` on Caddy, which proxies to the sandbox | Changed |
| `host.microsandbox.internal:6443` and `K8S_TOKEN` swap | Caddy to `https://host.containers.internal:6443`, with `tls_trust_pool` for the k3s CA and `header_up` | Same |
| Mount `.git` read-only and clone | `--mount type=bind,ro` | Same |
| Named volumes | Podman named volumes | Same |
| Omarchy theme mount | Bind mount | Same |
| `ssh` into the VM | `podman exec -it sandbox bash -l`. The 1 MB `msb exec` limit does not apply. | Better [inference] |
| TTT, Herdr | Same image. `podman exec -it` | Same |
| Image build and push | `podman build`, `podman push`, `yq` digest pin | Same |
| `config-sha` fingerprint | `podman-compose config` hash in a label | Changed |
| `just msb run/rm/shell/edit` | `just sandbox up/down/shell/edit` over `podman-compose` | Changed |
| `bws run` secret load | `bws run -- podman secret create` or env on the Caddy service | Same |
| Nested Podman builds | gVisor: gap. `krun`: same. | Gap with gVisor |
| `/dev/fuse`, `/dev/net/tun` | Not needed with `krun`. Gap with gVisor. | Gap with gVisor |
| k3s API access | Through Caddy | Same |
| SPIRE agent in the VM | Removed | Simpler |
| `msb doctor` | `podman info` and a script | Changed |
| Boot step `sandbox-boot` | Container `entrypoint` | Changed |

## 8. OCI artifact packaging (question G)

| Option | What it packs | Consume | Notes |
|---|---|---|---|
| `docker compose publish` | Only the compose YAML files, `env_file` files and local `extends` files. The artifact type is `application/vnd.docker.compose.project`. It warns on bind mounts and secrets. `--resolve-image-digests` pins tags. [src] | `docker compose -f oci://...`. Remote OCI is on by default in v5.7.0. [src] `pkg/remote/oci.go:75` | `podman-compose` cannot publish or read it. Inline the Caddyfile in `configs.content`. Only `docker-compose` handles it, and the runtime issue applies. |
| `podman artifact add` + `push` | Any files. Each file is one layer. The `title` annotation names the layer. `--type` sets the artifact type. [doc] | `podman artifact pull`, `podman artifact extract`, or `--mount type=artifact`. Stable since 5.6. | No new tool. `pull` takes a `SignaturePolicyPath`, so `policy.json` applies. [src] `abi/artifact.go:71` |
| ORAS | `oras push <ref> file:type ...` | `oras pull` | One more tool. |
| `flux push artifact` | A tar.gz layer. Config type `application/vnd.cncf.flux.config.v1+json`. Layer type prefix `application/vnd.cncf.flux.content.v1`. [src] | `flux pull artifact` | Already used here: `code/mcp-sandbox/.../platform-pipeline/justfile`, `code/ephemeral-env/justfile`. [repo] |

Pick: `podman artifact` for the bundle (no new tool), or `flux push artifact` (repo precedent). Both keep the whole directory: `compose.yaml`, `Caddyfile`, `runsc.conf`, Quadlet files and a README. [inference]

Digest pinning:

1. Pin every `image:` to `@sha256:`. `just sandbox build` writes the digest with `yq`, as `just msb build` does today. [repo]
2. Pin the artifact by digest in the run script: `…/sandbox-bundle@sha256:…`.
3. Pin `runsc` and `caddy` by checksum.

Signing:

1. `cosign sign <image>@sha256:...` signs by digest. The same command signs an artifact. cosign docs say to sign by digest. [doc] `cosign_sign.md`, v3.1.4
2. `cosign verify` runs before `podman artifact pull`.
3. Podman can enforce signatures at pull. `policy.json` supports `sigstoreSigned` with `keyPath` or Fulcio. [doc] `containers-policy.json.5.md`
4. Risk: cosign 3 writes a new bundle format by default. Test that `containers/image` reads it. Not verified. [inference]

## Plan before the spikes

The section "Update of 2026-11-08" has the current plan. The plan below is the earlier version for gVisor and Caddy.

All steps keep `.msb/` unchanged until step 20. Spikes S1 to S7 run first. Each spike uses a throwaway directory and a throwaway Podman network. The owner approves any download of `runsc`, `caddy`, `crun-krun` or `spire-agent`.

### Phase 0: spikes (riskiest first)

1. **S1: gVisor, rootless, networking.** Install `runsc` to `~/.local/bin`. Write `runsc.conf` (section 2.2). Test `network=sandbox`, then `host`, then `none`.
   - verify: `podman run --rm --runtime runsc alpine dmesg | head -3` prints `Starting gVisor`.
   - verify: `podman run --rm --runtime runsc alpine wget -qO- https://example.com` works in the mode you keep.
   - verify: write the result for each mode in a table.
2. **S2: Caddy as the only route out.** Create `inner` (`--internal`) and `outer`. Run Caddy on both with `--network-alias api.example.test`. Run the sandbox on `inner` only. Do it with runc first, then `runsc`.
   - verify: in the sandbox, `ip route` shows no default route.
   - verify: `wget -T3 https://1.1.1.1` fails. `nslookup example.org` returns `NXDOMAIN`.
   - verify: `wget -T3 http://caddy:2019` fails. `wget https://api.example.test` returns the Caddy answer.
   - verify: `podman ps` shows no socket mount. `podman inspect sandbox` shows no `/run/user` bind.
3. **S3: secret swap and SSE.** Make a local upstream container that echoes request headers. Put the alias on Caddy. Use the Caddyfile of section 4.3 with `{file./run/secrets/…}`.
   - verify: the echo shows the real test value. The sandbox env shows only the placeholder.
   - verify: change the secret file. The next request on the same keep-alive connection shows the new value.
   - verify: stream a test SSE source through Caddy with `curl -N`. Chunks arrive within 1 s of each other.
   - verify: set `ANTHROPIC_BASE_URL=http://caddy:8080` and run `claude -p "hi"` once. The Caddy log shows `200` and no token. Do not print the token.
4. **S4: SPIRE socket from gVisor.** Run `spire-agent` 1.16.0 on the host with `WorkloadAttestor "docker" { plugin_data { use_rootless_podman = true  verbose_container_locator_logs = true } }`. Bind-mount only the socket folder. Use `--host-uds=open`.
   - verify: `spire-agent api fetch x509` inside the sandbox returns an SVID.
   - verify: the agent log shows the PID and the cgroup path. Write both down.
   - verify: repeat with runc, with `--cgroups=split` (Quadlet) and with `krun`. Fill a table of selectors.
5. **S5: `krun`.** Install `crun-krun` and libkrun. Repeat S2 and S4 with `--runtime krun`.
   - verify: `podman run --rm --runtime krun alpine uname -r` prints a guest kernel.
   - verify: nested `podman run alpine true` works in the guest.
   - verify: TSI traffic leaves only through the inner network (the S2 tests).
6. **S6: Compose.** Write the bundle with `podman-compose` 1.6.0. Test with `docker-compose` 5.7.0 on the Podman socket too.
   - verify: `podman inspect -f '{{.OCIRuntime}}' <ctr>` shows `runsc` for the sandbox and the default for Caddy.
   - verify: with `docker-compose`, the same command shows if `docker-compose` dropped `runtime:`.
7. **S7: artifact and signature.** Push a test bundle to `ghcr.io/raghav19/engineersdaybook/sandbox-bundle`. Sign with `cosign sign --key`.
   - verify: `cosign verify --key cosign.pub <ref>@sha256:…` succeeds.
   - verify: `podman artifact pull` with a `sigstoreSigned` policy succeeds for the signed digest and fails for an unsigned one.
8. **Gate.** Fill the go or no-go table. S1 and S2 pass for the runtime. S3 passes. S4 gives a unique selector.
   - verify: the table is in the PR text. A person approves the choice of runtime.

### Phase 1: bundle skeleton (msb still runs)

9. Create `code/sandbox-bundle/` with `compose.yaml`, `Caddyfile`, `runsc.conf` and a README. Use the project layout rules of this repo.
   - verify: `podman-compose config` exits 0.
10. Write a script that turns `network.allow` of `sandbox.yaml` into aliases and site blocks. Give wildcard hosts a DNS answerer decision (open question 1).
   - verify: the script output has one site block for each non-wildcard host in `sandbox.yaml`.

### Phase 2: runtime and image

11. Reuse `.msb/image/` with a new `build` recipe. Pin the digest in `compose.yaml`.
   - verify: `grep '@sha256:' code/sandbox-bundle/compose.yaml` shows the image.
12. Move `sandbox-boot` steps that still apply into the container entrypoint. Drop the SPIRE agent, the FUSE and TUN steps if the runtime is `krun`.
   - verify: `podman exec sandbox claude --version` works.

### Phase 3: secrets and daily commands

13. Add `just sandbox up`, `down`, `shell`, `edit`. Load keys with `bws run`. Give secrets to the Caddy service only.
   - verify: `podman exec sandbox env | grep -c TOKEN` shows placeholders only. `podman exec caddy env` is not needed to read them.
14. Keep the claude-home, herdr, qwen-home and other named volumes.
   - verify: remove and recreate the containers. `claude --resume` still lists the old session.

### Phase 4: identity

15. If S4 passed, add the registration for the sandbox. Use `docker:label` plus `unix:uid`. Add the registration for Caddy.
   - verify: `spire-server entry show` lists both entries. Caddy presents the SVID to the MCP gateway in a test.
16. If S4 failed, register Caddy only. Remove the delegate flow for new sandboxes.
   - verify: the gateway log shows the Caddy SPIFFE ID.

### Phase 5: publish

17. Add `just sandbox publish`. It runs `podman artifact add`, `push`, `cosign sign`. It prints the digest.
   - verify: `cosign verify` and `podman artifact pull` succeed from a clean `XDG_DATA_HOME`.
18. Add `just sandbox pull <digest>`. It verifies, extracts and runs `podman-compose up -d`.
   - verify: on a clean user session, the command starts both containers.

### Phase 6: cutover and rollback

19. Run a parity checklist: Claude Code answers, `git push` works, `gh` works, `k3s` read works, Headroom dashboard opens on `127.0.0.1:8787`, TTT runs, a Podman build works, a blocked host fails.
   - verify: each item has a command and a pass in the PR text.
20. Tag `msb-final`. Move `.msb/` to a note in the README only after 30 days of daily use.
   - verify: `git tag --list msb-final` shows the tag.
21. Rollback: run `just msb run`. `.msb/` stays unchanged until step 20. Stop the bundle with `just sandbox down`.
   - verify: `msb ls` shows `sandbox-dev` running.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Rootless netstack does not work | Weaker gVisor network isolation | Use `network=host` in the container netns. The internal network enforces the policy. |
| Gofer cgroup gives no unique selector | No sandbox identity | Identity on Caddy. |
| Same host user for all containers | A gVisor escape reaches Caddy | `--userns=auto` for the sandbox. Test the volume ownership. |
| gVisor compatibility gaps | Nested Podman, k3s fail | Use `krun`. |
| Caddy lacks msb features | Fewer leak blocks | Matchers for named headers. Keep token scopes narrow. |
| Wildcard DNS | Wildcard hosts do not resolve | Add CoreDNS or dnsmasq. This is a third container. |
| Every client must trust the CA | Some tools fail | Env vars and a trust store step in the image. Use `ANTHROPIC_BASE_URL` for Claude. |
| Cert reload closes streams | Broken SSE and WebSocket on SVID rotation | `stream_close_delay`. Rotate at a quiet time. |
| `forwardproxy` is experimental and old | Supply chain | Do not use it. Use `caddy-l4`. |
| Custom Caddy build | Supply chain | Pin the `xcaddy` modules. Sign the image. |
| SPIRE 1.16.0 is 3 days old | Regressions | Pin and test in S4. |
| `runsc` rootless issues stay open | Upgrade breaks the sandbox | Pin `runsc` by checksum. Read the release notes. |
| Allowed host as relay | Data theft | Same as msb. Token scope. |
| Secret with `$` | Mangled token | Tokens here have none. Lint in the generator. |
| Port publish on an internal network | Dashboard unreachable | Publish on Caddy. |

## Open questions

1. Which DNS answerer serves wildcard hosts? Candidates are CoreDNS or dnsmasq in the Caddy container. Or drop wildcards and list hosts.
2. Does `network=sandbox` work with rootless Podman and pasta on this host? S1 answers.
3. Does a gVisor sandbox with `--userns=auto` connect to the SPIRE socket? The socket owner is the host user.
4. Does `containers/image` read cosign v3 bundle signatures?
5. Does `-p` work on a container in an internal network with no other network? The source says no firewall rules exist. S2 can test it.
6. Does libkrun in `crun-krun` hijack `AF_UNIX` by default? S5 answers.
7. Does `docker-compose` v5.7.0 pass the runtime to Podman? The source says no. S6 tests it.
8. Can Caddy do body swap? I read no plugin for it.
9. Which package source gives `crun-krun` on this host? Not tested.
10. Does Quadlet `MemoryMax=` limit a service whose sandbox runs under `runsc --ignore-cgroups`? Not tested.

## Not tested

No spike ran. `runsc` is not installed on this host. The permission system denied the download of the `runsc` binary. I did not retry. I ran only read-only commands: `command -v`, `podman info`, `ls`, `getfacl`, `git`, `gh api`, `curl` to the GitHub API. I did not run Caddy, SPIRE, `krun`, `cosign` or `oras`. All behavior claims for those tools come from docs and source. Source reads cover the tags in the Source line. I did not read third-party Caddy plugins other than `forwardproxy` and `caddy-l4`. I used no secret value.
