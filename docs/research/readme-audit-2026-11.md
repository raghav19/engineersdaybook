# README audit of the projects

Question: Does the README of each project match its code? Can a stranger follow the steps on a fresh workspace and a fresh system?

Source: eight read-only subagents. Each one read one project, ran only safe checks and returned a report. Audit date: 2026-11-06. Repo state: `main` at `6695fa6`.

Evidence tags: **[ran]** an agent ran the step safely. **[static]** an agent checked the step against files. **[unverifiable]** the step needs sudo, a cluster, a VM, an account or a token. **[handoff]** the fact comes from a handoff document of the owner and nobody repeated it. **[rechecked]** the main session checked the finding again after the audit, from a primary source or with a command.

## Limits

- No step ran on a clean host. Docker was not installed on the audit host (only Podman). No agent started a cluster or a VM, or used an account.
- "Reproducible" here means that reading and safe runs found no defect. It does not mean that someone followed the steps.
- Only the items tagged **[rechecked]** got a second look. Check every other finding again before you fix it.
- The `ansible-inventory` commands never ran. Their expected output comes from a hand calculation.

## Verdict

| Project | Verdict | Status after its fixes |
|---|---|---|
| `agent-sandbox` (microsandbox) | WIP | WIP: needs a k3s cluster, a GitHub App, a Qwen key and the author's registry |
| `agent-sandbox` (tag `docker-sbx`) | WIP, mostly done | WIP: needs the author's private kits and App |
| `mcp-sandbox` part 1 | WIP | Done: it records one run |
| `mcp-sandbox` part 2 | WIP | WIP until the server-side config is back in the repo |
| `mcp-sandbox` part 3 | WIP | WIP: the platform and the node step work, the guardrails do not |
| `rootless-docker` | WIP | Done after one run on a host |
| `devk8s-kind-wsl2` | WIP | Done after one run on WSL2 |
| `configuration-heirarchies` | WIP | Done after one real `ansible-inventory` run |
| `env-config-management` | WIP | WIP until the secret-file steps are rewritten |
| `ephemeral-env` | WIP (not in the root README) | WIP: the sandbox flow is not built |
| `blog/spec-driven-workflow` | Done | Done after four text fixes |

## agent-sandbox, microsandbox (`code/agent-sandbox/README.md`)

False or stale:

- Lines 11, 17, 27, 28 name `.msb/sandbox.yaml`. The file is `.msb/vm/sandbox.yaml`. [static]
- Line 29 cites "prerequisite 2". The GitHub token is prerequisite 5. [static]
- Line 39 says tokens last about 8 hours. `.msb/README.md:52` says to turn expiration off, and the comment at `.msb/msb.py:41-42` is stale. [static]
- Line 42 says SPIRE and kind are not ported. The SPIRE agent is in the image (`Dockerfile:39`, `sandbox-boot:60-83`), and `run` fails without it. k3s replaced kind. Only the Envoy workload step is missing. [static]

Overstated:

- Line 17: the deny list of five GitHub tools covers Claude Code only. `qwen-settings.json` has the same GitHub MCP server and no deny list. [static]
- Line 13 omits the ServiceAccount that can write in the namespace `sandbox-dev` (`rbac.yaml:96-120`). [static]
- Line 18 lists 2 placeholders. `sandbox.yaml` has 5. [static]

Not reproducible by a stranger: [static], and [unverifiable] where an account is needed.

- Missing prerequisites: a k3s cluster with the part 3 SPIRE add-on, a mandatory Qwen key (`justfile:41`), an Omarchy host and a GitHub App. The client id of the App is in `msb.py:44`. Also missing: a Bitwarden project with 5 keys and your own registry. The pinned image digest is private (HTTP 401).
- `just msb sync-kubeconfig` is required before the first run and is missing from the steps.
- `.msb/README.md` drifts from the code. "Exact versions" is false: the pins are prefixes and the base image is unpinned. `TTT_PLUGINS_REF` does not exist. The config paths are `image/configs/editor/`. Decision 19 contradicts the code. `headroom-home` is missing from `justfile:51`. "All four keys" is five. `run` opens Herdr.
- `msb doctor` passed. [ran]

