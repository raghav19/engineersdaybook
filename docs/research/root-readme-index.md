# Project index for the root README

Question: How should the root `README.md` index this repo so a visitor finds the right project fast?

Source: GitHub Docs (pages read 2026-10-19). Research date: 2026-10-19.

Evidence tags: **[repo]** means the claim comes from a file in this repo. **[primary]** means the claim comes from GitHub Docs. **[inference]** means our own conclusion. No primary source states it.

## Verdict

Write a manual index. Use one table per theme. Link to files, not to heading anchors.

1. GitHub builds an outline of the headings by itself. It does not build summaries. The index adds the one thing the outline cannot give: what each project achieves.
2. A table gives a visitor one row per project, with the link, the result and the kind side by side. The README is short, so the first project link is visible without scrolling.
3. Relative links to files keep working on every branch and in clones. Heading anchors break when a heading changes.
4. Keep the index by hand. The repo has no hook that lists projects. A hook costs more than six rows of text.

Rejected options:

- Plain bullet list: no room for the result and the kind without long lines.
- One table with all rows: the sandbox projects and the infra projects have different readers. Two themes let a visitor skip a half.
- Auto-generated index (hook or `just` recipe): extra code. It cannot write the "what it achieves" sentence.
- Collapsed sections: GitHub Docs do not cover them on the formatting page. They hide the index that the visitor came for.

## Findings: GitHub behavior

| Claim | Source |
|---|---|
| A README typically says what the project does, why it is useful, how to start, where to get help and who maintains it. | [primary] https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes |
| A README "should only contain information necessary for developers to get started using and contributing to your project." | [primary] same page |
| "GitHub will automatically generate a table of contents based on section headings." The reader opens it with the Outline icon. | [primary] same page |
| GitHub shows the README from `.github`, then the root, then `docs`. This repo has the README in the root only. | [primary] same page, [repo] `README.md` |
| GitHub truncates a README after 500 KiB. | [primary] same page |
| GitHub changes a relative link to match the branch the reader views. Relative links also work in clones. | [primary] same page |
| A link that starts with `/` is relative to the repository root. | [primary] https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax |
| Link text must be on one line. | [primary] same page |
| Absolute links "may not work in clones of your repository". | [primary] same page |
| A heading anchor is the heading in lower case, with spaces as hyphens. A repeated heading gets a number suffix. | [primary] same page |
| A heading change breaks links to its anchor. | [primary] same page |
| A table needs a blank line before it. Each header cell needs at least three hyphens. Cells need not align. | [primary] https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-tables |
| A cell can hold links, inline code and text styling. To show a pipe in a cell, write `\|`. | [primary] same page |
| Use alerts only when they are crucial. Use at most one or two per page. | [primary] basic-writing-and-formatting-syntax page |

## Findings: this repo

| Claim | Source |
|---|---|
| The root `README.md` has two lines: a title and "my dabbling with tech and perspectives". | [repo] `README.md` |
| Each folder under `code/` is an independent project with no shared domain. The index must not imply one. | [repo] `docs/agents/domain.md` |
| `code/agent-sandbox` runs Claude Code in an `sbx` microVM. The sandbox caps what a fooled agent can do. | [repo] `code/agent-sandbox/README.md` |
| `code/mcp-sandbox` has no README of its own. It holds three parts, each with a README. | [repo] `code/mcp-sandbox/` |
| Part 1 is a proof of concept against real GitHub infrastructure. The agent recognized the injected instruction twice and refused. | [repo] `code/mcp-sandbox/part-1-lethal-trifecta/README.md` |
| Part 2 seals one local MCP server in rootless Docker. The only route out is an egress proxy that logs each outbound attempt. | [repo] `code/mcp-sandbox/part-2-sandboxing-local-mcp/README.md` |
| Part 3 puts one gateway in front of three MCP servers. It checks identity, arguments and results. It maps the OWASP MCP Top 10. | [repo] `code/mcp-sandbox/part-3-mcp-guardrails/README.md` |
| `code/rootless-docker` holds a setup guide. It cites three container-escape CVEs. Rootless blocks two of them and downgrades one. | [repo] `code/rootless-docker/README.md` |
| `code/devk8s-kind-wsl2` builds a local Kubernetes stack with kind on WSL2. It adds operators, services, routes and four dashboards. | [repo] `code/devk8s-kind-wsl2/README.md` |
| `code/configuration-heirarchies` is a sample of the configuration-hierarchy pattern. `ansible-inventory` shows how variables inherit from `DEV` to `dev01` to `user1`. | [repo] `code/configuration-heirarchies/README.md` |
| `code/env-config-management` applies the same pattern to local tools and env vars with `mise`. | [repo] `code/env-config-management/README.md` |
| `blog/spec-driven-workflow/post.md` describes the order `grill-me`, `to-spec`, `to-tickets`. | [repo] `blog/spec-driven-workflow/post.md` |
| `.sbx/README.md` describes the dev sandbox. `just sandbox` runs its recipes. | [repo] `.sbx/README.md`, `justfile` |
| The folder name `configuration-heirarchies` has a spelling error. Links must use the real name. | [repo] `code/configuration-heirarchies/` |
| The repo has no hook or recipe that lists projects. `prek.toml` runs secret, YAML, file-size and Python checks only. | [repo] `prek.toml`, `justfile` |
| The `_archive` and `docs/research` folders are out of the index. This is a decision of the owner. | [repo] owner decision, 2026-10-19 |

## Design for the index

| Item | Choice | Basis |
|---|---|---|
| Order | Title, purpose line, two tables, writing, licence | [inference] A visitor sees the projects first. |
| Grouping | Two themes: sandboxing agents and MCP, and local infra and config | [inference] The projects fall in two reader groups. |
| Columns | Project, what it achieves, kind | [inference] The result sells the project. The kind sets expectations. |
| Kind words | series part, proof of concept, setup guide, pattern sample, how-to | [inference] Each word matches the project README. |
| Row for MCP series | One row per part | [repo] The three parts have different READMEs and different results. |
| Links | Relative, to the project README file | [primary] Survive branches and clones. |
| Anchors | None | [primary] A heading change breaks them. |
| Upkeep | Manual. Update the row in the same pull request that changes a project. | [inference] Six rows. A hook costs more. |

## Gaps and conflicts

- No primary source covers how a table renders on a phone. Check the render on GitHub after the push.
- No primary source states a best length or best order for a README index. The design choices above are inference.
- The pages read give a general README guide. They do not cover a repo that holds many independent projects.
- The formatting page does not cover `<details>`. We do not use it.
- We did not check the published blog. The index does not link it.
