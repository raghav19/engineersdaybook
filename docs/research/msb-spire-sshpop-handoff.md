# Handoff: SPIRE node attestation in the msb sandbox (join token now, sshpop next)

Question: How does the VM of the msb sandbox attest to the SPIRE server of the kind cluster, what is built, and what must the next session do?

Source: PR #171 (branch `msb-spire-node-attestation`, commit `a9de194`), the repo files, the tag `docker-sbx`, and the SPIRE 1.15.3 plugin pages for `sshpop`. Date: 2026-10-29.

Evidence tags: **[repo]** is a file or a PR in this repo. **[spire]** is a SPIRE 1.15.3 document that was fetched. **[inference]** is my own conclusion. **[untested]** means that nobody ran it. This VM has no `msb`, no `kind`, no `gh` and no kubectl context, so every host step is **[untested]**.

## Verdict

1. PR #171 gives the VM a node identity with a SPIRE **join token**. It passes `ruff`, `ty` and `bash -n`. Nobody ran it end to end. [repo] [untested]
2. The owner prefers **`sshpop`** for the next step. A join token works one time, so each new VM needs a new token and a `kubectl exec` on the host. [spire] [inference]
3. The owner does not want an agent on the host to read a private key. The design below keeps the node key in the VM and the CA key encrypted on the host. [inference]
4. Do not build `sshpop` before the host spike (section 5) passes.

## 1. State of PR #171 (join token)

| Piece | Where |
|---|---|
| `_spire_enroll` asks the VM if its agent is healthy. If not, it runs `token generate -ttl 600 -spiffeID spiffe://<domain>/microvm/<SANDBOX_GITHUB_ID>` and `bundle show -format spiffe` with `kubectl exec`. It sends both to `/run/spire` in the VM through `msb exec` stdin. | `.msb/msb.py` |
| `sandbox-boot` starts `spire-agent run -config /etc/spire/agent.conf -trustBundle … -joinTokenFile …`, waits 30 s for a healthy agent, then removes the token. | `.msb/dev-tools/sandbox-boot` |
| `kubectl` joins the `require` list. README and decision record 14 describe the flow. | `.msb/justfile`, `.msb/README.md` |

Known gaps of #171:

- After `msb stop` the agent is gone, so the next `run` mints a token that the agent ignores. [inference]
- `SANDBOX_GITHUB_ID` is not in the root `mise.toml` any more. `run` stops without it when the agent is not healthy. [repo]
- The PR was created with the GitHub MCP tool, because `gh` is not installed in the VM. [repo]

## 2. Why `sshpop`

