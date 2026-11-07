# Handoff: agent workload identity of the msb microVM

Written on 2026-11-07. The repo is `raghav19/engineersdaybook`. The project is `code/agent-workload-identity/`. This document lets a fresh session continue without the old conversation. Read it, then read "Next steps".

**Where this document and an older record disagree, this document wins.** The older handoffs in `code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/` (`microvm-attestation-spike.md`, `microvm-workload-attestation.md`, `node-attestation.md`) describe the design and the spike. They show routes and names that we replaced. `docs/handoff.md` is the index of all handoff documents.

## Goal

Each agent microVM gets its own SPIFFE ID. The private key stays on the host, outside the VM. This matches the "Agent Workload Identity" of Google Agent Compute Engine. The ID has three parts: `spiffe://mcp.local/node/<host-name>/user/<github-id>/vm/<vm-name>`. The node is the host (here `omarchy`), and not a VM.

## State: it works on the real cluster

On 2026-11-07, I ran the flow on the live k3s cluster and the real VM `sandbox-dev`. The delegate got `spiffe://mcp.local/node/omarchy/user/raghav19/vm/sandbox-dev` from the host SPIRE agent, about 8 seconds after the VM entry existed. Two VMs at once, and a stop and start, also worked (tested on a scratch VM, now removed). The evidence is in the body of PR #280, which was open when I wrote this.

Not verified: `just msb run` from end to end. It needs the Bitwarden passphrase and ends in an interactive `ssh -t`. I ran its steps one by one.

## The design in one picture

Read the guide and the ADRs. Do not copy them here.

- Guide: `code/agent-workload-identity/docs/workload-attestation.md` (idea, diagram, cast, 5 mermaid flows, names).
- ADR 0001 (the route: Delegated Identity API with a pid and a custom plugin): `code/agent-workload-identity/docs/adr/0001-delegated-identity-for-the-microvm.md`.
- ADR 0002 (the host registers its entries under its own names): `.../docs/adr/0002-the-host-registers-its-entries-under-its-own-names.md`.
- Glossary: `code/agent-workload-identity/CONTEXT.md`. Use its terms. Say "delegate", not "proxy". Say "node entry", not "alias".
- Research with the evidence: `docs/research/microvm-workload-attestation-spire.md`, section "Spike results".

## The pull requests

| PR | What | State |
|---|---|---|
| #264, #265, #266, #267 | research update, ADR 0001, project scaffold, guide and diagram | merged |
| #268 | the first static entries (now removed by #278) | merged |
| #270 | the delegate (`delegate/`, 3 files, no SQLite) | merged |
| #275 | the `msbvm` plugin (`plugin/`, 3 files, two checks) | merged |
| #276 | removed the 26 MB binary that #275 added by mistake | merged |
| #278 | `host-register`, `vm-register`, ADR 0002, the renamed IDs | merged |
| #279 | `agent-install`, `agent-up`, `agent-status`, `agent-down`, `agent/` | **open, base main** |
| #280 | `identity` step, `run` and `rm` changes, idempotent `agent-up` | **open, base `awi-host-agent`** (stacked on #279) |
| #269, #271, #277, #260 | old plugin core, old plugin attest, throwaway e2e rig, Envoy in the VM | closed |
| #241 | old "attest step" of the VM agent | open, stale. Close it after you check. |

Merge #279, then #280. When #279 merges, retarget #280 to `main` (GitHub does it if the branch is removed).

## What runs on the host now (left on purpose)

- The host is registered: certificate `host-node-omarchy`, entries `node-omarchy`, `delegate-omarchy`, and `vm-omarchy-sandbox-dev` in the cluster.
- The agent runs as the user unit `awi-spire-agent` (`just msb agent-status`).
- The binaries are in `~/.local/share/agent-workload-identity/bin/` (`msbvm`, `delegate`). The delegate entry has this path as a selector.
- The SPIRE 1.15.5 release is cached in `~/.cache/agent-workload-identity/spire-1.15.5/`.
- Remove it all with `just msb agent-down`, `vm-unregister`, `host-unregister`.
- Leftovers on the SPIRE server from the old spike: the entry `spiffe://mcp.local/spike/agent` and an expired `join_token` agent. Nobody removed them. Do not touch the entries `sandbox-node`, `istio-ingressgateway` and the `k8s_psat` and `x509pop` agents. The `x509pop` agent `eac2a996…` is the agent in the VM.

## Decisions of the user (do not reopen without a reason)