## agent-sandbox, tag `docker-sbx`

- Two links are broken: `docs/research/readme-notes.md` (line 21) and `docs/writeup/executive-one-pager.html` (line 85). [static]
- Line 285 lists `.sbx/host/README.md`. It does not exist. Line 30 links an asciinema page that returns HTTP 410.
- The prerequisites omit `gh auth login`.
- The kits are private packages under `ghcr.io/raghav19`, and the GitHub App client id is the author's.
- All `just sandbox` recipes of steps 1 to 8 exist. [ran, on an extracted copy of the tag]
- A fix needs a new tag or a docs commit on top of the tag. The tag is immutable.

## mcp-sandbox part 1 (`part-1-lethal-trifecta`)

- "Twice" is partly supported. Trial 2 is PR #3 on GitHub. Trial 1 has only pasted chat text. PR #2 also refused and the README does not say so. The model refused three times. [ran, `gh api`]
- The diagram and `spec.md` (lines 15, 83) say a PR opened and the issue closed in both trials. Trial 1 opened no PR. Issue #1 is open.
- "Private repo never fetched" has no MCP call log behind it. `verify-no-leak.sh` only checks PR diffs for 3 strings. [ran, as the repo owner]
- No prerequisites section. Repo names are hard-coded to `raghav19`. The bait file and the first issue body are not in the repo.
- `verify-no-leak.sh` fails for everyone but the owner of the private repo. Without a `gh` login it exits 4. [ran]
- Script 03 asks "did the agent open a PR?". It does not handle the refusal that the README describes. The MCP image and the model are not pinned.
- Lines 153-155 call the gateway "Part 2". It is part 3. Scripts 01 to 04 keep old ticket numbers.

## mcp-sandbox part 2 (`part-2-sandboxing-local-mcp`)

- The proxy half is sealed in `compose.yaml` and `squid.conf`: an internal network, an allowlist with `api.github.com` only, a read-only root, dropped capabilities and `no-new-privileges`. [static]
- The server-side flags in the README table (`--read-only`, `--cap-drop`, `--user 10001`, `--network`, journald) are in no current file. They survive in git history (`git show ab25fbf:.mcp.json`). [static]
- The `.mcp.json` link at line 48 is dead. Line 3 is empty.
- "Logs each outbound attempt" is too strong. Only requests that reach the proxy appear in the log. A direct attempt fails at the network without one.
- No test step exists for the sealed network or the proxy log.
- Missing: `mise` and `mise trust` as prerequisites, the GitHub App permissions and install step, the key location and the working directory for `docker compose up`. The chown command hard-codes the key file name.
- Docker was not installed, so nothing ran. [unverifiable]

## mcp-sandbox part 3 (`part-3-mcp-guardrails`)

Works: the k3s and Flux bring-up, 13 units in 3 groups (3 + 3 + 7), the build and publish tools and the secret store. SPIRE with `x509pop` works too, and the first node attestation ran on 2026-11-05. [handoff] [static]

Written but not proven or not deployed:

- `ext-mcp` has `rules.py` and 5 passing unit tests. It has no server, no image and no `flux/stack.yaml`. [ran]
- `ext-mcp-checks`, `ext-mcp-isolation` and `mcp-mtls` are in no stack. `ext-mcp-checks` is fail-closed and would block every call. [static]
- `authn-jwt` has an empty key set, so it rejects every call. Dex is nowhere in the repo. The policy names Keycloak and the README names Dex. [static]
- `tool-rbac` is one global deny list of 5 tools, not a grant per user. [static]
- The gateway group was blocked at the last record. The ExternalSecret `github-upstream` fails (cause unknown). [handoff]
- MCP08 ("not wired yet") is true. Only 2 of 10 attack tests exist. [static]

README defects:

