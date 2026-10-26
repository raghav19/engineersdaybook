# Python rules for scripts and tools

Question: How can AGENTS.md require type hints, ruff, ty, uv scripts and small PyInstaller binaries, with the least change to the repo?

Source: the repo at `d23ab0c`, ruff 0.17.0, ty 0.0.85, uv 0.13, PyInstaller 6.22.3. Research date: 2026-10-24.

Evidence tags: **[repo]** means the claim comes from a file in this repo or from a measurement in the sandbox VM. **[primary]** means the claim comes from the project that owns the tool.

## Verdict

The repo already follows these rules for the four build functions in `tools/`. Only the rule text and three small gaps were missing.

1. AGENTS.md section 9 states the rules.
2. `spire.py` is now a uv script (PEP 723 header). It has no dependency.
3. `tests/test_rules.py` has the missing `-> None` hints.
4. ty runs from `prek.toml` on every Python file outside `tools/`. A `ty.toml` in the repo root sets it.

## Findings

| Claim | Source |
|---|---|
| The build recipe of `tools/` runs `ruff check`, `ruff format --check` and `ty check`, then PyInstaller. | [repo] `tools/tools.just`, recipe `build` |
| The PyInstaller flags are `--onefile --strip` and three `--exclude-module`. Python is pinned to `3.13.15` and the hash seed to `1`. | [repo] `tools/tools.just` |
| `spire.py` had no ANN error. `tests/test_rules.py` had 5 (`def test_x(self):` without `-> None`). | [repo] `ruff check --select ANN`, measured |
| ty was not installed in the sandbox. mise has the backend `aqua:astral-sh/ty`, and 0.0.85 is available. | [repo] `mise registry`, `mise ls-remote ty` |
| ty finds a wrong return hint (`invalid-return-type`) and passes `spire.py` and `ext-mcp/`. | [repo] measured with ty 0.0.85 |
| `tools/` ignore the root `ty.toml`, because their build runs ty with `--project` and their own `pyproject.toml`. They need `types-pyyaml`, which the hook does not have. The hook excludes `/tools/`. | [repo] `tools/*/pyproject.toml`, `prek.toml` |
| `uv run --script` reads the PEP 723 block, and `#!/usr/bin/env -S uv run --script` makes the file executable. `just spire-enroll` and `sbxenv.yaml` call the file by path and need no change. | [repo] `.sbx/agent/agent.just`, `.sbx/sbxenv.yaml`, [primary] uv documentation, "Running scripts" |
| `spire.py` ran through `uv run --script` in the sandbox and stopped at the `SANDBOX_GITHUB_ID` check. | [repo] measured |

## Not added

- **UPX.** It needs an extra tool, and a packed binary breaks the stable sha256 tag in `tools.just`.
- **`--optimize 2`.** It could make the binary smaller. No file in `tools/` uses `assert`. It changes the binary, so measure it before you add it.

## Gaps

- The first run of `spire.py` on the host can download Python 3.13 if uv has none. A host without network access fails there.
- `ext-mcp` is a container service. AGENTS.md leaves it out of the script and tool rules.
- The `ty` pin in `mise.toml` and `tools.toml` is `0.0.91`, as in `tools/`. Change all three together.
