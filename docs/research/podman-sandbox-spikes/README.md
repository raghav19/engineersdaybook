# Configs and scripts of the sandbox spikes

These files came from the spikes of 2026-11-08. The research note is `docs/research/podman-sandbox-runtimes.md`. The handoff is `docs/handoff/podman-krun-sandbox.md`.

They are working examples, not a finished bundle. Each file ran in a spike with fake secrets. Read the section of its spike in the research note before you use it.

The files contain the marker `<SPIKES>`. It stands for the temporary folder of the spikes. Replace it with your own folder.

## Files

| Folder | File | Use |
|---|---|---|
| `A` | `containers.conf` | A private Podman config with the `krun` runtime. `krun` is a symlink to `/usr/bin/crun`. Set it with `CONTAINERS_CONF`. |
| `B` | `compose.yaml`, `proxy.yaml` | The iron-proxy layout with Podman: an internal network, the proxy on two networks and the secret swaps. |
| `C` | `compose.yaml`, `entry.sh` | The hardened sandbox: root entry, `chown`, then `setpriv` to `agent`. |
| `C` | `egress-selftest.sh` | The egress self-test. Run it inside the sandbox. Read its header first. |
| `D2` | `compose.yaml`, `resolv.conf` | The layout for Docker with gVisor, with the DNS fix. |
| `E` | `flow.sh`, `verify-pinned.sh` | Publish, sign and verify an artifact. The host test of the digest pin. |
| `F1` | `compose.yaml`, `entry.sh`, `identity-supervisor.sh`, `identity-relay.pl` | The sandbox container gets its SVID at start. A root supervisor renews it. A relay uses it. |
| `N2` | `compose-static.yaml` | Static uid maps for the sandbox and the proxy under `krun`. |
| `setup` | `install-runsc.sh` | Installs gVisor `runsc` into a private folder with a SHA-512 test. |
| `setup` | `docker-gvisor-setup.sh` | Root setup for Docker with gVisor: runtimes, daemon start and a socket ACL. Read it before you run it. |

## Not here

- Certificates, keys and the fake secret files. Make them again.
- The binaries of SPIRE, iron-proxy and gVisor. Download them from their releases and compare the checksums.
- The raw result files. The research note has the tables.