- The microVM is the workload. The key stays on the host. The agent runs on the host.
- The delegate only guesses the pid (it scans `/proc`). The plugin is the one verifier. The delegate checks the SVID ID that comes back and picks the SVID by ID.
- The delegate has no `pidfd` and no database read. The user accepted this because the ID check covers the wrong-VM risk. The SPIRE docs say that the delegate must make sure that the pid is not recycled between the request and the answer. A `pidfd` belongs to a later, long-running delegate.
- The plugin checks two things: the exe is `msb`, and `msb.db` has a `Running` row with this pid. It does not parse the command line and does not compare start times. The user dislikes complex code. Keep new code small.
- The node is named after the host name. The entries of the host and the VMs are created by `just msb` recipes from templates in `.msb/k3s/`, and not from files in git.
- The user reads on a phone. Use short lists and narrow diagrams. The diagram has short sub-lines, labeled arrows, a flow panel and a legend by role.
- The user does not want test rigs with a throwaway server or a Go test harness. They want the real flow as part of the VM start.

## Next steps

1. **Review and merge #279, then #280.** Then run `just msb run` yourself and check for the line `VM identity: … (expires …)` before the editor opens. Tell me if it fails.
2. **Delegate lifecycle.** The agent holds one SVID for each entry, not for each start of the VM. After a stop and start, the delegate gets the same SVID and key until it expires (4 hours). Decide what the delegate does with the key (mTLS to the gateway? forward the VM traffic?). Drop the key when the VMM exits. Add a `pidfd` then. Keep the stream open and renew. This is open: ADR 0001 lists "a delegate that runs for a long time" and "whether the delegate needs its own SVID".
3. **The gateway rule** on the SPIFFE ID (node, user and VM). Open question: can agentgateway read a URI SAN in a rule? Part 3 has a failing `ExternalSecret github-upstream` in the namespace `agentgateway-system`. The Kustomization `mcp-servers` and four others wait for it. Nobody fixed it.
4. **Retire the agent in the VM** and its static node entry `sandbox-node` (`node/sandbox-dev`). The part 3 guides (`docs/node-attestation.md`, `zero-trust-node-attestation.md`, `zero-trust-workload-attestation.md`, the diagrams) still describe the old design. The Envoy guide has a "replaced" notice. Close #241.
5. **Clean the spike leftovers** on the SPIRE server (see above). Writes to the live server need the user. The permission check blocked such writes before.
6. **Artifacts.** No pipeline publishes the addon artifacts. The `spire` OCI artifact on the cluster is from Nov 5. The host registration does not need it. Check `just platform/publish-artifacts` in part 3 if you change the addon.
7. **Optional, later:** `tpm_devid` for the node key. The Broker API when it leaves "experimental". An ADR for the plugin and the delegate sizes if the user asks.
8. **Housekeeping.** Remove the local worktrees and branches of finished PRs (`herdr worktree list`, `herdr worktree remove`): `awi-*`. The local branch `awi-e2e` has the old e2e rig and is not needed. Remote branches of closed PRs: `awi-plugin-core`, `awi-plugin-attest`, `awi-e2e-test`.

## Lessons from this session

