# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues on `raghav19/engineersdaybook`. Outside the sandbox, use the `gh` CLI for all operations. Inside the sandbox (`$SANDBOX_NAME` is set), use the gateway tools in the next section instead, and do not run `gh` or `curl` against GitHub (see `AGENTS.md`, section 6).

## Inside the sandbox: gateway tools

Every `gh` command in this file, the PR and wayfinding ones included, maps to a tool on the sbx MCP gateway. Each tool is `mcp__mcp-gateway__<name>`. The tools are deferred, so load their schemas first with ToolSearch (`select:mcp__mcp-gateway__issue_read,...`). Pass `owner` = `raghav19` and `repo` = `engineersdaybook`.

| `gh` command | Gateway tool |
| --- | --- |
| `gh issue create` | `issue_write` with `method: create` (`title`, `body`, `labels`) |
| `gh issue view <n> --comments` | `issue_read` with `method: get`, then `get_comments` and `get_labels` |
| `gh issue list` | `list_issues` (`state`: `OPEN`/`CLOSED`, `labels`; use `fields` to drop `body`) |
| `gh issue comment <n>` | `add_issue_comment` (`issue_number`, `body`) |
| `gh issue edit --add-label` / `--remove-label` | `issue_write` with `method: update` and the full `labels` list. It replaces the current set, so read it first with `issue_read` `get_labels` |
| `gh issue edit --add-assignee @me` | `issue_write` with `method: update` and `assignees` (the login from `get_me`) |
| `gh issue close <n> --comment` | `issue_write` with `method: update`, `state: closed`, `state_reason`; add the comment with `add_issue_comment` first |
| `gh pr view <n>` / `gh pr diff <n>` | `pull_request_read` with `method: get` / `get_diff` (also `get_comments`, `get_files`, `get_check_runs`) |
| `gh pr list` | `list_pull_requests` (`state`, `head` as `user:branch`); `search_pull_requests` to filter by author |
| `gh pr create` / `gh pr edit` / `gh pr close` | `create_pull_request` / `update_pull_request` (`title`, `body`, `state`) |
| `gh pr comment <n>` | `add_issue_comment` with the PR number as `issue_number` |
| sub-issue through `gh api` | `sub_issue_write` with `method: add`. `sub_issue_id` is the database id, not the number; `issue_read` `get_sub_issues` lists the children |

There is no gateway tool for issue dependencies (`.../dependencies/blocked_by`). In the sandbox, use the `Blocked by: #<n>, #<n>` fallback line from the wayfinding section.

## Conventions (`gh`, outside the sandbox)

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
