# The simplest way to post the rendered manifest diff in a pull request

Question: What is the simplest design to hydrate the rendered manifests in CI and post the diff in a pull request, when the existing `<component>/diff` recipe does the diff? The goal is to make `changed` and `diff-report` in the part 3 `justfile` easy to read.

Source: `just` 1.58 and 1.59, `flate` 0.6.5, `flux-local` 4.3.1 action, GitHub Actions docs. Research date: 2026-10-20.

Evidence tags: **[repo]** means the claim comes from a file in this repo or from a measurement in the sandbox VM. **[primary]** means the claim comes from the project that owns the tool (README, changelog, action source, docs.github.com). **[secondary]** means a third-party statement that the owner's docs do not repeat.

**Status (2026-10-20):** the research below led to the workflow of PR #119 (merged as `ba39283`), but the final design is different in four ways. See "Outcome" and "Handoff" at the end. The findings and the measurements stay valid.

## Verdict

Remove `changed`. Run every component. Use one short `diff-report` recipe with a plain `for` loop.

1. Running all 17 components takes 35 s one after the other and 8 s with 8 jobs (warm tools). A selection step saves little time. It costs 18 lines of shell and one rule ("all components when `config/` changes") that is easy to get wrong.
2. The `diff` recipe already prints nothing but the diff once you cut its first lines. An unchanged component gives an empty result. The loop prints only the components that have a diff.
3. Stop a failed render at once. Do not collect errors. The job log shows the failing recipe. This removes `failed`, `exit $failed` and the error section.
4. Do not build a character budget in `just`. The job summary takes the full text (limit 1 MiB per step). The comment takes `head -c 60000` of the same file, one line in the workflow.

The three open points are in "Gaps and conflicts".

## Findings: this repo

| Claim | Source |
|---|---|
| The current `changed` and `diff-report` recipes are 59 lines (`justfile:35-93`). They use string concatenation, `$'\n'`, a 4-backtick fence, a 60,000 budget and `exit $failed`. | [repo] `code/mcp-sandbox/part-3-mcp-guardrails/justfile:35-93` |
| The `diff` recipe compares `out/baseline/manifests.yaml` with `out/<name>/manifests.yaml`. It removes CRDs and Secrets from both sides. | [repo] `lib/workflow/diff.just:7-19` |
| The `diff` recipe ends with `|| [ $? -eq 1 ]`. So the exit code is 0 when there is a diff and when there is none. The exit code cannot show a change. | [repo] `lib/workflow/diff.just:19` (measured: exit 0 in both cases) |
| All output goes to standard output. Standard error was empty in the measured runs. | [repo] measured with `just platform/routes/diff >o.out 2>o.err` |
| Lines before the diff text: one `config: <file>` line for each config file (4 lines now), then one `baseline: <ref>` line. The `config:` lines come from `config-builder`. The `baseline:` line comes from `_baseline`. `just -q` does not hide them. | [repo] `tools/config-builder/config_builder.py:58`, `lib/workflow/diff.just:32,35` |
| The diff text starts at the line `--- baseline`. An unchanged component prints no `--- baseline` line and no `@@` line. | [repo] measured on `platform/routes` with and without an edit |
| A component with no pin prints `baseline: none (...)`. The whole artifact then shows as added. | [repo] `lib/workflow/diff.just:8,30-33` |
| Each component writes to `out/<name>/`. All components share `out/values.yaml` (written by `config-builder`) and `out/tools/` (built by `build`). | [repo] `lib/workflow/package.just:43-53`, `lib/workflow/common.just:11-14` |
| `config-builder` opens `out/values.yaml` with mode `w`. It does not write to a temporary file first. So two parallel runs can read a half-written file in theory. | [repo] `tools/config-builder/config_builder.py:94-99` |
| The 17 components are the folders under `platform/` whose `justfile` imports `workflow.just`. | [repo] `grep -rl --include=justfile workflow.just platform` (17 results) |

## Findings: timing

Measured in the sandbox VM on 2026-10-20 with `just` 1.58.0 and `flate` 0.6.5. The baseline pull comes from `ghcr.io` through the sandbox proxy.