- **`go build ./...` in a folder with one `main` package writes a binary** there. I committed a 26 MB file (#275) with `git add -A`. Use `go build -o`, check `git status` before `git add -A`, and keep `.gitignore` entries (`plugin/` and `delegate/` have them now). The blob stays in the history of `main`.
- **Lint the PR body before `gh pr create`.** `ste-lint.py` hard violations (a semicolon, a sentence over 25 words, synonym rotation) must be 0. Fix the body, then create.
- **The local `main` is behind `origin/main`.** After `herdr worktree create`, run `git merge --ff-only origin/main` before you edit. Use `git switch -C <branch> origin/<other>` to start a branch at another remote branch.
- **A force-push of a branch with an open PR is denied** by the permission check. Add a plain commit, or open a new PR. GitHub's "Update branch" button merges `main` into the PR branch. Your next push is then rejected. Run `git fetch` and `git merge origin/<branch>`.
- **`just` variables override environment variables.** Pass a value as `just --justfile .msb/justfile MSB_NAME=x recipe`. A comment between `[env]` attributes and a recipe is a syntax error.
- **Go stamps the build path and the git commit into a binary.** The plugin checksum is in the agent config. The recipes build with `-trimpath -buildvcs=false`, so the checksum changes only when the code changes.
- **The agent needs about 5 seconds after it starts, and a new entry needs about 8 seconds, before the delegate gets an SVID.** Until then it gets `PermissionDenied: no identity issued` or zero SVIDs. Retry. Do not treat these as fatal.
- **The draw.io SVG export hides all text in a `foreignObject`.** `rsvg-convert` drops it, so the PNG has no text. I made the `.drawio` and a plain-text `.svg` from one model with a Python script, and then ran `rsvg-convert -z 2 -b white x.svg -o x.png`. **That script is not in the repo.** It was in a session scratchpad, and its copy in `/tmp/awi-handoff/make_diagram.py` can vanish. Python in this repo needs type hints, `ruff`, `ty` and a PEP 723 header (`docs/agents/python.md`), so I did not commit it. If you change the diagram, either edit `code/agent-workload-identity/docs/diagrams/agent-workload-identity.drawio` and the `.svg` by hand, or write the generator again as a typed `uv` script and commit it. The style rules are in `docs/agents/diagrams.md`. Read every label in the final PNG.
- **Mermaid check.** The rule says to parse each mermaid block. Install `mermaid@11` and `jsdom@25` with npm in an empty folder, and run this script (`node check.mjs <file.md>`):

```js
import { JSDOM } from 'jsdom';
import fs from 'fs';
const dom = new JSDOM('<!doctype html><body></body>');
globalThis.window = dom.window; globalThis.document = dom.window.document;
const { default: mermaid } = await import('mermaid');
const text = fs.readFileSync(process.argv[2], 'utf8');
const blocks = [...text.matchAll(/```mermaid\n([\s\S]*?)```/g)].map(m => m[1]);
let bad = 0;
for (const [i, b] of blocks.entries()) {
  try { const r = await mermaid.parse(b); console.log(`block ${i+1}: ok (${r.diagramType})`); }
  catch (e) { bad++; console.log(`block ${i+1}: ERROR ${e.message}`); }
}
process.exit(bad ? 1 : 0);
```

- **`msb inspect` has no pid.** `msb.db` (tables `sandbox` and `run`) is the only record of a pid next to a VM name. It is internal to msb (tested with 0.7.13). Run `just integration` in `plugin/` after an msb update. The real `msb.db` has few rows, so I could not test how msb handles a crash.
- **The `flux-schema-catalog` MCP server was not available.** `docs/agents/kubernetes.md` says to use it. I used `flux-schema explain -s ecosystem` and `flux-schema validate --schema-location default --schema-location ecosystem`. Say so before you edit a manifest.

## How to work in this repo

- Rules: `AGENTS.md`. Worktrees with `herdr worktree create --branch <b> --label <l>`. Never push to `main`. The PR steps are in `docs/agents/pull-requests.md`: identity, branch, push, compare `git ls-remote` with `git rev-parse`, duplicate check, create. Write the body with the `pr` skill template. End commits with the `Co-Authored-By` line and PR bodies with the generated-with line from the system reminder.
- All text follows Simplified Technical English: `python3 .claude/skills/asd-ste100/scripts/ste-lint.py <file>`.
- This session ran on the host (Linux, not in the msb VM). Before you ask the user to run a command, read `docs/agents/host-handoff.md`: push a branch and name the commit.
- Never run `just msb run` or `msb stop sandbox-dev` casually. The VM holds the user's session and secrets. Test with a scratch VM: `msb create alpine --name awi-scratch`, then `just --justfile .msb/justfile MSB_NAME=awi-scratch vm-register identity`, then `vm-unregister` and `msb rm -f awi-scratch`.
- Never print a key, a token or a join token. Do not read `~/.config/msb/host-node/node.key`.

## Suggested skills

- `pr` for every PR body. `asd-ste100` before you finish any change.
- `tdd` for any Go change in `plugin/` or `delegate/` (the delegate lifecycle).
- `gitops-knowledge` and the flux-schema CLI for any manifest in `.msb/k3s/` or the spire addon.
- `diagnosing-bugs` if `just msb run` or `identity` fails (look at `journalctl --user -u awi-spire-agent`).
- `research` for the agentgateway URI SAN question and for the Broker API.
- `domain-modeling` if you change `CONTEXT.md` or add an ADR.
- `code-review` before you ask the user to merge a large PR.

## Not checked

- `just msb run` end to end (see above).
- The `x509pop` re-attestation of the host agent after about 2 hours. The agent has run for about an hour.
- Renewal of the node certificate of the host (90 days, renewed after 60).
- A rename of the host.
- A host with a name that the recipes reject (they accept 1 to 40 characters: lower case letters, digits and `-`).
- mTLS with the SVID, and the gateway.
