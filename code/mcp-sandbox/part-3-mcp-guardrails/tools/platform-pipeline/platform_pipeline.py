"""platform-pipeline: run a recipe of every component of platform/, one after the other. The recipes of platform/justfile call it.

usage: platform_pipeline.py package | diff [--sha7 T] [--run-url U] [--limit N] | publish

Run it in the root of part 3: the recipes of platform/justfile do that. A component is a folder of platform/ that has a flux/stack.yaml.

package   just <component>/package-artifact for each component
diff      just <component>/diff for each component. A diff with a line that starts with @@ is a change
publish   just <component>/publish-artifact for each changed component (the ones in out/manifest-diff/changed.json)

A failed component does not stop the others. The exit code is 1 when one or more components failed.
The ::group:: lines fold the log of each component in GitHub Actions. On a terminal they are plain text.

Output  diff writes to out/manifest-diff/ (the folder is not in git):
        changed.json   the JSON array of the changed components, publish reads it
        report.md      the comment text for a pull request (TEMPLATE below, Jinja). A text over --limit characters becomes a note with --run-url.
                       No change: no file
        It also appends the full text (no limit) to $GITHUB_STEP_SUMMARY when that variable is set.
"""

import json
import os
import subprocess
from pathlib import Path
from typing import Annotated

import typer
from jinja2 import Environment, StrictUndefined

# The text of the pull request comment. A limit of 0 means no limit (the job summary)
TEMPLATE = """\
{% set body %}
{% for name, diff in diffs.items() %}

<details><summary>{{ name }}</summary>

````diff
{{ diff.rstrip("\\n") }}
````

</details>

{% endfor %}
{% endset %}
## Rendered manifest diff (commit {{ sha7 }})
{% if limit | int > 0 and body | length > limit | int %}

> [!NOTE]
> The diff is larger than {{ limit }} characters. A comment cannot show it. See the full diff: {{ run_url }}
{% else %}
{{ body }}
{% endif %}
"""

OUT = Path("out") / "manifest-diff"

# No rich: plain help and plain tracebacks, so typer never imports rich and the build leaves it out (--exclude-module in tools.just)
app = typer.Typer(add_completion=False, rich_markup_mode=None, pretty_exceptions_enable=False)


def run(*command: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=False, stdout=subprocess.PIPE, text=True)


def components() -> list[str]:
    """The folders of platform/ that Flux delivers: the ones with a flux/stack.yaml."""
    found = sorted(stack.parents[1].as_posix() for stack in Path("platform").glob("**/flux/stack.yaml"))
    if not found:
        raise typer.BadParameter("no component in platform/: run it in the root of part 3")
    return found


def run_each(recipe: str, names: list[str]) -> tuple[dict[str, str], list[str]]:
    """Run `just <component>/<recipe>` for each component. Return the output of each success and the names of the failures."""
    outputs: dict[str, str] = {}
    failed: list[str] = []
    for name in names:
        print(f"::group::{name}", flush=True)
        done = run("just", f"{name}/{recipe}")
        print(done.stdout, end="", flush=True)
        print("::endgroup::", flush=True)
        if done.returncode:
            failed.append(name)
        else:
            outputs[name] = done.stdout
    if failed:
        print(f"::error::{recipe} failed for: {', '.join(failed)}", flush=True)
    return outputs, failed


def render(diffs: dict[str, str], sha7: str, run_url: str, limit: int) -> str:
    env = Environment(undefined=StrictUndefined, keep_trailing_newline=True, trim_blocks=True, lstrip_blocks=True)
    return env.from_string(TEMPLATE).render(diffs=diffs, sha7=sha7, run_url=run_url, limit=limit)


@app.command()
def package() -> None:
    """just <component>/package-artifact for each component."""
    _, failed = run_each("package-artifact", components())
    raise typer.Exit(len(failed) > 0)


@app.command()
def diff(
    sha7: Annotated[str, typer.Option(help="The short commit hash")] = "",
    run_url: Annotated[str, typer.Option(help="The link to this run")] = "",
    limit: Annotated[int, typer.Option(help="The size of a comment, at most")] = 60000,
) -> None:
    """just <component>/diff for each component; write changed.json and report.md."""
    sha7 = sha7 or run("git", "rev-parse", "--short=7", "HEAD").stdout.strip()
    outputs, failed = run_each("diff", components())
    diffs = {name: text for name, text in outputs.items() if any(line.startswith("@@") for line in text.splitlines())}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "changed.json").write_text(json.dumps(list(diffs)))
    (OUT / "report.md").unlink(missing_ok=True)
    if diffs:
        (OUT / "report.md").write_text(render(diffs, sha7, run_url, limit))
        if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(summary, "a") as file:
                file.write(render(diffs, sha7, run_url, 0))
    raise typer.Exit(len(failed) > 0)


@app.command()
def publish() -> None:
    """just <component>/publish-artifact for each changed component."""
    changed = OUT / "changed.json"
    _, failed = run_each("publish-artifact", json.loads(changed.read_text()) if changed.exists() else [])
    raise typer.Exit(len(failed) > 0)


if __name__ == "__main__":
    app()
