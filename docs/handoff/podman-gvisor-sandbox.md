# Handoff: the Podman sandbox runs in gVisor

Written on 2026-11-11. The index of all handoff documents is `docs/handoff.md`. This document continues [podman-sandbox-merged.md](podman-sandbox-merged.md). That document parked gVisor. This one unparks it.

The change is on the branch `sandbox-gvisor`. The host of the owner still runs the crun container from `podman-compose`. A fresh session continues with "Next steps".

## Goal

The owner wants the agent sandbox to run in gVisor (`runsc`) in place of `crun`, with these conditions:

1. The path out stays the same: `socat` in the container, `proxy.sock`, `sandbox-bridge` and iron-proxy. No new part on the network path.
2. The container keeps `--network=none`.
3. The limits (processes, memory, CPU) work. The owner chose a Quadlet unit for this.

## What changed

| File | Change |
|---|---|
| `.sandbox/sandbox.container` | New. The Quadlet unit. It replaces `compose.yaml`. It has the limits and the `ExecStartPost` line that brings up `lo`. |
| `.sandbox/compose.yaml` | Removed. |
| `.sandbox/justfile` | `setup` links the unit and writes `~/.config/containers/containers.conf.d/runsc.conf`. `run` starts `sandbox.service`. `rm` stops it. A new private recipe, `_checkout`, writes the drop-in file for the `.git` mount and the branch. `podman-compose` is no longer a requirement. `runsc` is. |
| `.sandbox/README.md`, `.sandbox/proxy/README.md`, `.sandbox/docs/diagrams/` | The new runtime, the network diagram, the glossary and the trade-offs. |
| `.sandbox/image/` | Comments only. They named `compose.yaml`. |

The image, `sandbox-entry`, `sandbox-start` and the proxy units do not change.

## The three runtime flags

| Flag | Reason |
|---|---|
| `ignore-cgroups` | Rootless `runsc` cannot make a systemd scope. |
| `network=host` | gVisor then uses the empty network namespace of the container. This is a runsc flag. It is not `podman --network=host`. With the default `network=sandbox`, the guest has no `lo`, so `socat` cannot bind `127.0.0.1`. |
| `host-uds=open` | The guest may connect to the mounted `proxy.sock`. gVisor blocks this by default. |

## Evidence

All tests ran on the host of the owner on 2026-11-11 with `runsc` release-20261102.0, Podman 6.1.4 and the real image `localhost/sandbox-dev:latest`. The last four rows used the real iron-proxy as a client only. The live units were not touched.

| Fact | Result |
|---|---|
| `network=sandbox` with `--network=none` | The guest has no `lo`. `socat` fails with `Cannot assign requested address`. |
| `network=host` with `--network=none` | `lo` is in the guest and it is down. `SIOCSIFFLAGS` in the guest fails with `ENOTTY`, so the guest cannot bring it up. |
| `socat` binds `127.0.0.1` while `lo` is down | It works. The connect fails until `lo` is up. |
| `podman unshare nsenter --net=/proc/<pid>/ns/net ip link set lo up` on the host | It brings `lo` up. The relay then works. |
| The wall | `/proc/net/dev` in the guest lists `lo` only. `curl --noproxy '*' https://1.1.1.1` fails. |
| Quadlet unit with `runsc` | It works. Quadlet adds `--cgroups=split` and `Delegate=yes`. The sentry, the gofer and conmon are in the cgroup of the service. A symlink to the unit file works. A drop-in file works. `DefaultDependencies=false` in `[Quadlet]` drops the wait for network-online. |
| Start time | 0.4 s for `systemctl start`. 16.7 s until healthy (the clone and Headroom). |
| `MemoryMax=256M` with a 400 MB allocation | The allocation passed. Swap hid the limit. With `MemorySwapMax=0`, the kernel killed the sandbox (`oom_kill 1`). |
| `TasksMax=120` with 200 new processes | The limit held at host level (`pids.events max`). The sandbox died. |
| `CPUQuota=100%` with 4 busy loops | The loops used 84% of one CPU. The cgroup throttled them. |
| An idle sandbox | 46 to 54 host tasks. A running sandbox with `claude` and Headroom: 149 tasks and 799 MiB. |
| A sandbox that hit a limit | The service shows `failed`. `systemctl start` starts it again. |
| Tools in the guest | `claude` 2.1.322, `git`, `mise`, `herdr` 0.9.5, `node`, `just` and `ttt` 1.10.0 run. `terraform` prints the same message as under `crun`: the test container had no cache folder. |
| The real chain | A clone of the repo from the `.git` mount worked on the branch `sandbox-gvisor`. `curl https://api.github.com/zen` returned 200. `curl https://example.com` failed with `CONNECT tunnel failed, response 403`. |
| Sockets in the guest | A manual `podman run -d` showed `/run/notify/notify.sock`. The Quadlet unit did not. The proxy folder has the mode 0711, so the guest cannot list it. |
| Who owns the processes on the host | `crun`: the agent runs as host uid 100999 (a subuid). gVisor: the sentry and the gofer run as the owner. |

