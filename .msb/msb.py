#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = ["ruamel.yaml==0.19.1"]
# ///
"""The steps of the msb sandbox recipes: msb.py <step>

The justfile has the recipes and the order of the steps. This file has the steps that need Python. Exit 1 means a wrong setup or a failed step.
The justfile exports MSB_NAME and MSB_WORKSPACE. It also puts the git values that sandbox.yaml names in the environment.
Run msb.py with `just msb <recipe>`. The justfile does the small checks (the tools on the PATH, the SSH key).

vscode-settings  merge the settings that Remote-SSH needs into the VS Code user settings file. Your other settings stay.
github-login     log in to GitHub with the GitHub App (web flow). The tokens go to a file with mode 600.
                 The recipe runs this step under `bws run`, which gives it the client secret.
ensure-vm        make or start the VM, then run sandbox-boot in it. If the VM has another configuration, stop.
                 The recipe runs this step under `bws run`, so the Bitwarden secrets are in its environment.
allow-host       add one host to network.allow in sandbox.yaml. The comments and the layout of the file stay.
"""

import argparse
import hashlib
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path
from typing import NoReturn

from ruamel.yaml import YAML  # ty: ignore[unresolved-import] - PEP 723 dependency, not in the environment of the hook
from ruamel.yaml.scalarstring import DoubleQuotedScalarString  # ty: ignore[unresolved-import] - PEP 723 dependency, not in the environment of the hook

MSB_DIR = Path(__file__).resolve().parent
CONFIG = MSB_DIR / "sandbox.yaml"
# The GitHub App of this repository. The client ID is public. The client secret is the Bitwarden key GITHUB_APP_CLIENT_SECRET.
# You installed the app on this repository only, with the permissions contents, issues and pull requests. So the token cannot do more.
# The access token lasts 8 hours. The refresh token lasts about 6 months, and each refresh gives a new one.
# The tokens go in a file on the host (mode 600), because the Bitwarden machine account cannot write.
GITHUB_CLIENT_ID = "Iv23liVvjK9IHk8lWmIh"
GITHUB_CALLBACK_PORT = 8765  # the callback address of the app is http://127.0.0.1:8765/callback
GITHUB_TOKEN_FILE = Path.home() / ".config" / "msb" / "github-app.json"
LOGIN_TIMEOUT = 300  # seconds that `github-login` waits for your approval
# The ports of the host that the VM can reach, as host.microsandbox.internal:<port>. sandbox.yaml cannot express a rule for a port.
# So msb.py gives msb one `--net-rule allow@host:tcp:<port>` for each port. The services are in the kind cluster (the SPIRE agent and kubectl need them).
HOST_PORTS = {
    6444: "kind API server",
    18081: "SPIRE server",
    19090: "Flux Operator web UI",
}
# The VS Code settings that Remote-SSH needs. `vscode-settings` merges them into your user settings. Your other settings stay.
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
# --- Helpers. Their names start with _. Only the functions below call them. A helper stands above the code that calls it. ---


def _die(message: str) -> NoReturn:
    """Print `msb: <message>` on stderr and exit with 1. Every failed step ends here."""
    print(f"msb: {message}", file=sys.stderr)
    sys.exit(1)


def _fingerprint() -> str:
    """Return the fingerprint of the VM: a hash of sandbox.yaml (it pins the image), the host values and the host ports. `ensure-vm` calls this.

    The justfile puts the host values in the environment (SANDBOX_GIT_DIR, SANDBOX_BRANCH, GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL).
    The tokens and the branch are not in the fingerprint.
    """
    parts = [
        CONFIG.read_text(),
        os.environ["SANDBOX_GIT_DIR"],
        os.environ["GIT_AUTHOR_NAME"],
        os.environ["GIT_AUTHOR_EMAIL"],
        str(HOST_PORTS),
    ]
    return hashlib.sha256("\n".join(parts).encode()).hexdigest()[:16]


