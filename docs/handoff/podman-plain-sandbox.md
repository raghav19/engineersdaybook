# Handoff: a plain hardened Podman sandbox with a host-side proxy

Written on 2026-11-09. The index of all handoff documents is `docs/handoff.md`. This document replaces the direction of [podman-krun-sandbox.md](podman-krun-sandbox.md). Read that one only for the spike results and the state of the host.

The owner changed direction in this session. The krun microVM sandbox is built and tested (PR #284 and #287), but the owner rejected it as too complex. The new sandbox is a plain rootless Podman container with no network. iron-proxy runs on the host and is its only way out. This handoff lets a fresh session continue without the old conversation. Read it, then read "Next steps".

## Goal

The owner wants a sandbox for AI agents (Claude Code, Qwen Code, Herdr, the TTT editor) that:

1. Runs from one declarative Compose file, started with `just sandbox run`.
2. Has no real secret inside. A proxy outside the sandbox swaps placeholders for real tokens and allows only listed hosts.
3. Has one way out: the proxy. No subnets, fixed IP addresses or proxy container.
4. Keeps the session after the terminal closes, and keeps the history of each agent in volumes.
5. Later: gives the sandbox a SPIFFE identity, if this needs no complex flow.
6. Later: ships as a signed OCI artifact. The host runs a pinned and verified digest.

The agent does not run containers inside the sandbox. CI builds and pushes the images. The owner accepted this on purpose.

## Read these first (do not copy them here)

- The rules of the repo: `AGENTS.md`. Before a PR, read `docs/agents/pull-requests.md` and `docs/agents/host-handoff.md`. Before a diagram, read `docs/agents/diagrams.md`. Before any text, run `/asd-ste100`.
- The first handoff: [podman-krun-sandbox.md](podman-krun-sandbox.md). The research note: `docs/research/podman-sandbox-runtimes.md`. The spike files: `docs/research/podman-sandbox-spikes/README.md`.
- The identity work for the msb microVM: `code/agent-workload-identity/docs/handoff/agent-workload-identity-status.md`.
- The code on the branch `sandbox-plain` (head `54b7766`): `.sandbox/README.md` (still the krun text, see "Next steps"), `.sandbox/compose.yaml`, `.sandbox/justfile`, `.sandbox/proxy/iron-proxy.yaml`, `.sandbox/image/sandbox-entry` and `.sandbox/egress-selftest.sh`.

## The path so far

| PR or branch | What it is | State |
|---|---|---|
| #282 | The research note and the first handoff | Merged |
| #283, #285, #286 | The image of the sandbox for krun (reverted once, then added again) | Merged |
| #284 | The compose file, the proxy container and the self-test (krun) | Open. Superseded by `sandbox-plain`. |
| #287 | `sshd`, the clone, volume owners, the first README and diagrams (krun) | Open. Superseded by `sandbox-plain`. Branch `sandbox-boot`, base `sandbox-compose`. |
| `sandbox-plain` | The plain-container sandbox with a host-side proxy. Head `54b7766`. | Pushed, no PR yet. The README is not rewritten. |

Do not close #284 and #287 before `sandbox-plain` has a PR and the owner agrees. Keep their branches.

## What the owner decided, in order

1. Use iron-proxy in its own process as the only way out (first handoff).
2. Use a krun microVM so that nested Podman needs no special privileges (first handoff). #284 and #287 built it.
3. The owner asked for one command (`just sandbox run`) that works like `just msb run`: it keeps running, attaches over ssh and resumes Herdr. Built in #287.
4. The owner rejected the network of #287: two networks, fixed IP addresses, a proxy container, an ext4 loop file, `sshd` and static uid maps. The tokens of the proxy container also sit in Podman storage.
5. The owner chose the plain hardened rootless container, `--network none`, a host-side iron-proxy and no nested containers. Anthropic's [secure deployment guide](https://code.claude.com/docs/en/agent-sdk/secure-deployment) describes this pattern.
6. The owner will add the SPIFFE identity and more hardening later.

The owner rejected or parked these options. Do not offer them again without a new reason:

| Option | Why not |
|---|---|
| A remote Podman socket for the agent | The socket gives full control of Podman as the host user |
| Bitwarden Agent Access SDK or OneCLI as the swap | Alpha, needs a human approval for each credential, and OneCLI replaces iron-proxy |
| Other VM products (smolvm, Matchlock, BoxLite, Kata) | Not tested. Parked. |
| A crun patch for a vsock port | Long term. crun never calls `krun_add_vsock_port2`. |
| Docker Sandboxes | Not tested for Linux |

## What is built on `sandbox-plain`

```text
just sandbox run
  _ca     make the CA (ca.crt and ca.key in ~/.local/state/sandbox)
  _bin    take the iron-proxy binary from the pinned image into the state folder
  _proxy  bws run -- systemd-run --user  iron-proxy  (tokens in its environment, tunnel on 127.0.0.1:1080)
  _bridge systemd-run --user  socat  proxy.sock (in $XDG_RUNTIME_DIR/sandbox) -> 127.0.0.1:1080
  build + podman-compose up -d sandbox      (only if the sandbox does not run)
  podman exec -it -u agent sandbox herdr
```

- **The sandbox.** `network_mode: none`, `cap_drop ALL` plus `SETUID`, `SETGID` and `SETPCAP`, `no-new-privileges`, default rootless user map. `sandbox-entry` runs as container root (the host user), trusts the CA, starts a relay (`socat`, 127.0.0.1:3128 to the socket, no capability) and drops to `agent`. `HTTPS_PROXY` points at the relay.
- **The proxy.** iron-proxy 0.56.0, pinned by digest in the justfile. All listeners are on the host loopback. The sandbox uses the tunnel (CONNECT) only.
- **Volumes.** Six named volumes with the option `uid=1000,gid=1000`. The option counts ids of the rootless user namespace, and in the default map these equal the ids in the container.
- **Removed from #287.** The networks, the fixed IP addresses, the proxy container, `sshd`, the ssh key, the ext4 loop file, the static uid maps, port 2222, `crun` and `libkrun`.

## Evidence from this session

All tests used dummy tokens and a stub for `bws`. The recipes ran as `just sandbox ...`.

| Test | Result |
|---|---|
| `just sandbox selftest` | All PASS. One SKIP: no `dig`. New tests: only `lo`, 403 for a host that is not listed (through CONNECT). |
| Cold start | `just sandbox run claude --version` printed `2.1.319 (Claude Code)` in 38 s |
| Attach to a running sandbox | 0.7 s. No build and no passphrase prompt. |
| Volumes | All six show `1000:1000` in the sandbox, and `agent` can write |
| From the sandbox | `api.github.com` gives 200. `example.com` gets CONNECT 403. `GH_TOKEN` is the placeholder. The only interface is `lo`. |
| Socket permission | `agent` cannot open `proxy.sock` (`Permission denied`). Only the relay (container root) can. |
| Proxy audit | One JSON line for each request. A call to `api.anthropic.com` with the dummy token gets 401. |
| Swap proof (spike, throwaway CA) | An echo host received `Bearer <real value>`. The container env held the real value 0 times. |
| Restart | After `just sandbox down` and a new `run` (35 s), the proxy and the sandbox came back. A marker file in `~/.claude` was still there, and the clone was on the branch `sandbox-plain`. |

Not tested:

- Real tokens end to end through the proxy (test N5 of the research note). The owner runs it.
- `git push`, Claude Code streaming through the tunnel, Headroom and Qwen Code through the proxy.
- `claude --continue` after `down`, and a second terminal in the same Herdr session.
- A crash of the proxy while the sandbox runs.
- Domain fronting and an SNI or `Host` header mismatch at the proxy.

## What the tests showed (facts to reuse)

- **Under krun, a Unix socket from the host fails.** A bind-mounted socket gives `ECONNREFUSED` in the guest. A plain container connects. [spike]
- **Default rootless mapping.** Container id 0 is the host user. Container id N (N >= 1) is the host id 100000 + N - 1. The container root can open a socket that the host user owns with mode 600. The container user `agent` cannot. A relay that runs as container root fixes this, and `keep-id` is not needed.
- **The volume option.** `uid=` of a local volume counts ids of the rootless user namespace, not host ids. `uid=100999` gave an owner that the container saw as 100999. Use `uid=1000`. A volume keeps the owner of its first creation, so remove a volume before you change the option.
- **Nested Podman in a plain container failed** in six configurations (dropped caps, `SETUID`, `SETGID`, `DAC_OVERRIDE`, `seccomp=unconfined`, a subuid range inside the container). The errors come from `newuidmap`: `write to uid_map failed` or `open of uid_map failed`. This is why the owner dropped nested containers. Under krun the same build worked as non-root with five caps.
- **Networks under krun** (TSI is the default): `pasta` and `bridge` give the guest the internet and block the host loopback. The internal network blocks both. `pasta` with `--map-host-loopback` reaches a host proxy, but leaves the internet open. A host process in the rootless network namespace (`podman unshare --rootless-netns`) is reachable from the internal network. It works and was not adopted.
- **crun and vsock.** libkrun has `krun_add_vsock_port` and `krun_add_vsock_port2`. `libcrun.so` (1.30.1) never calls them, and the krun manual has no annotation for them.
- **The Podman secret and env are on disk.** Plain env, a secret as env and a secret as mount all leave the value in the container storage while the container exists. `podman inspect` shows plain env only. Docker Sandboxes avoids this because its proxy is a host process.
- **iron-proxy secret sources.** The binary at 0.56.0 has `env`, `aws_sm`, `aws_ssm`, `1password`, `1password_connect` and `vault_kv`. The docs page at docs.iron.sh lists only the first five. There is no Bitwarden source and no command source. `ttl` re-reads a value without a restart (not for `env`).
- **iron-proxy has no SPIFFE support** (docs and README). `grpc` is the only mTLS option, to a policy server. agentgateway supports SPIFFE: it reads the verified SPIFFE ID as `source.spiffeId` (two third-party posts about v1.5.0, not the official docs).
- **The tunnel listener swaps tokens.** CONNECT in `mitm` mode intercepts TLS, and the allowlist and the swap apply (audit shows `"mode":"mitm"`).
- **The proxy has a deny list** for loopback and metadata addresses as upstream.
- **Podman remote works.** `podman --remote --url unix://... build` built an image on a temporary service socket. A socket proxy (for example `container-socket-proxy`) can limit the endpoints. Not adopted.
- **Bounding set of `podman exec`.** An `exec` session starts with the container's bounding set (`SETUID`, `SETGID`, `SETPCAP`), not with the empty set of the entry. `CapEff` is 0 and `no-new-privileges` is on. Treat it as a small gap.

## OpenBao and secret sources

The owner asked about OpenBao as a secret store. A research agent read the sources. The facts, with links:

- iron-proxy has a `vault_kv` source since [v0.50.0](https://github.com/ironsh/iron-proxy/releases). Fields: `mount`, `path`, `kv_version` (1 or 2, default 2), `json_key`, `ttl`, `failure_ttl`. It reads `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_NAMESPACE` and `VAULT_CACERT`. Static KV only. The README advises Vault Agent or Vault Proxy with auto-auth.
- OpenBao is MPL-2.0, a Linux Foundation project (OpenSSF Sandbox), forked from Vault 1.14 with the same API, and v2.7.2 came out on 2026-10-26. `bao agent` does auto-auth (AppRole, JWT, cert), caching and templates.
- Not verified: iron-proxy with OpenBao. The README never names OpenBao. Test first.
- SPIFFE: JWT auth with a SPIRE JWT-SVID is likely to work (a ControlPlane demo uses it). Cert auth with an X.509 SVID is blocked by [openbao issue #1687](https://github.com/openbao/openbao/issues/1687). This authenticates the proxy to OpenBao only. mTLS to agentgateway still needs a proxy that presents an SVID.
- Cost on one laptop: a server, an agent, a seal key and backups. The agent report recommends a pilot only for the `ttl` rotation or the SPIFFE auth.

## Open decisions (ask the owner)

1. **Secret source.** Keep `bws run` (works, the proxy reads the tokens once), or pilot OpenBao with `vault_kv`. The first test: a throwaway OpenBao and iron-proxy 0.56.0 `vault_kv`, one KV v2 read. Also open: a Bitwarden token in the keyring to remove the passphrase prompt, and an upstream request for a Bitwarden or command source.
2. **SPIFFE identity.** iron-proxy cannot present an SVID. Option 1: a host-side mTLS forwarder (Envoy or Caddy, with the SVID from the host SPIRE agent) for the gateway only. Option 2: a `grpc` transform that adds a JWT-SVID. Option 3: an upstream request.
3. **Container isolation.** The container shares the host kernel, and the agent runs as a subuid of the host user. Options: a separate Linux user for the sandbox, a seccomp profile, a read-only root file system, lower `pids` and memory limits. Anthropic's guide lists `--userns-remap` and a custom seccomp profile.
4. **GHCR token.** The sandbox still has the placeholder `GHCR_PUSH_TOKEN` (for `flux push artifact`). With CI builds the sandbox may not need it. Decide, then remove the rule and the variable.

## Next steps

Do them in this order.

1. **Finish `sandbox-plain`.**
   - Rewrite `.sandbox/README.md` for the plain container: architecture, network flow, secrets, prerequisites (no `crun`, no `libkrun`, `socat`, `systemd-run`, a `subuid` range), getting started, daily use, troubleshooting, limits. Take every fact from the files and from the evidence above.
   - The new diagrams are done: `.sandbox/docs/diagrams/architecture` and `network-flow` (drawio, svg and png), already on the branch. Link them from the README with the png files. Read each label against the files.
   - Lint the README with `ste-lint.py`. Push. Open the PR with the `pr` skill. Verify `git ls-remote` equals `git rev-parse`.
   - verify: `just sandbox selftest` passes, `just sandbox run claude --version` works, an attach takes under one second, a restart keeps the clone and the agent histories.
2. **Close #284 and #287** with a comment that links the new PR, after the owner agrees.
3. **N5 (the owner runs it).** `bws run` with the real tokens, one at a time. Claude API with a long SSE stream. GitHub with a Basic auth `git` clone and push. The Qwen endpoint.
   - verify: each call works, the audit log shows the swap, and no real token is in the sandbox (`just sandbox selftest` does not use real tokens).
4. **Tools through the proxy.** Test `git push`, Headroom, Qwen Code, `claude plugin install`, `curl`, `pip` and `npm`. A tool that ignores `HTTPS_PROXY` fails closed. Fix each one with its own setting.
5. **Secret source** (open decision 1).
6. **Isolation** (open decision 3). Add one control at a time and run the self-test after each.
7. **CODEOWNERS and a CI guard for `.sandbox/`.** The guard tests that the compose file has `network_mode: none`, no `privileged`, no host network, no socket except the proxy socket and no extra `devices`.
8. **CI builds.** Add a workflow that builds, scans and pushes the images. Then publish the sandbox as a signed OCI artifact by digest (cosign), and verify before `up`. See the first handoff, step 9.
9. **SPIFFE identity** (open decision 2).
10. **Switch.** Run next to `msb` for one week. Switch the daily command. Keep `.msb/` for two more weeks. Remove it after that.

## Lessons

- A proxy that sits in the VMM (msb, Docker Sandboxes) has one route by construction. With Podman and krun the proxy is a separate part, and the network wall becomes the complex part.
- `pkill -f <text>` kills the shell that runs it when the command line has the text. Use `pgrep` first, or a pid file.
- The auto-mode classifier denied a listener on `0.0.0.0` (reason: expose a local service). A listener on `127.0.0.1` passed. Use loopback for every test listener.
- `podman unshare` shows ids of the rootless namespace. A volume option and a `stat` in `unshare` use the same ids.
- A volume keeps its options and owner. After a change of the owner formula, remove the volumes that you made for tests.
- `podman-compose down` prints an error for a service that does not exist. It is harmless.
- `systemd-run --user --setenv=NAME` (no value) passes the variable from the caller. This keeps the token out of the arguments.
- A voice dictation made the names unclear ("open bar" was OpenBao, "orangic" was agentgateway). Ask for the name when a tool name is new.

## State of the host

These changes are outside the repo. They stay until someone removes them.

- Files in `~/.local/state/sandbox`: `ca.crt`, `ca.key`, `bin/iron-proxy-<digest>`. The folder `ssh/` is from #287 and is not used now. The old Podman secret `sandbox-ca-key` and the old image layers remain.
- User services `sandbox-proxy` and `sandbox-bridge` exist only while `just sandbox run` has started them. `just sandbox down` stops them. The socket is `$XDG_RUNTIME_DIR/sandbox/proxy.sock`.
- The test volumes of the krun sandbox were removed. The volumes of the new sandbox are made at the first `run` (names `sandbox-workspace`, `sandbox-claude-home`, `sandbox-qwen-home`, `sandbox-headroom-home`, `sandbox-herdr`, `sandbox-terraform-providers`).
- The image is `localhost/sandbox-dev:latest`. The proxy binary comes from the image pinned in the justfile.
- The items of the first handoff remain: Docker with gVisor runtimes in `/etc/docker/daemon.json`, an ACL on `/var/run/docker.sock`, root-owned leftovers and the spike images. See "State of the host" there.
- The scratch files of this session (test scripts, the stub `bws`, the throwaway CA of the swap spike) were in a temporary folder.