| Run | Result |
|---|---|
| One component, no `out/` folder (tools not built) | 17.6 s and 17.9 s. About 16 s of this is the one-time build of `config-builder` and `value-injector`. |
| One component, tools built | 1.7 s |
| 17 components one after the other, tools built | 35.3 s. The range is 0.7 s to 5.3 s. The mean is 2.1 s. |
| Same, with an empty `flate` cache (`FLATE_CACHE_DIR` set to a new folder) | 39.2 s. The cache after the run was 1.8 MB. |
| 17 components with `xargs -P 8`, tools built | 7.8 s. Every output file equals the sequential output. |
| 17 components with `xargs -P 8`, no `out/` folder | 45.1 s. **2 of 17 failed** (`ext-mcp`, `cert-manager`). The error is `Could not load PyInstaller's embedded PKG archive` and `objcopy Failure`. Eight jobs built the same tool at the same time. |

What this means:

1. Sequential cost on a fresh runner is about 18 s + 35 s, or about 55 s. This is small next to the time to install the tools.
2. Parallel runs are safe only after the tools exist. Build them once first. The commands `just tools/config-builder/build` and `just tools/value-injector/build` are the likely way. I did not run this exact pre-build step.
3. The warm parallel run showed no clash on `out/values.yaml` in one try. One try does not prove the write is safe (see the `config-builder` row above).

## Findings: `just`

The README and CHANGELOG are the source for all rows. https://github.com/casey/just/blob/master/README.md and https://github.com/casey/just/blob/master/CHANGELOG.md

| Claim | Version |
|---|---|
| `[script('bash')]` recipes run the whole body as one script. The repo pins `just` 1.58 (`mise.toml`), so a feature with a version above 1.58 is not safe. | 1.32.0 |
| `shell(command, args...)` returns the standard output of a command. | 1.27.0 |
| `[no-exit-message]` hides the `error: Recipe ... failed` line. | 1.7.0 |
| `[parallel]` runs the dependencies of a recipe at the same time. The list of dependencies is fixed in the file. | 1.42.0 |
| `--jobs` limits the parallel recipes. `num_jobs()` returns the number. | 1.56.0 |
| `--set NAME VALUE` and `NAME=VALUE` before the recipe override a variable. | no version tag in the README. Used by this repo's help text on 1.58 |
| `just foo/bar` runs recipe `bar` in `foo/justfile`. Extra recipes on the same command line are looked up in the same `foo/justfile`. So `just a/diff b/diff` does not work. Call `just` once for each component. | no version tag in the README ("Invoking justfiles in Other Directories"). Used by this repo on 1.58 |
| `--working-directory` works without `--justfile`. | 1.59.0 only |
| A recipe cannot loop over a list of folders by itself. A mapped dependency (`*(recipe args)`) with `[parallel]` can do it, but it needs `set unstable` and `set lists`. Both are marked unstable and "will change in backwards incompatible ways". | `lists` 1.53.0, unstable |
| The README shows GNU `parallel` or `#!/usr/bin/env -S parallel` for lines that run at the same time inside one recipe. | README ("Parallelism") |

What this means: the loop over components belongs in a `for` in the shell. `just` has no stable loop. The part 3 `justfile` already uses `[script('bash')]`, so a `for` loop adds no new feature.

## Findings: prior art

