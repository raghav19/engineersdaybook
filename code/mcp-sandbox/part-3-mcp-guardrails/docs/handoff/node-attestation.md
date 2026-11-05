# Handoff: node attestation of the msb sandbox microVM

Written on 2026-11-05 at about 20:05 UTC. The index of all handoff documents is `docs/handoff.md` at the root of the repo.

The node attestation works and its docs are on `main` (commit `0126bcc`). This handoff lets a fresh session continue without the long history. Read it, then read "Next steps".

**Where this document and an older record disagree, this document wins.** The older record `docs/research/msb-spire-sshpop-handoff.md` (branch `msb-spire-sshpop-handoff`) describes `sshpop` and a join token. Both are gone.

## Goal

The sandbox microVM (msb) proves to a SPIRE server that it is an approved node. The server runs on the user's k3s cluster. The user wants zero trust, Gateway API only, and a flow that starts nothing by hand.

The end state is a chain of four links. Link 1 is the node attestation. Link 2 is a workload entry for a process in the VM (Envoy). Link 3 is an SVID on the client hop. Link 4 is a gateway rule on the SPIFFE ID. Only link 1 exists.

## Read these first (do not copy them here)

- The guide of the model: `code/mcp-sandbox/part-3-mcp-guardrails/docs/node-attestation.md`. It has the idea, the parts, 3 mermaid flows and the names.
- The diagram: `docs/diagrams/node-attestation.{drawio,svg,png}` in the same project.
- The detailed guide: `docs/zero-trust-node-attestation.md`. The workload step: `docs/zero-trust-workload-attestation.md`.
- Rules of the repo: `AGENTS.md`. The rule for docs: `docs/agents/project-docs.md`.
- The full transcript of this session: `/home/agent/.claude/projects/-home-agent-engineersdaybook/b863ef56-5af8-494c-bb8f-ad8dca6b85a6.jsonl`. It also has the code of the diagram generator (see "Tools").

## What `main` has

- #239: k3s replaces kind in part 3 (`clusters/k3s/`).
- #240: the SPIRE server is reachable through the Istio ingress gateway (Gateway, TLSRoute passthrough, ReferenceGrant).
- #231 then #243: the VM attests with `x509pop`. cert-manager makes the key pair and the 90-day certificate (`Certificate sandbox-node`). `just msb node-cert` copies the files to the host.
- #246: the agent reaches the server through the gateway on port 443.
- #244: the VM no longer holds the admin kubeconfig. It has a read-only token of the ServiceAccount `sandbox-agent`, and the host swaps it in. I read the files and did not run it.
- #247: the guide, the redrawn diagram and the correction of the SVID life.
- #251 and #252: the rule for docs. A topic doc in `docs/` explains the model. A main README keeps its own shape.

## Decisions of the user (do not reopen without a reason)

- k3s only. Kind is gone. Each project has its own disposable cluster and its own Flux.
- Gateway API only, for example TLSRoute. No Istio VirtualService. Istio ingress and agentgateway replace Traefik.
- The node certificate comes from outside the VM and exists before the VM starts.
- cert-manager makes both the key pair and the certificate (90 days, signed by the node CA). The flow is a short shell recipe in the justfile. No OpenSSL or Python helper and no test file.
- The check runs at each start of the VM. The check does not touch a running agent. The agent re-attests by itself.
- A leaked key is a forced rotation. It is a separate step.
- The port stays 443. The name is `spire.localhost`.
- Docs: the heading names the subject (no word "primer"). Each doc follows `docs/agents/project-docs.md`.
- The user reads on a phone. Use short lists and narrow diagrams.

## Facts checked on 2026-11-05 (live)

- The SPIRE agent in the VM attested at 19:16:41 UTC. Its ID is `spiffe://mcp.local/spire/agent/x509pop/eac2a996…`.
- The server sets `default_x509_svid_ttl` to `4h` and the trust domain to `mcp.local`. So the agent SVID ends at 23:16:41 UTC.
- The node entry `spiffe://mcp.local/node/sandbox-dev` exists. Its selectors are the CN `sandbox-dev` and `github-id:raghav19`.
- No workload entry exists for a process in the VM.
- The gateway `spire` shows `Programmed=True`. From the VM, port 443 shows a certificate that SPIRE issued.
- `Certificate sandbox-node` is Ready.

## Corrections of earlier claims (do not repeat the old claims)

- The agent SVID lives 4 hours, not 1 hour. Re-attestation is about every 2 hours, not every 30 minutes.
- Port 443 works from the new VM. An earlier probe came from the old VM and showed the msb proxy. Drop the port 9443 idea.
- #244 fixed the admin kubeconfig problem.

