#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The steps of the msb sandbox recipes: msb.py <step>

The justfile has the recipes and the order of the steps. This file has the logic of each step. Exit 1: wrong setup or a failed step.
The justfile exports MSB_NAME and MSB_IMAGE. Run msb.py through `just msb <recipe>`. The checks that bash does well (msb on the PATH, the SSH key, the name of a host, the tags of the image) and the
VS Code settings are in the justfile.

github-login     log in to GitHub with the GitHub App (web flow, with the client secret from Bitwarden). The tokens go to a file with mode 600
                 The recipe runs this step under `bws run`
ensure-vm        make the VM from sandbox.yaml if none exists. If a VM exists and is current, give it the current GitHub and Claude tokens.
                 Else stop. The recipe runs this step under `bws run`, so the Bitwarden secrets are in its environment
wait-boot        wait until sandbox-boot is ready. If it fails, print the end of the boot log
"""

import argparse
import hashlib
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path
from typing import NoReturn

MSB_DIR = Path(__file__).resolve().parent
CONFIG = MSB_DIR / "sandbox.yaml"
BOOT_TIMEOUT = 90  # seconds that `wait-boot` waits for sandbox-boot
REFRESH_MARGIN = 1800  # seconds. A token that expires in less time is refreshed (GitHub) or refused (Claude)
# The GitHub App of this repository. The client ID is public. The client secret is the Bitwarden key GITHUB_APP_CLIENT_SECRET. You installed the app on
# this repository only, with the permissions contents, issues and pull requests. So the token cannot do more. The access token lasts 8 hours. The refresh
# token lasts about 6 months, and each refresh gives a new one. So the tokens go in a file on the host (mode 600): the Bitwarden machine account cannot write.
GITHUB_CLIENT_ID = "Iv23liVvjK9IHk8lWmIh"
GITHUB_CALLBACK_PORT = 8765  # the callback address of the app is http://127.0.0.1:8765/callback
GITHUB_TOKEN_FILE = Path.home() / ".config" / "msb" / "github-app.json"
LOGIN_TIMEOUT = 300  # seconds that `github-login` waits for your approval
CLAUDE_CREDENTIALS = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / ".credentials.json"
# The ports of the host that the VM can reach, as host.microsandbox.internal:<port>. sandbox.yaml cannot express a rule for a port, so msb.py
# passes one `--net-rule allow@host:tcp:<port>` to msb for each. The services are in the kind cluster (the SPIRE agent and kubectl need them).
HOST_PORTS = {
    6444: "kind API server",
    18081: "SPIRE server",
    19090: "Flux Operator web UI",
}
# --- Helpers. They start with _ : only the functions below call them. A helper stands above the code that calls it. ---


def _die(message: str) -> NoReturn:
    """Print `msb: <message>` on stderr and exit with 1. Every failed step ends here."""
    print(f"msb: {message}", file=sys.stderr)
    sys.exit(1)


def _out(*cmd: str, default: str | None = None) -> str:
    """Run a command in .msb/ (inside the repo) and return its output without the final newline.

    If the command fails, return `default`. If there is no default, stop with the message of the command.
    """
    done = subprocess.run(cmd, capture_output=True, text=True, check=False, cwd=MSB_DIR)
    if done.returncode == 0:
        return done.stdout.strip()
    if default is None:
        _die(f"`{' '.join(cmd)}` failed: {done.stderr.strip()}")
    return default


def _image_id() -> str:
    """Return the id of the local Docker image MSB_IMAGE. Stop with a hint if the image does not exist.

    The id is part of the fingerprint of the VM, so a new image makes the VM not current.
    """
    image = os.environ["MSB_IMAGE"]
    return _out("docker", "image", "inspect", image, "--format", "{{.Id}}", default="") or _die(
        f"the image {image} does not exist. Run: just msb image-build"
    )


def _github_exchange(**data: str) -> str:
    """Send `data` and the client credentials of the GitHub App to GitHub, save the tokens that come back, and return the access token.

    The client secret is the Bitwarden key GITHUB_APP_CLIENT_SECRET, which `bws run` puts in the environment.
    The token file has mode 600. It keeps the access token, the refresh token and the time when the access token ends.
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
    """Wait for GitHub to send the browser to the callback address of the app, and return the query of that request.

    The address is http://127.0.0.1:GITHUB_CALLBACK_PORT/callback?code=...&state=... A plain socket is enough: read the first line of the
    request, answer "200" and close. Ignore a request without a code (the icon of the page, or a connection that sends nothing).
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

    If the token ends in less than REFRESH_MARGIN seconds, ask GitHub for a new one with the refresh token and save it first.
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

    The login is the key `claudeAiOauth` in ~/.claude/.credentials.json (Linux). The VM does not log in: it has a placeholder, as sbx does.
    This function only reads the file. It never refreshes the token: `claude` on the host does that and rotates the refresh token,
    and a second refresh from here would make the refresh token of `claude` useless.
    Stop in four cases:
    - there is no file, or its mode is not 600
    - it is not a subscription login
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
        _die(
            "the Claude login of this host expires soon or is no longer valid. Start `claude` on the host to refresh it, then run this again."
        )
    return login["accessToken"]


def _host_values() -> dict[str, str]:
    """Return the host values that sandbox.yaml names as ${NAME}: the git directory, the branch, and the git name and email.

    They come from git on the host. The VM clones the git directory and starts on the branch, and the commits in the VM have this author.
    """
    return {
        "SANDBOX_GIT_DIR": _out("git", "rev-parse", "--path-format=absolute", "--git-common-dir"),
        "SANDBOX_BRANCH": _out("git", "branch", "--show-current"),
        "GIT_AUTHOR_NAME": _out("git", "config", "user.name", default="agent"),
        "GIT_AUTHOR_EMAIL": _out("git", "config", "user.email", default="agent@localhost"),
    }


# --- Steps. One function for each step of main(), in the order of the cases there. ---


def github_login() -> None:
    """Log in to GitHub with the web flow of the GitHub App (`just msb github-login`). It writes the token file.

    1. Print the address of the approval page and open it in the browser. You approve the app.
    2. GitHub sends the browser to a port of this host (the callback address of the app) with a one-time code.
       _github_callback waits for it. The random `state` value must come back the same, or the answer is not from GitHub.
    3. Send the code and the client secret to GitHub, and save the tokens (_github_exchange).
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
    """Make the VM, or check that the VM that exists is current. The recipe runs this step under `bws run`.

    The fingerprint is a hash of sandbox.yaml, the image and the host values. msb keeps it in the label `config-sha` of the VM.
    1. No VM exists: make it. msb reads the secrets of sandbox.yaml from the environment: GH_TOKEN, CLAUDE_CODE_OAUTH_TOKEN and the Bitwarden keys.
       GH_TOKEN is the GitHub App token of github.py. CLAUDE_CODE_OAUTH_TOKEN is the access token of the Claude login of this host.
    2. A VM exists, but it does not run or it has another fingerprint: stop. If you remove it, its clone goes too, so you decide.
    3. A VM exists, runs and is current: give it the current two tokens with `msb modify --secret`. It does not restart.
    """
    name = os.environ["MSB_NAME"]
    values = _host_values()
    tokens = {"GH_TOKEN": _github_token(), "CLAUDE_CODE_OAUTH_TOKEN": _claude_token()}
    # The fingerprint is a hash of sandbox.yaml, the image and the host values. The token and the branch are not in it.
    parts = [
        CONFIG.read_text(),
        _image_id(),
        values["SANDBOX_GIT_DIR"],
        values["GIT_AUTHOR_NAME"],
        values["GIT_AUTHOR_EMAIL"],
        str(HOST_PORTS),
    ]
    wanted = hashlib.sha256("\n".join(parts).encode()).hexdigest()[:16]

    # msb keeps the fingerprint of the VM in the label config-sha.
    info = _out("msb", "inspect", name, "--format", "json", default="")
    if not info:
        # A failed boot leaves a stale folder. Then msb says "already exists" (microsandbox issue 1908). `msb inspect` does not show it.
        shutil.rmtree(Path(os.environ.get("MSB_HOME", Path.home() / ".microsandbox")) / "sandboxes" / name, ignore_errors=True)
        port_rules = [arg for port in HOST_PORTS for arg in ("--net-rule", f"allow@host:tcp:{port}")]
        # msb reads the value of each secret of sandbox.yaml from its environment: the two tokens, and the Bitwarden keys (from `bws run`).
        done = subprocess.run(
            ["msb", "run", "-d", "--name", name, "--conf", str(CONFIG), "--label", f"config-sha={wanted}", *port_rules],
            env=os.environ | values | tokens,
            check=False,
        )
        if done.returncode != 0:
            _die("msb could not make the VM (its message is above).")
        return
    vm = json.loads(info)
    status = vm["status"].lower()
    if vm["config"]["labels"].get("config-sha") != wanted or status != "running":
        # msb fixes the config of a VM when it makes the VM. It does not run sandbox-boot when it starts a stopped VM.
        # If you remove the VM, you remove its clone, so you decide.
        print(
            f"msb: {name} is {status}. It is not current: sandbox.yaml, the image or a host value changed, or the VM stopped.",
            file=sys.stderr,
        )
        _die("push any work in it (just msb shell). Then run: just msb rm && just msb run")
    # The VM runs and is current. Give it the current tokens. The placeholders in the VM stay, and the VM does not restart.
    for secret, value in tokens.items():
        hosts = _out("yq", "-r", f'.secrets.{secret}.allow | join(",")', str(CONFIG))
        done = subprocess.run(
            ["msb", "modify", name, "--secret", f"{secret}@{hosts}"],
            env=os.environ | {secret: value},
            capture_output=True,
            text=True,
            check=False,
        )
        if done.returncode != 0:
            _die(f"msb could not give the VM the current value of {secret}: {done.stderr.strip()[:300]}")


