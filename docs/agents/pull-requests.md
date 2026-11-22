# Pull requests

Open a PR with the GitHub MCP tool `mcp__github__create_pull_request`. The sandbox has no `gh`. Do these steps in this order. If a step fails, stop and report the exact error text. Do not go on to the next step.

Claude Code defers the GitHub MCP tools. Before step 1, load them with ToolSearch: `select:mcp__github__get_me,mcp__github__list_pull_requests,mcp__github__create_pull_request,mcp__github__update_pull_request`.

1. Git identity. Run `git config user.name` and `git config user.email`. If either prints nothing, call `mcp__github__get_me` and read `login`, `id` and `email`. Then run `git config user.name "<name>"` and `git config user.email "<email>"`. If `email` is null, use `<id>+<login>@users.noreply.github.com`. Never use `--global`. Never invent a value.
2. GitHub identity. Call `mcp__github__get_me`. If it returns an error, or `login` is not `raghav19`, stop. Tell the user that the GitHub MCP server has no GitHub authorization.
3. Branch. `git branch --show-current` must not print `main`. If it does, run `git checkout -b <branch>` before you commit.
4. Push. Run `git push -u origin <branch>`. Then run `git ls-remote origin refs/heads/<branch>`. The hash must equal `git rev-parse <branch>`. Do not compare with `HEAD`: the checkout can move to another branch. A PR for an unpushed branch always fails.
5. Duplicate check. Call `mcp__github__list_pull_requests` with `owner` `raghav19`, `repo` `engineersdaybook`, `head` `raghav19:<branch>` and `state` `open`. If a PR exists, call `mcp__github__update_pull_request` with its `pullNumber`. Do not create a second PR.
6. Images. A PR body shows an image only as an SVG. Never embed a `.png`. Commit and push the `.svg` in step 4, before you create the PR. Link it with the absolute URL `https://github.com/raghav19/engineersdaybook/blob/<sha>/<path>.svg?raw=true`, where `<sha>` is the output of `git rev-parse <branch>`. Write it as `![<alt text>](<url>)`. A relative path does not render in a PR body, and a branch-name URL breaks when the branch is deleted. If an image has no SVG (a screenshot), do not embed it. Paste the text output instead.
7. Create. Call `mcp__github__create_pull_request` with `owner` `raghav19`, `repo` `engineersdaybook`, `base` `main`, `head` `<branch>`, `title` and `body`. Write the body text with the `pr` skill.
8. Report. Give the `html_url` that `mcp__github__create_pull_request` returned. If it returned no `html_url`, the PR does not exist.