## What was not tested

- `just sandbox setup` and `just sandbox run` as real commands. Both touch the live proxy or the live container name. The tests used a renamed copy of the unit (`sandbox-gvt`) and a dry run of `run`.
- An interactive Herdr or TTT session. The test harness had no terminal.
- A heavy job under `TasksMax=2048` and `MemoryMax=3G`.
- `Restart=` for a killed sandbox.
- Whether `runsc` uses the default seccomp profile of Podman.
- The speed of TLS handshakes. An earlier spike (G1) measured 1587 ms for 20 new connections against 730 ms with `crun`.

## Decisions of the owner

- Accept that a limit kills the whole sandbox, not one process.
- Keep `socat`, `proxy.sock` and `sandbox-bridge` as they are. Do not add a network part.
- Use a Quadlet unit, so that the service cgroup holds the limits.

## Open decisions (ask the owner)

1. **A separate host user for the sandbox.** Today the sentry runs as the owner. A bug in the sentry gives an attacker the owner user. With `crun`, the agent is a subuid. A separate host user closes this gap. It needs its own rootless Podman and access to the proxy socket. Not tested.
2. **`Restart=on-failure`** for a sandbox that a limit killed. Not tested.
3. **The value of `TasksMax`.** 2048 is a guess with a margin. Raise it if a job hits it.
4. **The custom seccomp profile** and the egress self-test. They stay parked.

## Next steps

1. **The PR.** Read `docs/agents/pull-requests.md`. The branch is `sandbox-gvisor`. The owner merges.
2. **The host bring-up (the owner runs it).** The main checkout has uncommitted files. Use a clean checkout or a worktree of the branch.
   1. Close the Herdr sessions in the sandbox. Run `podman rm -f sandbox`. The volumes stay.
   2. Run `just sandbox setup` from the branch. It writes `runsc.conf`, links the unit and restarts the proxy.
   3. Run `just sandbox run`.
   - check: `systemctl --user is-active sandbox` prints `active`. `podman inspect sandbox --format '{{.OCIRuntime}}'` prints `runsc`. `just sandbox run claude --version` works. `podman exec sandbox curl --noproxy '*' -m 4 https://1.1.1.1` fails.
3. **Real traffic.** Test the Claude API with a long stream, a GitHub push, and a heavy job. Watch `systemctl --user status sandbox` for `failed`.
4. **Close the older work.** The new design supersedes the branch `sandbox-plain` and the PRs #284 and #287. Close them only after the owner agrees.

## Lessons

- The image `ENTRYPOINT` already starts the relay on port 3128. A test script that starts another `socat` on that port fails with `Address already in use`.
- `pkill -f` with a pattern that is also in your own command line kills your shell. Use a pid.
- Quadlet does not expand shell variables. Values that depend on the checkout go in a drop-in file that `just` writes.
- `Notify=healthy` cannot work with the `ExecStartPost` line that brings up `lo`, because the health check needs that line first.
- A Unix socket path has a limit of 108 characters. A long scratchpad path hides this problem behind a "No such file" error.
- Test only in a renamed copy. Never touch the live `sandbox` container, the `sandbox-*` volumes or the `sandbox-proxy` and `sandbox-bridge` units.

## State of the host

- The live `sandbox` container runs from `podman-compose` with `crun`. It still works.
- `runsc` is in `/usr/local/bin`. I removed the spike files: the test unit, `runsc.conf`, the test volume and the stub socket. A copy of the spike files is in the scratchpad of the session, and it may be gone.
- The main checkout has uncommitted changes that this work did not make: `docs/handoff.md` and untracked files under `docs/handoff/` and `docs/research/`.
