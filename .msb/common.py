"""The helpers that every script of .msb/ shares. It is a module, not a script: the scripts import it from their own folder."""

import os
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

MSB_DIR = Path(__file__).resolve().parent


def die(message: str) -> NoReturn:
    """Print `msb: <message>` on stderr and exit with 1. Every failed step ends here."""
    print(f"msb: {message}", file=sys.stderr)
    sys.exit(1)


def setting(name: str) -> str:
    """Return a value that the justfile exports (MSB_NAME, MSB_IMAGE, MSB_WORKSPACE). Stop if it is not set, which happens when you run msb.py by hand."""
    return os.environ.get(name) or die(f"{name} is not set. Run this through `just msb <recipe>`.")


def out(*cmd: str, default: str | None = None) -> str:
    """Run a command in .msb/ (inside the repo) and return its output without the final newline.

    If the command fails, return `default`. If there is no default, stop with the message of the command.
    """
    done = subprocess.run(cmd, capture_output=True, text=True, check=False, cwd=MSB_DIR)
    if done.returncode == 0:
        return done.stdout.strip()
    if default is None:
        die(f"`{' '.join(cmd)}` failed: {done.stderr.strip()}")
    return default
