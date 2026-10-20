# /// script
# requires-python = ">=3.10"
# dependencies = ["jinja2==3.1.6"]
# ///
"""Build the pull request comment of the manifest-diff workflow from the Jinja templates in .github/templates/.

  manifest_diff.py collect NAME DIFF_FILE OUT_DIR           when DIFF_FILE has a diff: keep it in OUT_DIR and add it to the job summary
  manifest_diff.py comment COLLECTED_DIR REPORT_FILE        write the comment from the diffs in COLLECTED_DIR to REPORT_FILE

NAME is the component. GITHUB_OUTPUT and GITHUB_STEP_SUMMARY are optional, so the script also runs on a laptop.
Run it with: uv run --locked --script .github/scripts/manifest_diff.py ... (the dependency is locked in manifest_diff.py.lock).
"""

import argparse
import json
import os
import re
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

LIMIT = int(os.environ.get("LIMIT", "60000"))
env = Environment(
    loader=FileSystemLoader(Path(__file__).resolve().parent.parent / "templates"),
    undefined=StrictUndefined,
    keep_trailing_newline=True,
    trim_blocks=True,
    lstrip_blocks=True,
)


def append(env_var: str, text: str) -> None:
    if path := os.environ.get(env_var):
        with open(path, "a") as f:
            f.write(text)


def collect(name: str, diff_file: str, out_dir: str) -> None:
    diff = Path(diff_file).read_text().rstrip("\n")
    if not re.search(r"^@@", diff, re.MULTILINE):
        return
    component = {"name": name, "diff": diff}
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / (name.replace("/", "-") + ".json")).write_text(json.dumps(component))
    append(
        "GITHUB_STEP_SUMMARY",
        env.get_template("manifest-diff-section.md.j2").render(component=component),
    )
    append("GITHUB_OUTPUT", "changed=true\n")


def comment(collected_dir: str, report_file: str) -> None:
    components = [
        json.loads(f.read_text()) for f in sorted(Path(collected_dir).glob("*.json"))
    ]
    if not components:
        return
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    context = {
        "sha7": os.environ["HEAD_SHA"][:7],
        "components": components,
        "limit": LIMIT,
        "run_url": run_url,
    }
    template = env.get_template("manifest-diff-comment.md.j2")
    report = template.render(**context, too_big=False)
    if len(report.encode()) > LIMIT:
        report = template.render(**context, too_big=True)
    Path(report_file).write_text(report)
    append("GITHUB_OUTPUT", "post=true\n")


parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest="command", required=True)
p = sub.add_parser("collect")
p.add_argument("name")
p.add_argument("diff_file")
p.add_argument("out_dir")
p = sub.add_parser("comment")
p.add_argument("collected_dir")
p.add_argument("report_file")
args = parser.parse_args()
if args.command == "collect":
    collect(args.name, args.diff_file, args.out_dir)
else:
    comment(args.collected_dir, args.report_file)
