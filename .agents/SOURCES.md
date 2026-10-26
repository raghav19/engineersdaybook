# Agent skills

These skills are copies of upstream skills, committed here so that every environment (the host, sbx and msb) has the same skills at the same version. Nobody edits them here. Claude Code reads them through the link `.claude/skills` to `.agents/skills`.

An upstream change reaches this repository only in a pull request, so you read the diff. The licence of each upstream repository is in `licenses/`.

The prek hooks skip `.agents/skills/`: they must not rewrite the copies.

## Update a skill

`<upstream>`, `<path>` and `<skill>` are the values in the table below. Do this on a new branch.

```shell
# 1. Get the upstream. To pin an older version, run `git -C /tmp/upstream checkout <commit>` after the clone.
git clone https://github.com/<upstream> /tmp/upstream

# 2. Replace the copy. --delete removes the files that upstream removed.
rsync -a --delete --exclude=.git /tmp/upstream/<path>/ .agents/skills/<skill>/

# 3. Put the new commit in the table (git -C /tmp/upstream rev-parse --short=12 HEAD), read the diff, commit, open a pull request.
```

- The upstream is not trusted. Read the diff before you commit. Do not run its scripts.
- `asd-ste100` is the root of its upstream (path `.`). Add `--exclude=README.md --exclude=LICENSE --exclude=.claude-plugin` to the `rsync` command.
- A new skill: copy it the same way and add a row. A removed skill: delete its folder and its row. For `mattpocock/skills`, the `skills` list in its `.claude-plugin/plugin.json` shows which skills are published.
- If the licence file of the upstream changed, copy it to `licenses/` too.

| Skill | Upstream | Path in upstream | Commit |
|---|---|---|---|
| `asd-ste100` | [danyuchn/asd-ste100-skill](https://github.com/danyuchn/asd-ste100-skill) | `.` | `8da6b6340aa2` |
| `ask-matt` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/ask-matt` | `5beb35b040e3` |
| `aws-auth` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) | `plugins/aws-core/skills/aws-auth` | `bcec7a6182a3` |
| `aws-compute` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) | `plugins/aws-core/skills/aws-compute` | `bcec7a6182a3` |
| `aws-containers` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) | `plugins/aws-core/skills/aws-containers` | `bcec7a6182a3` |
| `aws-iam` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) | `plugins/aws-core/skills/aws-iam` | `bcec7a6182a3` |
| `aws-networking` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) | `plugins/aws-core/skills/aws-networking` | `bcec7a6182a3` |
| `aws-security` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) | `plugins/aws-core/skills/aws-security` | `bcec7a6182a3` |
| `aws-storage` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) | `plugins/aws-core/skills/aws-storage` | `bcec7a6182a3` |
| `codebase-design` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/codebase-design` | `5beb35b040e3` |
| `code-intelligence` | [antonbabenko/agent-plugins](https://github.com/antonbabenko/agent-plugins) | `plugins/code-intelligence/skills/code-intelligence` | `4a148f86223a` |
| `code-review` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/code-review` | `5beb35b040e3` |
| `diagnosing-bugs` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/diagnosing-bugs` | `5beb35b040e3` |
| `domain-modeling` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/domain-modeling` | `5beb35b040e3` |
| `gitops-cluster-debug` | [fluxcd/agent-skills](https://github.com/fluxcd/agent-skills) | `skills/gitops-cluster-debug` | `47af543da6ce` |
| `gitops-knowledge` | [fluxcd/agent-skills](https://github.com/fluxcd/agent-skills) | `skills/gitops-knowledge` | `47af543da6ce` |
| `gitops-repo-audit` | [fluxcd/agent-skills](https://github.com/fluxcd/agent-skills) | `skills/gitops-repo-audit` | `47af543da6ce` |
| `grilling` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/productivity/grilling` | `5beb35b040e3` |
| `grill-me` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/productivity/grill-me` | `5beb35b040e3` |
| `grill-with-docs` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/grill-with-docs` | `5beb35b040e3` |
| `handoff` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/productivity/handoff` | `5beb35b040e3` |
| `implement` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/implement` | `5beb35b040e3` |
| `implement-spec` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/implement-spec` | `5beb35b040e3` |
| `improve-codebase-architecture` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/improve-codebase-architecture` | `5beb35b040e3` |
| `pr` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/pr` | `5beb35b040e3` |
| `prototype` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/prototype` | `5beb35b040e3` |
| `research` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/research` | `5beb35b040e3` |
| `retro` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/retro` | `5beb35b040e3` |
| `setup-matt-pocock-skills` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/setup-matt-pocock-skills` | `5beb35b040e3` |
| `tdd` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/tdd` | `5beb35b040e3` |
| `teach` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/productivity/teach` | `5beb35b040e3` |
| `terragrunt-skill` | [jfr992/terragrunt-skill](https://github.com/jfr992/terragrunt-skill) | `skills/terragrunt-skill` | `fbd333605880` |
| `to-questionnaire` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/productivity/to-questionnaire` | `5beb35b040e3` |
| `to-spec` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/to-spec` | `5beb35b040e3` |
| `to-tickets` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/to-tickets` | `5beb35b040e3` |
| `triage` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/triage` | `5beb35b040e3` |
| `wait-what` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/productivity/wait-what` | `5beb35b040e3` |
| `wayfinder` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/wayfinder` | `5beb35b040e3` |
| `wizard` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/engineering/wizard` | `5beb35b040e3` |
| `writing-for-agents` | [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/productivity/writing-for-agents` | `5beb35b040e3` |