| Claim | Source |
|---|---|
| `flux-local diff ks` and `diff hr` render both sides and diff them. They compare two paths, `--path` and `--path-orig`. The action checks out the PR branch into `pr/` and the live branch into `live/`. | https://github.com/allenporter/flux-local/blob/main/action/diff/action.yml |
| `flux-local` does not select changed components. The user gives the path and the resource type. The README shows a **matrix** of cluster path and resource type, one job for each pair. | https://github.com/allenporter/flux-local/blob/main/README.md ("diff action") |
| `flux-local` limits size for each diff, not for the whole comment: input `limit-bytes`, default 10000. `diff-lines` (default 6) sets the context lines. | https://github.com/allenporter/flux-local/blob/main/action/diff/action.yml |
| `flux-local` skips CRDs and Secrets by default (`skip-crds`, `skip-secrets` are true). It strips noisy labels (`helm.sh/chart`, `checksum/config`, `app.kubernetes.io/version`, `chart`). | same file |
| `flux-local` returns the diff as the action output `diff` (empty when there is no diff). It writes multi-line output with a random delimiter in `$GITHUB_OUTPUT`. | same file |
| `flux-local` does not post the comment. The README posts it with a second action, `mshick/add-pr-comment`, in a `diff` fence of five backticks. It uses one `message-id` for each matrix item, so each item has its own comment. | https://github.com/allenporter/flux-local/blob/main/README.md |
| `flate` has a `diff` command (`ks`, `hr`, `images`, `all`). It diffs two Flux source trees (`--path`, `--path-orig`) or one tree against a Git revision (`--base <rev>`). | https://github.com/home-operations/flate/blob/main/README.md |
| `flate` has "changed-only mode". With `--path-orig` it finds which Flux Kustomizations own the changed files and renders only those. | same file ("Changed-only mode") |
| `flate diff` output styles (`-o`): `human`, `github`, `brief`, `gitlab`, `gitea`, plain unified `diff`, `json`, `html`. The `github` style prints `@@ <path> @@` lines that the GitHub diff block shows with colour. | same file (Behaviors) |
| `flate diff` strips noisy attributes with `--strip-attr`. The default covers chart-bump noise. | same file |
| The `flate` action only installs the binary and sets `FLATE_BASE` and `FLATE_CACHE_DIR`. It does not post a comment. | https://github.com/home-operations/flate/blob/main/action/action.yml |
| `mshick/add-pr-comment` cuts a message at 61,440 characters. The default `truncate: artifact` uploads the full text as an artifact and adds a link. `simple` cuts and adds a notice. | https://github.com/mshick/add-pr-comment/blob/main/README.md ("Message Truncation") |

What this means: no first-party tool selects changed components by itself and posts one capped comment. `flux-local` leaves both to the workflow. `flate` selects (changed-only) but compares Flux source trees. This repo compares two built `manifests.yaml` files, one of them pulled from the registry. Whether `flate diff` can replace the `diff` recipe here is not tested. See "Gaps and conflicts".

## Findings: GitHub limits

| Claim | Source |
|---|---|
| Each step can add at most 1 MiB to the job summary. If a step adds more, the upload of that step fails and an error annotation appears. The failed upload does not change the status of the step or job. | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands ("Step isolation and limits") |
| GitHub shows at most 20 step summaries for each job. | same page |
| A comment body is limited to 65,536 characters. | [secondary] `mshick/add-pr-comment` README, which says "GitHub's API limits comment bodies to 65,536 characters". The pages I read on docs.github.com (REST issue comments, Actions limits, workflow commands) do not state this number. |

What this means: `head -c 60000` keeps the comment under the limit. `head -c` counts bytes, and a byte count is never lower than the character count. The cut can fall inside a code fence. Add a closing fence and a notice after the cut.

## Gaps and conflicts

- The 65,536-character comment limit comes from a third-party README. The GitHub pages I read do not state it. A test comment with a body over the limit would settle it. I did not run it, because the run posts to the repo.
- I did not test whether `flate diff --path-orig` accepts the pulled baseline folder (it holds only `manifests.yaml`, plain objects, no Flux objects). The README describes Flux source trees. Treat `flate diff` as not usable here until a test shows otherwise.
- I did not test the pre-build of the two tools before a parallel run. The cold parallel failure is measured. The fix is not.
- Timing was measured once for each case in one VM. A GitHub runner has different network and CPU. The baseline pull from `ghcr.io` is the part most likely to differ.
- One disagreement between sources: the current `justfile` header says the report is "held under the limit of a pull request comment" by a budget in `just`. The prior art (`flux-local`, `add-pr-comment`) puts the size cap in the workflow or in the posting step. This note follows the prior art.

## Candidate designs

Ranked. All three keep the `<component>/diff` recipe as it is.

### 1. One recipe, all components, plain `for` loop (recommended)

`changed` is removed. `diff-report` is about 10 lines. Fail fast.

