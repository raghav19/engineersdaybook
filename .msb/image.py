#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The published image of the sandbox: image.py <step>

tags  print the tags of the image, one for each line. Stop if dev-tools/ differs from the commit
"""

import argparse

from common import die, out


def image_tags() -> None:
    """Print the tags of the published image, one for each line. `image-publish` calls this.

    The tags are the commit, `latest` (only on main) and the git tag of the commit (if it has one).
    Stop if dev-tools/ differs from the commit, because the tag is the commit.
    """
    if out("git", "status", "--porcelain", "--", "dev-tools"):
        die("dev-tools/ differs from the commit. The tag of the image is the commit, so commit the changes first.")
    tags = [out("git", "rev-parse", "HEAD")]
    if out("git", "branch", "--show-current") == "main":
        tags.append("latest")
    if git_tag := out("git", "describe", "--exact-match", "--tags", "HEAD", default=""):
        tags.append(git_tag)
    print("\n".join(tags))


def main() -> None:
    """Read the step from the command line and call its function."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    steps.add_parser("tags")
    match parser.parse_args().step:
        case "tags":
            image_tags()


if __name__ == "__main__":
    main()