- No "Quick start" section. A fresh clone needs the author's private `ghcr.io` packages, Bitwarden IDs and fork URL.
- Lines 42-59 describe the target design in the present tense. The OWASP table claims controls that are not built.
- The repo tree (lines 95-115) has wrong entries. Line 130 is wrong: `compose-stack` builds and pushes `stack-composer`, so it needs registry credentials.
- `zero-trust-node-attestation.md` says "Status: design" (line 3), and its own section 10 says parts 1 to 5 are done. Lines 32, 33 and 37 hold 4-column rows in a 2-column table. Line 186 and line 151 disagree on who makes the CSR (the host or cert-manager). Line 207 describes the admin kubeconfig that #244 removed.
- `zero-trust-workload-attestation.md` is a legacy design with a broken anchor. `arch.md` describes Dex, onboarding, ext-mcp, mTLS and a join token in the present tense.
- `app-of-apps-pattern.md` section 7 misses one cross-group `dependsOn`: `spire` waits for `cert-manager`.
- Stale comments: `ext-mcp/deploy/kustomization.yaml:13`, `mcp-mtls/peerauthentication.yaml:7`, `ext-mcp-checks/kustomization.yaml:3-4`, `istio-ingress/spire-route.yaml:10`, `authn-jwt/policy.yaml:19`.
- Issues #10 to #14 are stale (kind, Cognito, Kyverno).
- `config/cloud/k3s/bitwarden.yaml` commits Bitwarden org and project IDs, and a handoff says to keep the project ID out of docs. The owner must decide.

Proposed status label for the node step: "The node step works. Not enforced." No gateway rule uses the SPIFFE ID. The second attestation and the two negative tests are open.

## rootless-docker (`code/rootless-docker/README.md`)

Fixed on the branch `docs/rootless-docker-readme-fixes`. All items below are **[rechecked]** unless the text says otherwise.

- The three CVE IDs are right. The advisories quote the text that the README quotes. Rootless blocks only the final host write in CVE-2019-5736 and CVE-2025-52881. In CVE-2024-21626 it reduces the impact. The root README row says it "blocks the escape" and overclaims.
- No install step. `docker` and `rootlesskit` are in Arch `extra`. `docker-rootless-extras` is in the AUR and ships `dockerd-rootless.sh` and the user units.
- Line 54 has the typo `$XDG_2RUNTIME_DIR`. The "context: should read rootless" check is wrong, so it now checks "Security Options".
- The bind-mount demo cannot create the file. Container uid 1000 is host uid 100999, and it cannot write in a directory that the host user owns. The result is `Permission denied`. [rechecked with `rootlesskit`, not with Docker]
- The ACL command pointed at `./data`, which does not exist.
- Docker docs: overlay2 needs kernel 5.11 or later, and cgroup v2 is needed only for resource limits.
- Not changed: the port-80 demo output. A subagent claims that `docker run` fails with "cannot expose privileged port 80" and leaves the container in `Created`. Nobody ran it. [unverifiable]
- The project has no `CONTEXT.md` and no `docs/adr/`.

## devk8s-kind-wsl2 (`code/devk8s-kind-wsl2`)

Fixed on the branch `docs/devk8s-kind-readme-fixes`.

- Checks that passed: all 6 Helm chart versions, 5 CRD URLs and the kind node image exist, and all 5 kustomizations build. [ran] `flux-schema validate` found no error in the 4 local kustomizations. [ran]
- Headlamp had no route. `addons/routes/dashboard.yaml` duplicated the Headlamp `HelmChart`. It is now an `HTTPRoute` to the service `headlamp` on port 80. [rechecked: rendered the chart, built and checked the manifest]
- The `crds` step installs the CloudNativePG operator and the k3s helm-controller as Deployments, not only CRDs. [rechecked]
- The README lacked `kubectl`, the clone step, a free port 80 and the memory need. `kind.yaml` is written to `$HOME` but was read from the current directory.
- Not changed: `addons/services/metrics.yaml:35-37` has `limits` at the wrong indent, so Kubernetes ignores them. A fix would start to enforce 256Mi. Nobody tested that.
- Not changed: the unused ConfigMap `es-ilm-policy` and the unused namespace `app`.
- Not run: `kind create cluster` and every apply step. [unverifiable] The project has no `CONTEXT.md`.

## configuration-heirarchies