```just
# one Markdown section for each component that has a diff
[script('bash')]
diff-report:
    set -euo pipefail
    for c in $(grep -rl --include=justfile workflow.just platform | xargs -n1 dirname | sort); do
      diff=$(just "$c/diff" | sed -n '/^--- baseline/,$p')   # cut the config: and baseline: lines
      [ -n "$diff" ] || continue                            # no diff: print nothing
      printf '<details><summary>%s</summary>\n\n```diff\n%s\n```\n\n</details>\n\n' "$c" "$diff"
    done
```

- In `just`: the loop above. It prints Markdown on standard output.
- In the workflow YAML: build the two tools once. Run `just diff-report > report.md`. Write `report.md` to the job summary. For the comment, run `head -c 60000 report.md`, add a closing fence and the line "Cut. See the job summary." only when the file is longer, then post with `gh api`. If `report.md` is empty, post "No rendered manifest changes."
- Trade-off: a render failure in one component stops the report. The log shows the failing recipe, but the reviewer sees no diff for the other components until it is fixed. A component with no pin shows its whole artifact as added. Time: about 55 s on a fresh runner.
- Optional speed-up: build the tools first, then `xargs -P 8`. This gives about 8 s, but needs one output file for each component. Do not start with it.

### 2. The workflow YAML holds the loop, `just` has one tiny recipe

```just
# the component folders, one for each line
[script('bash')]
components:
    grep -rl --include=justfile workflow.just platform | xargs -n1 dirname | sort
```

```yaml
# workflow step (about 10 lines of shell)
- run: |
    for c in $(just components); do
      d=$(just "$c/diff" | sed -n '/^--- baseline/,$p')
      [ -n "$d" ] && printf '<details>...</details>\n' "$c" "$d" >> report.md
    done
```

- In `just`: only the list of components. In the YAML: the loop, the Markdown and the posting.
- Trade-off: the same logic as design 1, but a developer cannot run it on a laptop with one command. The YAML grows and has no `shellcheck` or `just --fmt` check. The justfile stays smallest.

### 3. Matrix: one job for each component (the `flux-local` example)

```yaml
strategy:
  matrix:
    component: [platform/routes, platform/addons/istio, ...]   # 17 entries, kept by hand or by a prior job
steps:
  - run: just ${{ matrix.component }}/diff   # then one comment for each component
```

- In `just`: nothing new. In the YAML: the matrix, the tool install in each job and one comment for each component, with its own comment marker.
- Trade-off: each comment is far below the size limit, so no cut is needed. But 17 jobs install the tools and build the two helpers 17 times (about 18 s each). A pull request can get up to 17 comments. The matrix list needs upkeep when a component is added. Use this only if one component grows large enough to fill a comment alone.

## Outcome: what was built (PR #119)

The pull request workflow is `.github/workflows/manifest-diff.yaml`. It does not use any of the three designs above as written.

| Topic | Research verdict | What was built |
|---|---|---|
| Which components | Run every component. | One matrix job for each folder with `flux/stack.yaml` (`just components`). The four folders without it are not in the matrix. |
| Loop | A `for` loop in `just`. | No loop. GitHub starts one job for each component, and each job runs the recipes of its component. |
| Comment | One comment, cut with `head -c 60000`. | One comment for each commit. A Jinja template builds it. Over 60,000 characters the comment holds a note and the link to the run. |
| Failure | Fail fast. | Same. A failed job stops its component and the comment lists only the finished ones. |
| Publish | Not covered. | A component is published to ghcr.io only when its diff is not empty. |

Moving parts:

- `.github/scripts/render.py` (typer and jinja2, run by `uv run --locked --script`) fills a template with `--var`, `--file` and `--glob` values. It knows nothing about diffs.
- `.github/templates/manifest-diff-section.md.j2` is the block of one component. `manifest-diff-comment.md.j2` is the comment and holds the size rule.
- Each matrix job uploads its block as a GitHub artifact. The `comment` job downloads all blocks and posts one comment with `mshick/add-pr-comment`. The comment steps run only when `hashFiles` finds a block.
- The ghcr.io token comes from Bitwarden through `bitwarden/sm-action` (v3.0.1). The only GitHub secret is `BWS_ACCESS_TOKEN`.
- The diff compares with the artifacts that `main` pins, not with the files on `main`.

