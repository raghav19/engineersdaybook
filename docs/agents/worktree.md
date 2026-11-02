# Git worktree workflow

Agents should use `enter_worktree` for isolated work. This creates a worktree at `.qwen/worktrees/<slug>` **inside** the project directory, not a sibling directory outside it.

## Why inside the project?

- Keeps all worktrees discoverable in one place (`.qwen/worktrees/`)
- Easier to clean up: `rm -rf .qwen/worktrees/` removes all agent worktrees
- Git metadata is in `.git/worktrees/` (standard git behavior)
- Avoids cluttering the parent directory with `project-name-branch` siblings

## Usage

```
enter_worktree slug=my-feature
# Work in .qwen/worktrees/my-feature
# When done, commit and push from the worktree
exit_worktree
```
