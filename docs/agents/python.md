# Python

- Give every parameter and every return value a type hint. ruff rule `ANN` reports a missing hint. ty reports a wrong hint.
- Before you finish, run `ruff check`, `ruff format --check` and `ty check` on each Python file you changed. Fix every finding.
- Do not add `# noqa` or `# type: ignore` without a reason in the same comment.
- A script is a Python file that a recipe or a person runs. Start it with `#!/usr/bin/env -S uv run --script` and a PEP 723 block (`requires-python` and `dependencies`). Pin each dependency to an exact version.
- A tool is a build function in `tools/`. Build it as one PyInstaller binary with the `build` recipe of `tools/tools.just`. Copy the `pyproject.toml` of a sibling tool. Do not write other PyInstaller flags.
- To make a binary smaller, add `--exclude-module` to `flags` in `tools/tools.just`. Measure the size before and after.
- A service that runs in a container (`platform/ext-mcp`) is not a script and not a tool. Keep its Dockerfile.
- The reasons for each pin are in `docs/research/typer-ty-tools.md`.