def wait_boot() -> None:
    """Wait until sandbox-boot writes /run/sandbox-ready, for at most BOOT_TIMEOUT seconds.

    sandbox-boot clones the repo, installs the hook and starts Headroom. If a step fails, it exits and the VM stops, so the wait ends.
    Then print the end of the boot log on stderr and exit with 1.
    """
    name = os.environ["MSB_NAME"]
    # sandbox-boot clones the repo, installs the hook and starts Headroom. Then it writes /run/sandbox-ready.
    # If a step fails, sandbox-boot exits with an error and the VM stops. The wait then ends, and the boot log shows the reason.
    wait = ["msb", "exec", name, "--", "sh", "-c", "until [ -f /run/sandbox-ready ]; do sleep 1; done"]
    try:
        ready = subprocess.run(wait, timeout=BOOT_TIMEOUT, check=False).returncode == 0
    except subprocess.TimeoutExpired:
        ready = False
    if not ready:
        log = _out("msb", "logs", name, default="").splitlines()[-15:]
        print(f"msb: the VM did not finish its boot. This is the end of its log (msb logs {name}):\n" + "\n".join(log), file=sys.stderr)
        sys.exit(1)


def main() -> None:
    """Read the step from the command line and call its function. The steps have the same order here, in the module docstring and in this file."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    for step in ("github-login", "ensure-vm", "wait-boot"):
        steps.add_parser(step)
    args = parser.parse_args()
    match args.step:
        case "github-login":
            github_login()
        case "ensure-vm":
            ensure_vm()
        case "wait-boot":
            wait_boot()


if __name__ == "__main__":
    main()
