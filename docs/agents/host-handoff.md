# Host handoff

You run in a **clone** of this repo (`/run/sandbox/source` exists). Your edits and commits are invisible to the host until you push them.

- Before you ask the user to run any command on the host that depends on your changes, commit them and `git push` to a feature branch. Never push to `main`.
- In the same message, name the branch and the exact commit (`git rev-parse --short HEAD`). Give the host command with the checkout, e.g. `git fetch origin && git checkout <branch> && just <target>`.
- If the push fails, say so and stop. Do not ask the user to run a host command against unpushed changes.
- Host-only commands that need no repo changes (`sbx policy ...`, `sbx secret ...`, `sbx ports ...`) need no push.