| | `join_token` (#171) | `sshpop` |
|---|---|---|
| Token and `kubectl` at each new VM | yes | no |
| Agent ID after `rm` | new each time (alias workaround) | stable if `agent_path_template` uses a principal [spire] |
| Secret in the VM | none at rest | the node private key |
| Change on the server | already on | add the `sshpop` attestor and the CA public key |

The plugin name is `sshpop` (not `ssh_pop`). The server checks that the certificate chains to a trusted CA and sends a challenge that the node key signs. [spire]

## 3. Design for `sshpop`

Two key pairs. The CA key pair signs. The node key pair proves the VM.

```text
host   ~/.config/msb/spire-ca/   mode 700, never mounted
         ca        CA private key, passphrase, ssh-keygen -a 100
         ca.pub    CA public key → cert_authorities on the SPIRE server
host   ~/.config/msb/spire/      mounted read-only at /run/sandbox/spire
         node_key.pub        copied from the VM
         node_key-cert.pub   written by ssh-keygen -s
VM     /etc/spire/node_key   made by sandbox-boot, root only, the agent runs as root or a spire user
```

Flow:

```text
once      host: ssh-keygen -t ed25519 -a 100 -f ~/.config/msb/spire-ca/ca
          server: NodeAttestor "sshpop" { cert_authorities = "<ca.pub line>" }, restart the server
per VM    VM: sandbox-boot makes /etc/spire/node_key if it is missing
          host: msb exec sandbox-dev -- cat /etc/spire/node_key.pub > ~/.config/msb/spire/node_key.pub
          host: ssh-keygen -s ~/.config/msb/spire-ca/ca -h -I msb-sandbox -n msb -V +7d ~/.config/msb/spire/node_key.pub
attest    agent reads host_key_path and host_cert_path, sends the certificate to host.microsandbox.internal:18081
          server checks the CA signature, sends a challenge, checks the signature of the node key, issues the agent SVID
```

Agent config in the VM:

```hcl
NodeAttestor "sshpop" { plugin_data {
  host_key_path  = "/etc/spire/node_key"
  host_cert_path = "/run/sandbox/spire/node_key-cert.pub"
} }
```

Rules to keep:

- Mount only `~/.config/msb/spire/`. The CA key must never be in a mounted folder.
- The first boot has two passes: the VM makes its key, the owner signs it, the next `run` starts the agent. A `just msb spire-sign` recipe should do the signing in the terminal of the owner, not in an agent session.
- The certificate is public data. Only the node private key is secret.

## 4. Concepts the owner asked about

| Question | Answer |
|---|---|
| Which certificate does the agent show? | An OpenSSH certificate (`ssh-keygen -L -f node_key-cert.pub` prints it). It holds the node public key, key ID, principals, validity and the CA signature. It is not the X.509 SVID. [spire] |
| How does the server verify the challenge without the node public key? | The key is inside the certificate. The CA signature makes the server trust it. No key needs registration. [spire] |
| Is the certificate sent through `agent.sock`? | No. The agent sends it over the network connection to the server (Node API, port 18081). `agent.sock` is the Workload API for processes such as Envoy. [spire] |
| Is workload attestation mixed in? | No. `NodeAttestor "sshpop"` proves the machine. `WorkloadAttestor "unix"` (already in `spire-agent.conf`) identifies a process by its Unix user. The registration entry joins them: its parent is the agent ID. [spire] |
| What protects the CA key? | The passphrase (same limit as decision 4 of `.msb/README.md`), or a hardware `ed25519-sk` key that needs a touch. An agent with the uid of the owner can read the file but cannot type the passphrase. [inference] |

## 5. Host spike (do this before any code)

Run on the host, in order. Stop at the first failure.

1. `host.microsandbox.internal:18081` reaches the host `127.0.0.1:18081`: `msb exec sandbox-dev -- bash -c '</dev/tcp/host.microsandbox.internal/18081'`. [untested]
2. The TLS interception of msb does not break the gRPC TLS to port 18081. Read `~/.spire/agent.log` in the VM. [untested]
3. The chart `spire` 0.30.3 can enable `sshpop` on the server, or the server accepts an extra plugin block. `platform/addons/spire/spire.yaml` only sets `nodeAttestor.joinToken.enabled`. [untested]
4. The exact format of `cert_authorities` (the `ca.pub` line should work). [untested]
5. Sign one certificate by hand and run `spire-agent` in the VM. Check `spire-server agent list`. [untested]
6. Test an expired certificate and a re-attestation after `msb stop`. The `sshpop` page does not describe either. [untested]
7. The Claude agent in the VM has no `sudo`, so it cannot read `/etc/spire/node_key`. [untested]

## 6. Next steps

1. Run the spike (section 5).
2. If it passes: replace the join-token code of #171 with the flow in section 3. Add the `spire-sign` recipe, the mount in `sandbox.yaml` (`${MSB_SPIRE_DIR}:/run/sandbox/spire:ro`) and the server change in the kind stack. Then `just msb build`, commit the new digest, and `just msb rm && just msb run`.
3. If it fails at step 1 or 2: keep the join token and fix #171 (gate on a valid SVID on disk, not on the agent process).
4. Later: the Envoy workload entry (`unix:user:envoy`). It is not part of this work.

## Gaps

- No host command ran. Every claim about `msb` behavior (stdin of `msb exec`, mounts, host ports) is **[untested]**.
- I did not check what the server stores about a node after attestation.
- `docs/research/spire-node-attestation.md` still describes the sbx flow. It does not describe #171 or `sshpop`.
