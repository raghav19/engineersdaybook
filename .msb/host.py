#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The setup of this host for the sandbox: host.py <step>

ssh-key          print the path of your SSH public key
vscode-settings  set the VS Code settings for Remote-SSH
check-host HOST  stop if HOST is not a host name
"""

import argparse
import json
import os
import re
from pathlib import Path

from common import MSB_DIR, die

VSCODE_SETTINGS = {
    "remote.SSH.configFile": str(MSB_DIR / "ssh_config"),
    "remote.SSH.defaultExtensions": [
        "astral-sh.ty",
        "charliermarsh.ruff",
        "tamasfe.even-better-toml",
        "kennylong.kubernetes-yaml-formatter",
        "yzhang.markdown-all-in-one",
        "skellock.just",
        "isontheline.vscode-sysmon",
    ],
    "remote.SSH.useExecServer": False,
    "remote.SSH.enableDynamicForwarding": False,
    "remote.SSH.enableAgentForwarding": False,
    "remote.SSH.connectTimeout": 30,
    "remote.SSH.showLoginTerminal": False,
    "remote.SSH.localServerDownload": "always",
    "update.mode": "none",
    "extensions.autoUpdate": "off",
    "extensions.autoCheckUpdates": False,
}


def ssh_key() -> None:
    """Print the path of your SSH public key. `setup` gives it to `msb ssh authorize`.

    The default is ~/.ssh/id_ed25519.pub. The variable SANDBOX_SSH_PUBKEY changes it. Stop if the file does not exist.
    """
    key = Path(os.environ.get("SANDBOX_SSH_PUBKEY", Path.home() / ".ssh" / "id_ed25519.pub"))
    if not key.is_file():
        die(f"there is no SSH public key at {key}. Make one with: ssh-keygen -t ed25519. Or set SANDBOX_SSH_PUBKEY.")
    print(key)


def vscode_settings() -> None:
    """Merge VSCODE_SETTINGS into the user settings of VS Code (~/.config/Code/User/settings.json).

    It writes the file only if a value differs, and then it says so. New VS Code windows use the new values.
    """
    path = Path.home() / ".config" / "Code" / "User" / "settings.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    current = json.loads(path.read_text()) if path.is_file() else {}
    if current | VSCODE_SETTINGS != current:
        path.write_text(json.dumps(current | VSCODE_SETTINGS, indent=2) + "\n")
        print(f"VS Code settings changed in {path}. New VS Code windows use them.")


def check_host(host: str) -> None:
    """Stop if HOST is not a valid host name: an optional `*.`, then letters, digits, dots and hyphens. `allow-host` calls this before it writes the name to sandbox.yaml."""
    if not re.fullmatch(r"(\*\.)?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?", host):
        die(f"{host} is not a host name.")


def main() -> None:
    """Read the step from the command line and call its function."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    for step in ("ssh-key", "vscode-settings"):
        steps.add_parser(step)
    steps.add_parser("check-host").add_argument("host")
    args = parser.parse_args()
    match args.step:
        case "ssh-key":
            ssh_key()
        case "vscode-settings":
            vscode_settings()
        case "check-host":
            check_host(args.host)


if __name__ == "__main__":
    main()