## Handoff

### Open work

1. **Merge the route fix.** The demo change `/mcp-test` in `platform/routes/httproute.yaml` was merged by mistake with #119. A follow-up PR (`fix/route-path-mcp`, #123) sets it back to `/mcp`. The cluster was not affected: `sync/local-kind/infra-stack.yaml` pins the `routes` artifact at `sha256:558bc4e9…`, which has `/mcp`. After the merge the workflow should show no diff for `routes` and post no comment.
2. **Delete what the tools cannot delete:** the repo secret `GHCR_TOKEN`, the stray bot comments on PR 119, and the packages `ghcr.io/raghav19/mcp-guardrails-spike/*` (routes, cert-manager, spire). The versions of `mcp-guardrails/routes` and `spire` that CI published have no pin and are harmless.
3. **Not yet run on GitHub:** the over-limit note with the final `render.py`, and a pull request with no diff at all (#123 is the first).

### Known limits

- A change in `config/` alone does not start the workflow.
- Pull requests from forks are skipped, because their token cannot read the secret or push.
- Comments only grow: one for each head commit that has a diff.
- The baseline is the pinned artifact, so unpublished changes already on `main` (for example the `spire` Service from #117) appear in every diff until they are published and pinned.
- `bitwarden/sm-action` downloads its binary at run time and does not check a checksum. The pin by SHA does not cover that binary.
- `ext-mcp`, `ext-mcp-checks`, `ext-mcp-isolation` and `mcp-mtls` have no `flux/stack.yaml`. Commit `f75adf5` (#66) removed them from the stack because `ext-mcp` does not start. They return to the matrix when they get one.

### Gotchas

- **The access-token secret.** Setting it with `bws-secret.sh token | gh secret set …` stored terminal escape characters. The value started with `ESC ]` and had two colons. The action then failed with "Has the wrong number of parts". Set it from the file: `gh secret set BWS_ACCESS_TOKEN --repo raghav19/engineersdaybook < ~/.config/bws/access-token`. Check only the shape of the secret (3 dot parts, 1 colon, starts with `0.`, no non-printable character), never its value.
- **`flux-schema`** must be in the `install_args` of the matrix job and in the root `mise.toml`. Without it Hydrate fails with exit code 127. The sandbox has the tool, so local runs hide the error.
- **A re-run keeps the old merge commit.** GitHub re-runs use the same `GITHUB_SHA` and `GITHUB_REF` as the original event. To refresh a diff after `main` moves, push to the PR branch. The comment id holds the PR head commit: a new push adds a comment and a re-run of the same commit updates its own comment.
- **`uv run --locked --script`** needs `render.py.lock` next to the script. Create it with `uv lock --script`.
- **`envsubst` is not in the sandbox.** The Jinja script replaced it.
- **The pre-commit hook** `end-of-file` removes a trailing blank line. The section template starts with a blank line for that reason.
- **Reading CI logs** without `gh`: the REST API works with `curl` for this public repo (`/actions/runs`, `/actions/runs/<id>/jobs`). `/actions/jobs/<id>/logs` redirects to a blob URL that `curl` can read.
- **GitHub from the sandbox** goes through the `mcp__mcp-gateway__*` tools. They cannot delete comments or packages, re-run a workflow, or set secrets. Pushing a workflow file needs the `workflow` scope on the sandbox-scoped `github` secret.

### How to work in this repo

- Git has no identity in the sandbox. Commit with `-s`, the author name and e-mail of the owner (see `git log`), and the trailer `Assisted-by: claude-code/<model id>`. Do not use `Co-authored-by`.
- The checkout at `/home/rana/Projects/engineersdaybook` is shared with other sessions. Do not switch its branch. Use a separate `git worktree` and push from there. Never push to `main`.
- Show a plan or a spike before a design change. The owner asks for it every time.
- Run a spike on a throwaway branch (`spike/…`) with its own workflow file, then delete the branch.
