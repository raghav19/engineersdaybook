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
| `.sandbox/runsc.conf` | New. The gVisor flags for Podman, with a comment for each flag. It has no host path, so `setup` links it. |
| `.sandbox/proxy/sandbox-guard.nft` and `sandbox-guard.service` | New. The firewall rule and its system unit. Only the owner may connect to the proxy TCP ports 18080 to 18083 and the UDP port 18084 on `127.0.0.1`. |
| `.sandbox/justfile` | `setup` links the unit, `runsc.conf` and `~/.config/sandbox/repo.git` (the `.git` folder of the repo). It installs the firewall rule with `sudo`. `run` restarts `sandbox.service`, which replaces the old container. `rm` stops it. The recipe `_check` is gone. `podman-compose` is no longer a requirement. `runsc`, `nft` and `sudo` are. |
| `.sandbox/README.md`, `.sandbox/proxy/README.md`, `.sandbox/docs/diagrams/` | The new runtime, the network diagram (with a carrier label on each line and the firewall rule), the glossary and the trade-offs. |
| `.sandbox/image/` | Comments only. They named `compose.yaml`. |

The image, `sandbox-entry`, `sandbox-start` and the proxy units do not change.

## The firewall rule

A TCP or UDP port on `127.0.0.1` has no check of the user. Any local user could connect to iron-proxy and use the real tokens through the placeholders. `sandbox-guard.nft` rejects connections to TCP 18080-18083 and UDP 18084 (the real listeners of `iron-proxy.yaml`) from every uid except the owner. The bridge runs as the owner, so it still connects.

- It needs root. `just sandbox setup` copies the rule and the unit to `/etc` with `sudo`. A link to a file in the repo would let the user change what root runs.
- It is its own table, `inet sandbox_guard`. `ufw` is active on the host of the owner and stays as it is. The `nftables` service is off and stays off.
- `setup` stops if a `sudo` step fails. The proxy does not start without the rule.
- It separates users. A rootless container of the same user with `pasta` networking can reach the host loopback as that user. The sandbox has `Network=none`, so it cannot. Not tested.

## The three runtime flags

They are in `.sandbox/runsc.conf`.

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
| `runsc.conf` as a link in `containers.conf.d/`, without a `[engine.runtimes]` entry | Podman found `runsc` in `/usr/local/bin` by its default folders. The flags took effect: `lo` was in the guest, and the guest connected to a mounted host socket. |
| `~/.config/sandbox/repo.git` as a link to the `.git` folder, mounted by the unit | The container started healthy and cloned the repo. With no `SANDBOX_BRANCH`, the clone got the branch of the main checkout (`main`). |
| The firewall rule in a temporary network namespace (`podman unshare unshare -n`, uid 0 as the owner, uid 1 as another user) | `nft -c` accepted the file. Loading it twice left two rules, one for each protocol. TCP 18080 and 18083: the owner got a reply, the other user got `Connection refused`. UDP 18084: the owner got a reply, the other user got `Operation not permitted`. TCP 18085 (spare port) and UDP 18081 (no listener in the rule): the other user got a reply. The host firewall was not touched. |
| `sudo` on the host | It needs a password, so the real install of the rule was not run. `ufw` is active. `nftables.service` is inactive and disabled. |

## What was not tested

- `just sandbox setup` and `just sandbox run` as real commands. Both touch the live proxy or the live container name. The tests used a renamed copy of the unit (`sandbox-gvt`) and a dry run of `run`.
- The install of the firewall rule on the host: the `sudo` steps, `sandbox-guard.service` and a reboot. The rule text was tested in a temporary network namespace only.
- A connection to the proxy ports from a second user on the real host. The host has one user.
- A container of the same user with `pasta` networking, as a way to reach the proxy ports.
- An interactive Herdr or TTT session. The test harness had no terminal.
- A heavy job under `TasksMax=2048` and `MemoryMax=3G`.
- `Restart=` for a killed sandbox.
- Whether `runsc` uses the default seccomp profile of Podman.
- The speed of TLS handshakes. An earlier spike (G1) measured 1587 ms for 20 new connections against 730 ms with `crun`.

## Decisions of the owner

- Accept that a limit kills the whole sandbox, not one process.
- Keep `socat`, `proxy.sock` and `sandbox-bridge` as they are. Do not add a network part.
- Use a Quadlet unit, so that the service cgroup holds the limits.
- Put the firewall rule in `just sandbox setup`, for the owner user. Use a rule file and a unit file in the repo, not code in the recipe.
- `run` restarts the unit. Each run makes a new container. The unit runs `podman run --replace`, so it also replaces the compose container. The state lives in the volume. A process in the old container stops, and each run takes about 17 s.
- Put the gVisor flags in a file (`runsc.conf`) and link it, as for the proxy units. Link `repo.git` in the same way. This removed a generated drop-in file and the `_checkout` recipe. The cost: no `SANDBOX_BRANCH`, so the clone gets the branch of the main checkout. For a template that restores the branch, write a drop-in with a placeholder, and fill it in `setup` or `run`.

