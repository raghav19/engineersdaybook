# typer and ty for the build functions of part 3

Question: Can the build functions in `code/mcp-sandbox/part-3-mcp-guardrails/tools/` use typer for the CLI and ty for type checks, without a change to how the recipes call them?

Source: typer 0.27.3 (installed source), ty 0.0.85 docs, PyPI, ruff 0.17.0. Research date: 2026-10-21.

Evidence tags: **[repo]** means the claim comes from a file in this repo or from a measurement in the sandbox VM. **[primary]** means the claim comes from the project that owns the tool (its source, its docs, or its PyPI page).

## Verdict

Yes. All four tools now use typer, and every function has type hints. The build fails when a hint is missing (ruff `ANN`) or wrong (ty).

1. The callers do not change. A typer app with one command makes that command the root command.
2. The outputs do not change. 66 output files of 12 runs (stdout, stderr, exit code, written files) are byte-identical before and after.
3. Each binary is 26% larger (12.5 MiB to 15.7 MiB), because typer brings rich and shellingham.

## Findings: the tools before the change

| Claim | Source |
|---|---|
| stack-composer used argparse. config-builder and value-injector read `sys.argv[1:]` directly. platform-pipeline already used typer 0.27.3 with `Annotated`. | [repo] `tools/*/*.py` at `5b5997c` |
| `ruff check --select ANN` found 37 missing hints in config-builder, 38 in value-injector, 10 in stack-composer and 0 in platform-pipeline. | [repo] measured with ruff 0.17.0 |
| The recipes call the tools with positional arguments only, and stack-composer with `--manifest` and `--cluster` before them. | [repo] `lib/workflow/package.just:44,53`, `lib/workflow/compose.just:15` |

## Findings: typer

| Claim | Source |
|---|---|
| When a `Typer` app has exactly one registered command, typer builds a single click `Command`, not a group. The CLI then has no subcommand name. | [primary] `typer/main.py:1188-1200` (0.27.3) |
| typer 0.27.3 depends on `annotated-doc`, `rich` and `shellingham` (and `colorama` on Windows only). | [primary] PyPI metadata, as locked in `tools/platform-pipeline/uv.lock:268-273` |
| `typer.Option("--manifest", ...)` sets the option name. The parameter can then have a different name (`manifest_file`). | [repo] measured: `stack-composer --help` shows `--manifest` |
| `sys.exit("message")` inside a command still prints the message on stderr and exits 1. | [repo] measured: `sc-badflag` and `sc-nocluster` runs, same stderr and exit code as the argparse version |

## Findings: ty

| Claim | Source |
|---|---|
| The latest release on 2026-10-21 is 0.0.90 (2026-10-20). 0.0.85 (2026-10-06) is the newest release that is at least two weeks old. ty is still 0.0.x. | [primary] https://pypi.org/pypi/ty/json |
| `ty check --error-on-warning` exits 1 on a warning. The config key `[tool.ty.terminal] error-on-warning = true` does the same. | [primary] https://github.com/astral-sh/ty/blob/0.0.85/docs/reference/cli.md, `docs/reference/configuration.md` (`terminal`) |
| ty checks that the hints are correct. It does not report a function that has no hints. ruff's `ANN` rules report that. | [repo] measured: a probe file gives `ANN001`/`ANN201` from ruff and `invalid-return-type` from ty |
| ty found two real errors during the change: a parameter (`entry: Path`) reassigned with a list, and `doc` reassigned with a list element in `set_at_path` and `has_path`. | [repo] `ty check` output during the change |

## Findings: PyYAML types

| Claim | Source |
|---|---|
| PyYAML ships no type information. `types-pyyaml` (typeshed) gives the types of `yaml.safe_load` and the other functions. It is used by ty only, and is not in the binary. | [primary] https://pypi.org/project/types-PyYAML/ |
| The version `6.0.12.20260906` is typeshed's format: `6.0.12` is the PyYAML API, `20260906` the stub release date (2026-09-06). | [primary] https://pypi.org/pypi/types-PyYAML/json |

## What was built

- `typer==0.27.3` in the `dependencies` of config-builder, stack-composer and value-injector.
- `ty==0.0.85` (all four) and `types-pyyaml==6.0.12.20260906` (the three YAML tools) in the `build` dependency group.
- `[tool.ruff.lint] extend-select = ["ANN"]` and `[tool.ty.terminal] error-on-warning = true` in all four `pyproject.toml`.
- `tools.just` recipe `build`: `ty check` runs after the two ruff checks.

## Gaps

- ty is 0.0.x. A later release can report new diagnostics. Read its changelog before you change the pin.
- The three binaries changed, so their sha256 tags changed. The next `just push` pushes them again.