- The merged values of all shown outputs match a hand calculation. [static] `ansible` was not installed, so nobody ran the commands. [unverifiable]
- Line 3 ends with an empty "blog post ->" link. The old post moved to Medium. The owner must give the URL.
- No `ansible-core` version or install command. One `--list` block shows 4 commands and only one output (PRE).
- The tree (lines 52, 54) lists `playbooks/` and `roles/`. They do not exist.
- The four `aws_us_*_account` folders under `inventories/group_vars` are loaded by no inventory. Lines 233-234 claim prod vars. `PROD/prod/group_vars` holds only a symlink.
- `eks_ssm_parameter_name` shows an unrendered template. Whether `ansible-inventory` renders it depends on the version. [unverifiable]

## env-config-management

- The `mise` layering of tools and env is right. [ran, in a throwaway `HOME`]
- A stranger stops at the first command. The config is untrusted (the README has no `mise trust`). The committed secret files are encrypted to the author's age key, so every `mise` command fails with a decrypt error. [ran]
- The order is circular: `age` and `sops` come from `mise install`, which needs the decrypted files.
- `age-keygen -o $HOME/.config/mise/age.txt` fails without `mkdir -p`. `sops encrypt -i` fails on the committed file ("already encrypted"). [ran]
- Line 67 shows the wrong secret path. Line 76 names `.mise.toml` and `.mise.dev.toml`, but the files have no leading dot. The blog link on line 3 returns 404.
- The tasks need `tools/requirements.txt`, `tools/requirements.yaml` and `.vault-pass`. They are not in the repo. Two tasks use `sudo apt-get`. [static]
- `mise.toml:45` (`trusted_config_paths`) is a dead setting. `mise.toml:3-12` holds credential-shaped plaintext. It looks like placeholders. The owner must check that none is real.
- "Level 0 -> global" (line 11) is wrong. The file is a project file, and the repo root `mise.toml` also applies.

## ephemeral-env (`code/ephemeral-env/README.md`)

- `just check` passes: 36 of 36 Boutique manifests and 2 of 2 `clusters/k3s` manifests are valid. [ran] Nothing ran on a cluster. [unverifiable]
- The README says the sandbox flow is not built. Status: WIP. The root README does not list the project.
- **Possible security defect, not rechecked.** The guard `_host` tests `SANDBOX_NAME` (`justfile:34`, `clusters/k3s/justfile:35`, and part 3 `clusters/k3s/justfile:67`). The msb VM sets `SANDBOX_WORKSPACE` and `SANDBOX_BRANCH`, not `SANDBOX_NAME` (`.msb/vm/sandbox.yaml:18-30`). If so, the guard never fires in the VM, and the registry token could be used there. [static]
- Step 2 overwrites `~/.kube/config` with no warning. Step 3 does not say that `mise trust && mise install` installs the tools.
- The registry `raghav19` is hard-coded in `justfile:3`, in `flux-instance.yaml` and in `GHCR_USER`.
- `code/platform-engineering` is tracked (17 files) and has no top-level README. It is the older base of this project.

## blog/spec-driven-workflow/post.md

- Done after four text fixes. [ran]
  - Line 67 says `mise.toml` keeps the skills. The root `justfile` and `skills-lock.json` do.
  - Line 65 names a `CLAUDE.md` that does not exist.
  - "Four skills" (lines 9, 49, 63) conflicts with the six commands the post shows.
  - Lines 43-45 describe a chain, but the tickets form a graph.
- The claim "finished, working result" is soft. The Part 1 result is a refusal.

## Root README

- All 13 relative links and the tag `docker-sbx` resolve. [ran]
- The app of apps row (3 groups, 13 units) and the rendered manifest row match the code. [static]
- The zero trust row reads as built, and the page says "design".
- Line 4 ("Each project is independent") is only partly true. The zero trust doc needs `.msb/` and the root `justfile`. Tools come from the root `mise.toml`.
- The `rootless-docker` row overclaims. The part 2 row overclaims "logs each outbound attempt".

## Where each part is in the repo

- The handoff with the plan: `docs/handoff/readme-audit.md`.
- The two drafted fixes: the branches `docs/rootless-docker-readme-fixes` and `docs/devk8s-kind-readme-fixes`.