## Open decisions (ask the owner)

1. **A separate host user for the sandbox.** Today the sentry runs as the owner. A bug in the sentry gives an attacker the owner user. With `crun`, the agent is a subuid. A separate host user closes this gap. It needs its own rootless Podman and access to the proxy socket. Not tested.
2. **`Restart=on-failure`** for a sandbox that a limit killed. Not tested.
3. **The value of `TasksMax`.** 2048 is a guess with a margin. Raise it if a job hits it.
4. **The custom seccomp profile** and the egress self-test. They stay parked.

## Next steps

1. **The PR.** Read `docs/agents/pull-requests.md`. The branch is `sandbox-gvisor`. The owner merges.
2. **The host bring-up (the owner runs it).** The main checkout has uncommitted files. Use a clean checkout or a worktree of the branch.
   1. Close the Herdr sessions in the sandbox. `just sandbox run` replaces the old `sandbox` container, and the volumes stay.
   2. Run `just sandbox setup` from the branch. It asks for your `sudo` password and the Bitwarden token. It installs the firewall rule, links `runsc.conf`, the unit and `repo.git`, and restarts the proxy.
   3. Run `just sandbox run`.
   - check: `systemctl --user is-active sandbox` prints `active`. `podman inspect sandbox --format '{{.OCIRuntime}}'` prints `runsc`. `just sandbox run claude --version` works. `podman exec sandbox curl --noproxy '*' -m 4 https://1.1.1.1` fails.
   - check the firewall: `systemctl is-active sandbox-guard` prints `active`. `sudo nft list table inet sandbox_guard` shows one rule with your uid. The proxy still works from the sandbox. `sudo -u nobody curl -m 3 -x http://127.0.0.1:18080 https://example.com` fails (another user).
   - after a reboot: `systemctl is-active sandbox-guard` prints `active` before you start the proxy.
3. **Real traffic.** Test the Claude API with a long stream, a GitHub push, and a heavy job. Watch `systemctl --user status sandbox` for `failed`.
4. **Close the older work.** The new design supersedes the branch `sandbox-plain` and the PRs #284 and #287. Close them only after the owner agrees.

## Lessons

- The image `ENTRYPOINT` already starts the relay on port 3128. A test script that starts another `socat` on that port fails with `Address already in use`.
- `pkill -f` with a pattern that is also in your own command line kills your shell. Use a pid.
- A test without a terminal hides a stuck process. `timeout` runs its command in a background process group. In a terminal, a `podman` that touches the terminal there gets stopped by the kernel. The stopped `podman` holds the lock of the container, so every podman command hangs, even `podman ps -a`. `just sandbox run` hung at the wait for the health check. Use `timeout --foreground` and `</dev/null`. Test such a loop in a pseudo-terminal: `script -qfec "<command>" /dev/null`.
- To free a hung podman, find the stopped process (`ps -eo pid,stat,comm` shows state `T`) and kill it with `kill -KILL <pid>`. A stopped process ignores a normal `kill`.
- Quadlet does not expand shell variables. Use `%h` and `%t`, and links to fixed paths (`~/.config/sandbox/repo.git`). A generated drop-in file was harder to read.
- A user unit cannot enforce `IPAddressDeny=`, and a TCP port on loopback has no user check. A firewall rule with `meta skuid` is the way. A throwaway network namespace (`podman unshare unshare -n`) tests such a rule without root and without the host firewall.
- Do not link a file from your repo into `/etc/systemd/system/` for a root service. Copy it. Root would run a file that the user can change.
- `Notify=healthy` cannot work with the `ExecStartPost` line that brings up `lo`, because the health check needs that line first.
- A Unix socket path has a limit of 108 characters. A long scratchpad path hides this problem behind a "No such file" error.
- Test only in a renamed copy. Never touch the live `sandbox` container, the `sandbox-*` volumes or the `sandbox-proxy` and `sandbox-bridge` units.

## State of the host

- The live `sandbox` container runs from `podman-compose` with `crun`. It still works.
- `runsc` is in `/usr/local/bin`. I removed the spike files: the test unit, `runsc.conf`, the test volume and the stub socket. A copy of the spike files is in the scratchpad of the session, and it may be gone.
- The main checkout has uncommitted changes that this work did not make: `docs/handoff.md` and untracked files under `docs/handoff/` and `docs/research/`.
