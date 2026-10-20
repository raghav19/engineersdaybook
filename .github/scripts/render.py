# /// script
# requires-python = ">=3.10"
# dependencies = ["jinja2==3.1.6", "typer==0.27.3"]
# ///
"""Render a Jinja template with values from the command line.

  render.py TEMPLATE [--var NAME=VALUE]... [--file NAME=PATH]... [--glob NAME=PATTERN]... [--out FILE]

--var is a value. --file is the text of a file. --glob is the list of the texts of the files that match. Without --out the result goes to the standard output.
Run it with: uv run --locked --script .github/scripts/render.py ... (the dependencies are locked in render.py.lock).
"""

import glob as globber
from pathlib import Path
from typing import Annotated

import typer
from jinja2 import Environment, FileSystemLoader, StrictUndefined


def pairs(items: list[str] | None) -> list[tuple[str, str]]:
    return [tuple(item.split("=", 1)) for item in items or []]


def main(
    template: Annotated[Path, typer.Argument(help="The Jinja template file")],
    var: Annotated[list[str] | None, typer.Option(help="NAME=VALUE")] = None,
    file: Annotated[
        list[str] | None, typer.Option(help="NAME=PATH: NAME is the text of the file")
    ] = None,
    glob: Annotated[
        list[str] | None,
        typer.Option(help="NAME=PATTERN: NAME is the list of the texts of the files"),
    ] = None,
    out: Annotated[
        Path | None, typer.Option(help="Write to this file, not to the standard output")
    ] = None,
) -> None:
    values: dict[str, object] = dict(pairs(var))
    values |= {name: Path(path).read_text().rstrip("\n") for name, path in pairs(file)}
    values |= {
        name: [Path(p).read_text() for p in sorted(globber.glob(pattern))]
        for name, pattern in pairs(glob)
    }
    env = Environment(
        loader=FileSystemLoader(template.parent),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        trim_blocks=True,
        lstrip_blocks=True,
    )
    text = env.get_template(template.name).render(**values)
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text)
    else:
        print(text, end="")


typer.run(main)