## Open problem: the ExternalSecret `github-upstream` fails

At 20:01 UTC, the `ExternalSecret` `github-upstream` (namespace `agentgateway-system`) is `SecretSyncedError: could not get secret data from provider`. It reads the key `GITHUB_APP_CLIENT_SECRET` from the `ClusterSecretStore` `bitwarden`. The store itself is `Valid`.

Effect: the Kustomization `mcp-servers` fails its health check. `routes`, `authn-jwt`, `rate-limit` and `tool-rbac` wait for it. The node attestation does not depend on them.

I did not find the cause. Check first: does the key exist in the Bitwarden project, and does the access token reach it? Then read the logs of `deploy/external-secrets` in the namespace `external-secrets`.

## Next steps

1. **Re-attestation.** After 21:16 UTC, run `spire-server agent list` on `spire-server-0`. The expiry of the `x509pop` agent must move to a later time. If it does not, read the agent log as root on the host. The log is `/var/log/spire-agent.log` in the VM.
2. **Fix `github-upstream`** (see above). Then check that the Kustomizations `mcp-servers`, `routes`, `authn-jwt`, `rate-limit` and `tool-rbac` turn Ready.
3. **Workload entry.** Add an entry for a process in the VM. Parent: the node ID. Selector: `unix:user:envoy`. See `docs/zero-trust-workload-attestation.md`. Read `docs/agents/kubernetes.md` and use the flux-schema-catalog before you write the manifest.
4. **Stale diagrams.** `spire-setup`, `architecture`, `orchestration` and `workload-attestation` in `docs/diagrams/` show the old model.
5. **Worked example.** Link `docs/node-attestation.md` from `docs/agents/project-docs.md`.
6. **Optional.** Raise `--concurrent` of kustomize-controller in `clusters/k3s/flux-instance.yaml`. The 3 group Kustomizations (`gateway`, `mesh`, `secrets`) hold 3 of the 4 default workers, so the first start is slow.
7. **Tidy up, only after the user agrees.** Stale remote branches: `agents/explain-the-model-in-readmes`, `agents/guides-on-one-part`, `docs/research-node-attestation-x509pop`. Old worktrees: run `herdr worktree list`. PR #241 (branch `msb-attest`) should be closed. I did not check its state.

## Not checked

- A second attestation of the agent.
- An expired node certificate, and what the server does with the old certificate after a forced rotation.
- The `.drawio` in draw.io. The SVG and PNG come from a script with the same coordinates.
- The rendering of the mermaid flows in the GitHub mobile app. A parser accepts them.
- Whether an agent follows the pointer in `AGENTS.md` section 14.

## How to work in this repo

- Work in a Herdr worktree: `herdr worktree create --branch <branch> --label <slug>`. Never push to `main`.
- `gh` is not installed in the VM. Use the GitHub MCP tools. The steps are in `docs/agents/pull-requests.md`: identity, branch, push, compare `git ls-remote` with `git rev-parse <branch>`, duplicate check, create. Link an image in a PR body only as an SVG at the commit hash.
- Write all text in Simplified Technical English. Run `python3 .claude/skills/asd-ste100/scripts/ste-lint.py <file>`.
- `just` cannot parse the justfile of `.msb` inside the VM (`require("age")`). Run `just msb ...` on the host. Before you ask the user to run a command, read `docs/agents/host-handoff.md`.
- Never print a secret. The Bitwarden project ID and tokens stay out of docs and chat.
- The user likes an explanation before a change, and a short answer that ends with what you skipped.

## Tools in this VM

- There is no browser and no image tool. For a PNG: `uv pip install --target <dir> resvg-py pillow matplotlib`, then render the SVG with `resvg_py.svg_to_bytes` and the DejaVu fonts of matplotlib.
- Mermaid check: `npm install mermaid jsdom` in a scratch folder, then call `mermaid.parse` on each block under jsdom.
- The diagram generator (`make_node_diagram.py`) lived in the scratchpad of the session. It makes the `.drawio`, the `.svg` and the `.png` from one model. Its source is in the transcript. The scratchpad can vanish, so write it again from the transcript if you need to redraw.

## Suggested skills

- `asd-ste100` before you finish any change.
- `pr` for the body of a PR.
- `gitops-cluster-debug` for the failing Kustomizations and the ExternalSecret.
- `gitops-knowledge` and the flux-schema-catalog for any Flux or Kubernetes manifest.
- `writing-for-agents` if you edit `AGENTS.md` or a doc in `docs/agents/`.
