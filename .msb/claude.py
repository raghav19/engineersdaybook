#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The Claude login of the sandbox: claude.py <step>

status  say if the Claude login of this host exists and how long its access token lasts. It prints no token

The module also defines claude_token(), which vm.py calls. It returns the access token of the login that `claude` keeps on this host (Linux:
~/.claude/.credentials.json). The VM does not log in: it has a placeholder, and the host replaces it on the network, as sbx does.
This script only reads the file. It never refreshes the token: `claude` on the host does that and rotates the refresh token, and a second
refresh from here would make the refresh token of `claude` useless.
"""

import argparse
import json
import os
import time
from pathlib import Path
from typing import Any

from common import die

CREDENTIALS = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / ".credentials.json"
REFRESH_MARGIN = 1800  # seconds. A token that expires in less time is refused: the VM would soon get 401


def claude_login() -> dict[str, Any]:
    """Return the login of the file `~/.claude/.credentials.json` (the key `claudeAiOauth`). Stop if there is none, or if it is not a subscription login."""
    if not CREDENTIALS.is_file():
        die(f"there is no Claude login on this host ({CREDENTIALS}). Run `claude` and sign in, then run this again.")
    if CREDENTIALS.stat().st_mode & 0o077:
        die(f"{CREDENTIALS} must have mode 600.")
    login = json.loads(CREDENTIALS.read_text()).get("claudeAiOauth")
    if not login or "accessToken" not in login:
        die(
            "the Claude login of this host is not a subscription login (no claudeAiOauth). Run `claude` and sign in with your subscription."
        )
    return login


def claude_token() -> str:
    """Return the access token of the Claude login of this host. `ensure-vm` calls this.

    Stop if the token expires in less than REFRESH_MARGIN seconds. Do not refresh it here (see the top of this file):
    the message tells you to start `claude` on the host, which refreshes the login.
    """
    login = claude_login()
    if login["expiresAt"] / 1000 - time.time() < REFRESH_MARGIN:
        die(
            "the Claude login of this host expires soon or is no longer valid. Start `claude` on the host to refresh it, then run this again."
        )
    return login["accessToken"]


def claude_status() -> None:
    """Say if the login exists, its plan, and how many hours the access token lasts. Print no token."""
    login = claude_login()
    hours = (login["expiresAt"] / 1000 - time.time()) / 3600
    print(f"Claude login of this host: plan {login.get('subscriptionType', 'unknown')}, the access token lasts {hours:.1f} more hours.")


def main() -> None:
    """Read the step from the command line and call its function."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    steps.add_parser("status")
    match parser.parse_args().step:
        case "status":
            claude_status()


if __name__ == "__main__":
    main()
