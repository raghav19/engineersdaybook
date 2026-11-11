# Handoff: a build system for the agent sandbox

Written on 2026-11-11. The index of all handoff documents is `docs/handoff.md`. This document continues [podman-gvisor-sandbox.md](podman-gvisor-sandbox.md).

The owner wants the agent in the sandbox to build container images and push them to a registry. The agent sandbox must stay hardened and must not hold build capabilities. The first target is the owner laptop. The later target is a remote system at scale. No code for this is merged. One session ran spikes and compared designs. A fresh session continues with "Next steps".

## State of the repo

- PR #310 (README rewrite) is open. PR #311 (the cluster gateway) merged into the branch of #310, not into `main`. The gateway reaches `main` only when #310 merges. The document `docs/handoff/cluster-gateway.md` exists only on that branch until then.
- The worktree `sandbox-crane` (branch `sandbox-crane`, based on the branch of #310) holds edits that nobody committed. They add `crane = "0.22"` to `.sandbox/image/tools/infra.toml` and a README section on `crane`. The owner has not decided whether to keep them. See "Open decisions".
- The spikes left nothing on the host. The test containers, images and scratch folders are gone.
- Both this PR and #310 add an entry at the top of `docs/handoff.md`. The second PR to merge needs a trivial merge of that file.

## What the owner wants

- The agent never holds a build capability. Another component builds, on request.
- The build is ephemeral: a fresh container for each build, removed after the push.
- A simple local setup. The owner finds many systemd units and shell scripts too complex, and prefers declarative YAML.
- A queue that runs as a Podman container on the host, with a very small memory footprint.
- NATS is for later. It would load the laptop.
- The same contract later on a remote cluster. The local k3s counts as a remote cluster in a write-up. EKS is the scale target.
- The push goes through iron-proxy, with the same egress rules as the sandbox.

## What the spikes proved

The tests ran on 2026-11-11 on the owner host: Podman 6.1.4, `runsc` release 20261102.0, systemd 262. They used renamed test containers and the old local image `localhost/sandbox-dev:latest`, which has `podman`. They did not use the proxy.

| Fact | Result |
|---|---|
| `podman build --isolation=chroot --storage-driver=vfs` with a `RUN apk add` step in a `runsc` container | Passes. It needs a writable root. |
| Which capabilities it needs | `SETUID`, `SETGID` and `SYS_CHROOT`. The user can be `agent` (uid 1000). `no-new-privileges` must be off, because `newuidmap` is setuid. |
| The same build with `ReadOnly=true` | Fails: `error stat()ing intended root directory … no such file or directory`. |
| The cause of that failure | The helper in buildah does `pivot_root`, then `mount(".", ".", MS_SLAVE\|MS_REC)`. That call returns `EPERM` on the read-only gVisor root. The fallback `stat` then fails, because the old path is gone. The code is in `chroot/run_linux.go` and `run_common.go` in `containers/buildah`. A writable root passes. |
| Root with no added capabilities | Fails: `cannot write uid_map`. The multi-user mapping needs `SETUID` and `SETGID`. |
| `unshare -Ur` under the hardened flags (all capabilities dropped, `no-new-privileges` on) | Works. The user gets full capabilities inside the new namespace only. |
| A build with zero capabilities, a writable root and a single-user namespace | Passes `pivot_root`. Fails later: `error setting supplemental groups list: operation not permitted`. The file `/proc/self/setgroups` reads `deny`, and buildah should skip `setgroups` then. **The cause is not found.** |
| gVisor and added capabilities | A non-root user gets them as effective (`CapEff 0x400c0` for uid 1000). `os.setuid(0)` worked, so the user became root in the guest. |
| Guest-root and the managed settings | With a writable root, guest-root overwrote `/etc/claude-code/managed-settings.json`. With a read-only root the write failed. Plain uid 1000 with no capabilities and a writable root also failed. |
| The host in all these runs | Not touched. The gVisor documents say these capabilities exist only in the guest. |
| `podman kube play` with a `Job` manifest | Under `crun` it runs. The user, the three capabilities and the memory limit apply. Podman ignores `ttlSecondsAfterFinished`. Under `runsc` it fails: `joining UTS namespace … is not supported`. The man page has no annotation to avoid the shared pod namespaces. |
| `podman-compose` 1.6.0 with a service that has `runtime: runsc`, `user: "1000"`, `cap_drop: [ALL]`, three `cap_add` values and `network_mode: none` | Works. The output shows `Starting gVisor`. It also works with `--in-pod=false`. |
| Valkey 8 (`docker.io/valkey/valkey:8`) as the queue | See the next table. |
| Status of the tools on GitHub (API, 2026-11-11) | Google `kaniko` is archived (2025-06-03). The forks `chainguard-dev/kaniko` and `osscontainertools/kaniko` are active. `moby/buildkit`, `containers/buildah`, `kubernetes-sigs/kueue` and `kedacore/keda` are active. KEDA has the `ScaledJob` type and scalers for NATS JetStream, SQS, Kafka, Redis Streams, RabbitMQ and Prometheus. |
| TLQ and Apache Iggy | Read from their READMEs only. The classifier refused to run their images. I removed the pulled images. |

### The Valkey test

Server: rootless Podman, `--network none`, Unix socket only (`port 0`), `appendonly no`, `proto-max-bulk-len 64mb`, `maxmemory 256mb` with `noeviction`, and an ACL file. The client was a `runsc` container with no network and only the socket folder mounted.

| Check | Result |
|---|---|
| Idle memory | About 3.2 MB. About 11 MB while it held an 8 MB value. 6 processes. The image is 118 MB. |
| Context as a value | An 8 MB binary tar went in and came out with the same sha256. |
| Size limit | A 70 MB value is refused. The server closes the connection. |
| ACL for the user `agent` | Denied: `FLUSHALL`, `KEYS`, `CONFIG`, `ACL`, `DEL`, `BRPOP` and every key outside its patterns. A wrong password for `worker` fails. |
| A gap | With one pattern `~job:*`, the agent could overwrite `job:ID:status` and forge `done`. |
| The fix | Split the patterns: `%W~job:*:ctx` (write only), `%R~job:*:status`, `%R~job:*:log`, `%R~job:*:result` (read only) and `~build:queue`. The agent then cannot forge the status or the log. It cannot read a context back. |

### What the gVisor documents say

- `--cap-add` changes only what the guest sees. gVisor never gets host capabilities.
- The Docker-in-gVisor tutorials add `SYS_ADMIN` and `NET_ADMIN` (or `all`), and `docker build` with `RUN` steps works there. They use `--net-raw` and `--allow-packet-socket-write` for `dockerd`. A buildah build does not need these. They put `/var/lib/docker` on `tmpfs`.
- The rootless guide says a single-user mapping works with no setuid helper. Files owned by other users then need `ignore_chown_errors = "true"` in `storage.conf`. A multi-user mapping needs `newuidmap`.

## Designs the session compared

| Design | Verdict |
|---|---|
| The agent runs `buildah` in its own sandbox | Needs `SETUID` and a writable root, or the unsolved zero-capability path. Rejected for now. |
| `crane` only (add files to a base image) | Not a builder. It runs no `RUN` step. The owner rejected it as the only answer. |
| Spool folder that the agent writes, with a host watcher | The host reads files that the agent controls: symlinks, hard links, races. Replaced by a socket or a queue. |
| systemd units (socket intake, template unit, worker) | Works on paper. About five units and three scripts. The owner finds it too complex. |
| One foreground script (`socat` intake, loop, `systemd-run`) | The owner is not convinced by a script. |
| A `Build` custom resource and a Job on k3s | Declarative and the same on EKS. Needs gVisor in k3s (a root-level change) and a context delivery path. |
| `podman kube play` | Does not work under `runsc`. See the table above. |
| `podman compose` (the builder) with a Valkey queue | **The current lean for local use.** |
| EKS with SQS, KEDA `ScaledJob`, Kueue and Karpenter | The scale target. The isolation choice is open. |
| NATS JetStream | Postponed by the owner. |
| TLQ | In-memory, HTTP on TCP, no authentication, 64 KB messages. Cannot carry a context or a status. Does not fit. |
| Apache Iggy | A streaming log, not a work queue. Too much. Fits the distributed phase better. |

## The design to build next

The agent-facing contract is a small `Build` spec and a `sandbox-build` command in the image. The engine behind it differs by place.

```text
sandbox ── Unix socket (user "agent") ──► Valkey container (rootless, network none, socket only)
                                              ▲
host worker ── user "worker" (password on the host) ──┘
   │  takes an ID, checks it, pulls the context, lists the tar types, extracts into a private folder
   └─ podman compose run --rm builder      (runsc, three capabilities, no network, egress through iron-proxy)
        └─ build, then push with the path-scoped rule; the worker writes status, log and result back
```

### The agent side

1. Make a random ID. Write the tar with `SET job:ID:ctx`.
2. Enqueue with `LPUSH build:queue ID`.
3. Poll `GET job:ID:status` until `done` or `failed`. Read `job:ID:log` and `job:ID:result`.

### Sketch of the ACL (not tested as a whole)

```text
user default off
user agent on nopass %W~job:*:ctx %R~job:*:status %R~job:*:log %R~job:*:result ~build:queue -@all +lpush +set +get
user worker on >PASSWORD ~job:* ~build:queue -@all +brpop +get +set +del
```

### Sketch of the compose file (the `builder` service ran as shown)

```yaml
services:
  queue:
    image: docker.io/valkey/valkey:8
    network_mode: none
    restart: unless-stopped
    command: ["valkey-server", "/conf/valkey.conf"]
    volumes:
      - ./queue/valkey.conf:/conf/valkey.conf:ro
      - ./queue/users.acl:/conf/users.acl:ro
      - ${XDG_RUNTIME_DIR}/sandbox-queue:/run/valkey
  builder:
    profiles: [build]
    image: localhost/sandbox-dev:latest
    runtime: runsc
    user: "1000"
    network_mode: none
    cap_drop: [ALL]
    cap_add: [SETUID, SETGID, SYS_CHROOT]
    volumes:
      - ${JOB_DIR}/context:/ctx:ro
      - ${XDG_RUNTIME_DIR}/sandbox:/run/sandbox/proxy:ro
```

### Rules for the worker

- Accept an ID only if it matches a strict pattern. Derive every path from a fixed root plus the ID. Pass no agent text to a shell, a flag or a path.
- List the tar before you extract it. Allow only files and folders. Extract into a private folder with `--no-same-owner`. Mount the context read-only.
- Bring up the loopback of the builder from the host, as the `ExecStartPost` of `sandbox.container` does.
- Use a transient service or the compose service for the limits. `runsc` ignores Podman limits.
- Keep the real registry credential out of the builder. The proxy swaps the placeholder.

### Push through the proxy

The proxy rules take `host`, `methods` and `paths`. The tests on the k3s API showed that a path rule allows `GET /version` and refuses `GET /api`. The plan is to allow reads of the registry and to allow `POST`, `PATCH` and `PUT` only under the namespace of the build, for example `/v2/raghav19/sandbox-builds/**`. This also limits an account-wide token to one namespace. Nobody tested the full push sequence on `ghcr.io`.

### The remote design

- A `Build` custom resource (CRD with a structural schema and CEL rules) is the only object that the agent may create. The API drops unknown fields. A controller makes the `Job` from a fixed template. Candidates: KRO, Shipwright Build (needs Tekton) or a small operator.
- Pod Security Admission `baseline` on the namespace, RBAC that allows only `builds` and `pods/log`, and `subresources: {status: {}}` so only the controller writes the status.
- KEDA `ScaledJob` makes Jobs from queue depth. Kueue admits them by quota. Karpenter adds nodes. Use object-count quotas, API Priority and Fairness, and short TTLs against a flood of Jobs.
- On EKS, ECR with EKS Pod Identity replaces the proxy path rule. The IAM policy limits `ecr:PutImage` to a repository prefix.
- Isolation on EKS is open. EKS has no managed gVisor. There are three options. The first is `runsc` on your own node image. The second is Fargate microVMs, and nobody knows if they allow the capabilities that buildah needs. The third is Kata with Firecracker on nodes that support virtualization. AWS CodeBuild and AWS Batch are managed alternatives to compare first.

## Security notes

- With `SETUID` the agent becomes root in the guest. A read-only root then protects the managed settings. This is why the builder must be a separate, disposable container and not the agent sandbox.
- An escape from a `RUN` step reaches the gVisor sentry first. The sentry runs as the host user. A dedicated host user, or a separate machine, limits the damage of a second escape.
- `crun` shares the host kernel. It is acceptable only for trusted tenants on a dedicated builder host. For untrusted tenants use gVisor or a microVM.
- A queue that carries IDs only protects the control channel. The context and the `RUN` steps are untrusted code. The sandbox contains them.
- Treat a status or a log as data from the host. The agent has no write right on those keys.

## Open decisions (ask the owner)

1. **The worker.** A queue needs one process that takes jobs out. Accept one small script, or choose a ready-made consumer.
2. **The queue primitive.** Lists with `BRPOP` lose a job if the worker dies. Streams with a consumer group give acknowledge and redelivery. Recommendation: Streams.
3. **Where the image goes.** `ghcr.io`, a registry in the cluster, or an import into k3s from the host.
4. **A dedicated builder user now or later.** It needs root once for the user, the linger setting and the subuid range.
5. **The `crane` edits** in the worktree `sandbox-crane`. Keep `crane` as a registry tool, or discard the edits.
6. **gVisor in k3s.** A root-level change to the cluster. Ask before you touch the cluster.
7. **The controller** for the `Build` resource: KRO, a small operator or Shipwright.
8. **The EKS isolation choice.**

## Next steps

1. Spike Valkey Streams with the same ACL. Check `XADD`, `XREADGROUP`, `XACK` and `XAUTOCLAIM` from a `runsc` client.
   - check: kill the worker in the middle of a job. Another worker gets the job again.
2. Spike the worker and the compose `builder` end to end with a real `RUN` build and the tar checks.
   - check: the status, the log and the result reach the agent. The container is gone afterwards.
3. Spike the push through iron-proxy against a local `registry:2`, not `ghcr.io`.
   - check: a push to the allowed path passes. A push to another path gets `403`.
4. Add a Valkey client (`valkey-tools` or `redis-tools`) to the image. Write the `sandbox-build` client. Check that the package exists in the image base.
5. Optional: find why the zero-capability build fails at `setgroups`. A fix removes the need for `SETUID`.
6. Write the EKS design document. Start with the isolation spike.
7. Learn KEDA and Kueue on a throwaway `kind` cluster. Write a research note with the lab results.
   - check: does a KEDA `ScaledJob` create too many Jobs while Kueue holds them suspended?

## What was not tested

- Valkey Streams, durability and the full-memory behavior (`noeviction`).
- The worker, the tar checks and the compose `builder` in one flow.
- Any build through the proxy, and any push to a registry.
- The path rule with the full push sequence on `ghcr.io`.
- Resource limits and the timeout of a build.
- A dedicated builder user running `runsc` rootless.
- The `Build` resource, the controller, KEDA, Kueue, `kubectl-validate` and anything on EKS.
- The memory use of TLQ and Iggy. The classifier refused to run them.

## Lessons

- The failure of `ReadOnly=true` hides behind a misleading `stat()` message. Turn on `podman --log-level=debug` to see the real error.
- Added capabilities are effective for a non-root user in gVisor. Check what a capability gives to uid 1000 before you grant it.
- Valkey ACLs can split read and write key patterns (`%R~`, `%W~`). One shared pattern let the agent forge a status.
- A test with the real tools finds gaps that a design review misses. Run the test in a renamed copy, and remove it afterwards.
- The classifier can refuse to run a downloaded image. If it does, ask the owner to run the command or to add a permission rule. Do not work around it.
