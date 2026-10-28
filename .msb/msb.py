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
sync-token       give the running VM the current Claude token of the host, then restart Headroom. It does nothing if the VM has the token.
                 `just msb sync` runs this step each time `claude` on the host changes its login.
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
REFRESH_MARGIN = 1800  # seconds. GitHub: refresh a token that ends sooner. Claude: refuse it
# The GitHub App of this repository. The client ID is public. The client secret is the Bitwarden key GITHUB_APP_CLIENT_SECRET.
# You installed the app on this repository only, with the permissions contents, issues and pull requests. So the token cannot do more.
# The access token lasts 8 hours. The refresh token lasts about 6 months, and each refresh gives a new one.
# The tokens go in a file on the host (mode 600), because the Bitwarden machine account cannot write.
GITHUB_CLIENT_ID = "Iv23liVvjK9IHk8lWmIh"
GITHUB_CALLBACK_PORT = 8765  # the callback address of the app is http://127.0.0.1:8765/callback
GITHUB_TOKEN_FILE = Path.home() / ".config" / "msb" / "github-app.json"
LOGIN_TIMEOUT = 300  # seconds that `github-login` waits for your approval
CLAUDE_CREDENTIALS = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / ".credentials.json"
CLAUDE_TOKEN_SEEN = Path.home() / ".config" / "msb" / "claude-token.sha256"  # the hash of the token that `sync-token` gave the VM last
# Run in the VM as root. msb gives a new value of a secret to new connections only, so Headroom must close its old ones.
# The restart is the same as in dev-tools/sandbox-boot. Headroom starts again as the agent user.
HEADROOM_RESTART = """
pkill -u agent -f 'headroom proxy' || true
for _ in $(seq 50); do pgrep -u agent -f 'headroom proxy' >/dev/null || break; sleep 0.2; done
runuser -u agent -- env HOME=/home/agent sh -c 'setsid nohup headroom proxy --port 8787 >/tmp/headroom.log 2>&1 &'
for _ in $(seq 60); do curl -sf -o /dev/null http://127.0.0.1:8787/health && exit 0; sleep 1; done
tail -n 20 /tmp/headroom.log >&2
exit 1
"""
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
    """Send `data` and the client credentials of the GitHub App to GitHub. Save the tokens that come back. Return the access token.

    The client secret is the Bitwarden key GITHUB_APP_CLIENT_SECRET. `bws run` puts it in the environment.
    The token file has mode 600. It holds the access token, the refresh token and the time when the access token ends.
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
    saved = {
        "access_token": reply["access_token"],
        "refresh_token": reply.get("refresh_token"),
        "expires_at": time.time() + reply.get("expires_in", 10**9),
    }
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


def _github_token() -> str:
    """Return the GitHub access token from the token file. `ensure-vm` calls this.

    If the token ends in less than REFRESH_MARGIN seconds, ask GitHub for a new one with the refresh token. Save it first.
    Each refresh gives a new refresh token. Stop if there is no file. If GitHub refuses the refresh, the message says to log in again.
    """
    if not GITHUB_TOKEN_FILE.is_file():
        _die("there is no GitHub login. Run: just msb github-login")
    saved = json.loads(GITHUB_TOKEN_FILE.read_text())
    if saved["expires_at"] - time.time() > REFRESH_MARGIN:
        return saved["access_token"]
    return _github_exchange(grant_type="refresh_token", refresh_token=saved["refresh_token"])


def _claude_token() -> str:
    """Return the access token of the Claude login that `claude` keeps on this host. `ensure-vm` calls this.

    The login is the key `claudeAiOauth` in ~/.claude/.credentials.json (Linux). The VM does not log in. It has a placeholder, as sbx does.
    This function only reads the file. It never refreshes the token. `claude` on the host refreshes it and rotates the refresh token.
    A second refresh from here would make the refresh token of `claude` useless.
    Stop in three cases:
    - there is no file, or its mode is not 600
    - the login is not a subscription login
    - the token lasts less than REFRESH_MARGIN seconds
    """
    if not CLAUDE_CREDENTIALS.is_file():
        _die(f"there is no Claude login on this host ({CLAUDE_CREDENTIALS}). Run `claude` and sign in with your subscription.")
    if CLAUDE_CREDENTIALS.stat().st_mode & 0o077:
        _die(f"{CLAUDE_CREDENTIALS} must have mode 600.")
    login = json.loads(CLAUDE_CREDENTIALS.read_text()).get("claudeAiOauth")
    if not login or "accessToken" not in login:
        _die("the Claude login of this host is not a subscription login. Run `claude` and sign in with your subscription.")
    if login["expiresAt"] / 1000 - time.time() < REFRESH_MARGIN:
        _die("the Claude login of this host ends soon, or it is not valid. Start `claude` on the host to refresh it. Then run this again.")
    return login["accessToken"]


def _rotate_secret(name: str, secret: str, value: str) -> None:
    """Give the VM `name` the current `value` of `secret` with `msb modify`. The placeholder in the VM stays, and the VM does not restart.

    msb gives the new value to the connections that the VM opens afterwards. A connection that is open keeps the old value.
    """
    hosts = ",".join(YAML().load(CONFIG)["secrets"][secret]["allow"])
    done = subprocess.run(
        ["msb", "modify", name, "--secret", f"{secret}@{hosts}"],
        env=os.environ | {secret: value},
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        _die(f"msb could not give the VM the current value of {secret}: {done.stderr.strip()[:300]}")


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
    3. Send the code and the client secret to GitHub. Save the tokens (_github_exchange).
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


def ensure_vm() -> None:
    """Make the VM, or start the VM that exists. Then run sandbox-boot in it. The recipe runs this step under `bws run`.

    msb keeps the fingerprint (_fingerprint) in the label `config-sha` of the VM.
    1. A VM exists with another fingerprint: stop. If you remove the VM, its clone goes too, so you decide.
    2. No VM runs: `msb run -d` makes the VM. If a stopped VM exists, msb starts it, warns, and ignores the flags.
       msb reads the secrets of sandbox.yaml from the environment (GH_TOKEN, CLAUDE_CODE_OAUTH_TOKEN and the Bitwarden keys).
       GH_TOKEN is the GitHub App token. CLAUDE_CODE_OAUTH_TOKEN is the access token of the Claude login of this host.
    3. Give the VM the current tokens with `msb modify --secret`. It does not restart.
    Then run sandbox-boot in the VM. Its steps do nothing for work that exists, so this is safe at each run.
    The next run fixes a VM that stopped, a boot that failed and a Headroom that stopped.
    """
    name = os.environ["MSB_NAME"]
    tokens = {"GH_TOKEN": _github_token(), "CLAUDE_CODE_OAUTH_TOKEN": _claude_token()}
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
            env=os.environ | tokens,
            check=False,
        )
        if done.returncode != 0:
            _die("msb could not make or start the VM (its message is above).")
    # Give the VM the current tokens. The placeholders in the VM stay, and the VM does not restart.
    for secret, value in tokens.items():
        _rotate_secret(name, secret, value)
    # The VM has no command of its own. So each run does the work of sandbox-boot here, for a new VM and for an old VM.
    # stdin is /dev/null. With your terminal as stdin, msb 0.7.10 does not return after the script ends, and VS Code never opens.
    done = subprocess.run(["msb", "exec", name, "--", "/usr/local/bin/sandbox-boot"], stdin=subprocess.DEVNULL, check=False)
    if done.returncode != 0:
        _die(
            "sandbox-boot failed (its message is above). If the cause is in sandbox.yaml or a host value, make a new VM: just msb rm && just msb run"
        )


def sync_token() -> None:
    """Give the running VM the Claude token of the host now, then restart Headroom. Do nothing if the VM has this token already.

    `claude` on the host refreshes its login and the old access token stops working. msb gives a new value to new connections only.
    Headroom keeps its connections to api.anthropic.com open, so it keeps sending the old token. The restart closes them.
    The file CLAUDE_TOKEN_SEEN has the hash of the token that this step gave the VM last. The justfile runs this step under `watchexec`.
    """
    name = os.environ["MSB_NAME"]
    token = _claude_token()
    digest = hashlib.sha256(token.encode()).hexdigest()
    if CLAUDE_TOKEN_SEEN.is_file() and CLAUDE_TOKEN_SEEN.read_text() == digest:
        print("sync-token: the VM has this token already.")
        return
    _rotate_secret(name, "CLAUDE_CODE_OAUTH_TOKEN", token)
    done = subprocess.run(["msb", "exec", name, "--", "bash", "-c", HEADROOM_RESTART], stdin=subprocess.DEVNULL, check=False)
    if done.returncode != 0:
        _die("Headroom did not restart in the VM (its message is above). Check that the VM runs (msb ls). Run: just msb run")
    CLAUDE_TOKEN_SEEN.parent.mkdir(parents=True, exist_ok=True)
    CLAUDE_TOKEN_SEEN.write_text(digest)
    print("sync-token: the VM has the new token and Headroom restarted.")


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
    for step in ("github-login", "ensure-vm", "sync-token"):
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
        case "sync-token":
            sync_token()
        case "allow-host":
            allow_host(args.host)


if __name__ == "__main__":
    main()
