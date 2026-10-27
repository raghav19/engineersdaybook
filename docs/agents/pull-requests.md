# Pull requests

Open a PR with `gh pr create`. Do these steps in this order. If a step fails, stop and report the exact error text. Do not go on to the next step.

1. Git identity. Run `git config user.name` and `git config user.email`. If either prints nothing, run `gh api user --jq '.login, .email'`. Then run `git config user.name "<name>"` and `git config user.email "<email>"`. If `email` is null, use `<id>+<login>@users.noreply.github.com`. Never use `--global`. Never invent a value.
2. GitHub identity. Run `gh api user --jq .login`. If it returns an error, or the login is not `raghav19`, stop. Tell the user that `gh` has no GitHub authorization (in the msb sandbox: run `just msb github-login`, then `just msb run`, on the host). Do not try `gh auth login`.
3. Branch. `git branch --show-current` must not print `main`. If it does, run `git checkout -b <branch>` before you commit.
4. Push. Run `git push -u origin <branch>`. Then run `git ls-remote origin refs/heads/<branch>`. The hash must equal `git rev-parse <branch>`. Do not compare with `HEAD`: the checkout can move to another branch. A PR for an unpushed branch always fails.
5. Duplicate check. Run `gh pr list --head <branch> --state open --json number,url`. If a PR exists, run `gh pr edit <number>` on it. Do not create a second PR.
6. Images. A PR body shows an image only as an SVG. Never embed a `.png`. Commit and push the `.svg` in step 4, before you create the PR. Link it with the absolute URL `https://github.com/raghav19/engineersdaybook/blob/<sha>/<path>.svg?raw=true`, where `<sha>` is the output of `git rev-parse <branch>`. Write it as `![<alt text>](<url>)`. A relative path does not render in a PR body, and a branch-name URL breaks when the branch is deleted. If an image has no SVG (a screenshot), do not embed it. Paste the text output instead.
7. Create. Run `gh pr create --base main --head <branch> --title "<title>" --body-file <file>`. Write the body with the `pr` skill.
8. Report. Give the URL that `gh pr create` printed. If it printed no URL, the PR does not exist.