def _github_exchange(**data: str) -> str:
    """Send `data` and the client credentials of the GitHub App to GitHub. Save the access token that comes back. Return it.

    The client secret is the Bitwarden key GITHUB_APP_CLIENT_SECRET. `bws run` puts it in the environment.
    The token file has mode 600. It holds the access token only. The app does not expire user tokens, so there is no refresh token.
    """
    secret = os.environ.get("GITHUB_APP_CLIENT_SECRET") or _die(
        "GITHUB_APP_CLIENT_SECRET is not set. Run this through `just msb <recipe>`."
    )
    body = urllib.parse.urlencode({"client_id": GITHUB_CLIENT_ID, "client_secret": secret, **data}).encode()
    request = urllib.request.Request("https://github.com/login/oauth/access_token", data=body, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        reply = json.load(response)
    if "access_token" not in reply:
        _die(f"GitHub refused the request ({reply.get('error')}). Run: just msb github-login")
    saved = {"access_token": reply["access_token"]}
    GITHUB_TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(GITHUB_TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as file:
        json.dump(saved, file)
    return saved["access_token"]


def _github_callback() -> dict[str, list[str]]:
    """Wait for GitHub to send the browser to the callback address of the app. Return the query of that request.

    The address is http://127.0.0.1:GITHUB_CALLBACK_PORT/callback?code=...&state=... A plain socket is enough.
    Read the first line of the request, answer "200" and close. Ignore a request without a code (the icon of the page, or a connection that sends nothing).
    Return an empty dict if no request with a code comes in LOGIN_TIMEOUT seconds.
    """
    body = b"You can close this tab."
    answer = b"HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % (len(body), body)
    deadline = time.time() + LOGIN_TIMEOUT
    with socket.create_server(("127.0.0.1", GITHUB_CALLBACK_PORT)) as server:
        while (left := deadline - time.time()) > 0:
            server.settimeout(left)
            try:
                connection, _ = server.accept()
            except TimeoutError:
                break
            with connection:
                connection.settimeout(5)
                try:
                    target = connection.recv(4096).split(b" ")[1].decode()
                except (TimeoutError, IndexError):
                    continue
                connection.sendall(answer)
            query = urllib.parse.parse_qs(urllib.parse.urlparse(target).query)
            if "code" in query:
                return query
    return {}


# --- Steps. One function for each step of main(), in the order of the cases there. ---


def vscode_settings(path: Path) -> None:
    """Merge VSCODE_SETTINGS into the VS Code user settings file `path`. Your other settings stay. The values of VSCODE_SETTINGS win.

    A missing file starts as an empty one. New VS Code windows use the new values.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        current = json.loads(path.read_text()) if path.is_file() else {}
    except json.JSONDecodeError as error:
        _die(
            f"could not read {path} ({error}). VS Code accepts comments there. This step does not. Remove the comments. Then run setup again."
        )
    path.write_text(json.dumps(current | VSCODE_SETTINGS, indent=2) + "\n")
    print(f"The VS Code settings are in {path}. New VS Code windows use them.")


def github_login() -> None:
    """Log in to GitHub with the web flow of the GitHub App (`just msb github-login`). It writes the token file.

    1. Print the address of the approval page and open it in the browser. You approve the app.
    2. GitHub sends the browser to a port of this host (the callback address of the app) with a one-time code.
       _github_callback waits for it. The random `state` value must come back the same. If it does not, the answer is not from GitHub.
    3. Send the code and the client secret to GitHub. Save the token (_github_exchange). You copy it to Bitwarden.
    """
    state = secrets.token_urlsafe(16)
    redirect = f"http://127.0.0.1:{GITHUB_CALLBACK_PORT}/callback"
    query = urllib.parse.urlencode({"client_id": GITHUB_CLIENT_ID, "redirect_uri": redirect, "state": state})
    print(f"Approve the app in your browser. If it does not open, open this address:\nhttps://github.com/login/oauth/authorize?{query}")
    webbrowser.open(f"https://github.com/login/oauth/authorize?{query}")
    got = _github_callback()
    if got.get("state") != [state]:
        _die("there was no valid approval in time. Run: just msb github-login")
    _github_exchange(code=got["code"][0], redirect_uri=redirect)
    print(f"GitHub login saved in {GITHUB_TOKEN_FILE} (mode 600).")
    print("Copy the access token to the Bitwarden key GH_TOKEN. Then delete the file. The VM gets the token from Bitwarden.")


def ensure_vm() -> None:
    """Make the VM, or start the VM that exists. Then run sandbox-boot in it. The recipe runs this step under `bws run`.

    msb keeps the fingerprint (_fingerprint) in the label `config-sha` of the VM.
    1. A VM exists with another fingerprint: stop. If you remove the VM, its clone goes too, so you decide.
    2. No VM runs: `msb run -d` makes the VM. If a stopped VM exists, msb starts it, warns, and ignores the flags.
       msb reads the secrets of sandbox.yaml from the environment (GH_TOKEN, CLAUDE_CODE_OAUTH_TOKEN and the other Bitwarden keys).
       A running VM does not read a changed secret. To change a token, stop the VM (`msb stop`) and run this step again.
    Then run sandbox-boot in the VM. Its steps do nothing for work that exists, so this is safe at each run.
    The next run fixes a VM that stopped, a boot that failed and a Headroom that stopped.
    """
    name = os.environ["MSB_NAME"]
    wanted = _fingerprint()

    found = subprocess.run(["msb", "inspect", name, "--format", "json"], capture_output=True, text=True, check=False, cwd=MSB_DIR)
    # Only "sandbox not found" means that no VM exists. Stop on any other error.
    if found.returncode != 0 and "sandbox not found" not in found.stderr:
        _die(f"`msb inspect {name}` failed: {found.stderr.strip()[:300]}")
    vm = json.loads(found.stdout) if found.returncode == 0 else None
    if vm and vm["config"]["labels"].get("config-sha") != wanted:
        # msb fixes the config of a VM when it makes the VM. If you remove the VM, you remove its clone, so you decide.
        print(f"msb: {name} does not match the configuration now. sandbox.yaml or a host value changed.", file=sys.stderr)
        _die("push any work in it (just msb shell). Then run: just msb rm && just msb run")
    if not vm or vm["status"].lower() != "running":
        port_rules = [arg for port in HOST_PORTS for arg in ("--net-rule", f"allow@host:tcp:{port}")]
        done = subprocess.run(
            ["msb", "run", "-d", "--name", name, "--conf", str(CONFIG), "--label", f"config-sha={wanted}", *port_rules],
            check=False,
        )
        if done.returncode != 0:
            _die("msb could not make or start the VM (its message is above).")
    # The VM has no command of its own. So each run does the work of sandbox-boot here, for a new VM and for an old VM.
    # stdin is /dev/null. With your terminal as stdin, msb 0.7.10 does not return after the script ends, and VS Code never opens.
    done = subprocess.run(["msb", "exec", name, "--", "/usr/local/bin/sandbox-boot"], stdin=subprocess.DEVNULL, check=False)
    if done.returncode != 0:
        _die(
            "sandbox-boot failed (its message is above). If the cause is in sandbox.yaml or a host value, make a new VM: just msb rm && just msb run"
        )


def allow_host(host: str) -> None:
    """Add `host` to network.allow in sandbox.yaml. The comments, the quotes and the order of the file stay as they are.

    A host is a name such as api.example.com, or a wildcard such as *.example.com. If the list has the host already, the file does not change.
    """
    if not re.fullmatch(r"(\*\.)?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?", host):
        _die(f"{host!r} is not a host name.")
    yaml = YAML()
    yaml.preserve_quotes = True
    # Keep the layout of the file: a key is 2 spaces in, and the dash of a list item is 2 spaces further in.
    yaml.indent(mapping=2, sequence=4, offset=2)
    config = yaml.load(CONFIG)
    allow = config["network"]["allow"]
    if host in allow:
        print(f"{host} is in network.allow already.")
        return
    # The file quotes the wildcards and nothing else.
    allow.append(DoubleQuotedScalarString(host) if host.startswith("*") else host)
    yaml.dump(config, CONFIG)
    print(f"{host} is now in network.allow.")


def main() -> None:
    """Read the step from the command line and call its function. The steps have the same order here, in the module docstring and in this file."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    steps.add_parser("vscode-settings").add_argument("file", type=Path)
    for step in ("github-login", "ensure-vm"):
        steps.add_parser(step)
    steps.add_parser("allow-host").add_argument("host")
    args = parser.parse_args()
    match args.step:
        case "vscode-settings":
            vscode_settings(args.file)
        case "github-login":
            github_login()
        case "ensure-vm":
            ensure_vm()
        case "allow-host":
            allow_host(args.host)


if __name__ == "__main__":
    main()
