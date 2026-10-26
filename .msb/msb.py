#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The steps of the msb sandbox recipes: msb.py <step>

The justfile has the recipes and the order of the steps. This file has the logic of each step. Exit 1: wrong setup or a failed step.
The justfile exports MSB_NAME, MSB_IMAGE and MSB_WORKSPACE. Run msb.py through `just msb <recipe>`.

preflight        check that msb, the GitHub login and the image exist
github-login     log in to GitHub with the GitHub App (a browser approval), and save the tokens in a file with mode 600
refresh          refresh the GitHub token if it expires soon, and push it and the Bitwarden secrets into the running VM
ensure-vm        make the VM from sandbox.yaml if none exists. Stop if a VM exists and is not current
                 (GITHUB_TOKEN is the token of the GitHub App. The other secrets of sandbox.yaml come from the Bitwarden project)
wait-boot        wait until sandbox-boot is ready. If it fails, print the end of the boot log
ssh-key          print the path of your SSH public key
vscode-settings  set the VS Code settings for Remote-SSH
check-host HOST  stop if HOST is not a host name
vault-secret KEY print one Bitwarden secret for a pipe. It refuses to print to a terminal
image-tags       print the tags of the published image, one for each line. Stop if dev-tools/ has uncommitted changes
"""

import argparse
import fcntl
import getpass
import hashlib
import http.server
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path
from typing import Any, NoReturn

MSB_DIR = Path(__file__).resolve().parent
CONFIG = MSB_DIR / "sandbox.yaml"
BOOT_TIMEOUT = 90  # seconds that `wait-boot` waits for sandbox-boot
VAULT_TIMEOUT = 30  # seconds that the call to Bitwarden can take
# The GitHub App of this repository. The client ID is public (.sbx/agent/agent.just has it too). The client secret is in Bitwarden.
# The app has the permissions contents, issues and pull requests, on this repository only. So the token cannot do more.
GITHUB_APP_CLIENT_ID = "Iv23liVvjK9IHk8lWmIh"
GITHUB_APP_SECRET = "GITHUB_APP_CLIENT_SECRET"  # the Bitwarden key
GITHUB_CALLBACK_PORT = 8765  # the callback URL of the app is http://127.0.0.1:8765/callback
# The access token lasts 8 hours. The refresh token lasts about 6 months, and each refresh gives a new one. Bitwarden is read-only for the
# machine account, so the tokens go in a file on the host (mode 600).
GITHUB_TOKEN_FILE = Path(os.environ.get("MSB_GITHUB_TOKEN_FILE", Path.home() / ".config" / "msb" / "github-app.json"))
REFRESH_MARGIN = 1800  # seconds. A token that expires in less time is refreshed
LOGIN_TIMEOUT = 300  # seconds that `github-login` waits for the browser approval
# The ports of the host that the VM can reach, as host.microsandbox.internal:<port>. sandbox.yaml cannot express a rule for a port, so msb.py
# passes one `--net-rule allow@host:tcp:<port>` to msb for each. The services are in the kind cluster (the SPIRE agent and kubectl need them).
HOST_PORTS = {
    6444: "kind API server",
    18081: "SPIRE server",
    19090: "Flux Operator web UI",
}
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


def die(message: str) -> NoReturn:
    print(f"msb: {message}", file=sys.stderr)
    sys.exit(1)


def setting(name: str) -> str:
    """A value that the justfile exports."""
    return os.environ.get(name) or die(f"{name} is not set. Run this through `just msb <recipe>`.")


def out(*cmd: str, default: str | None = None) -> str:
    """Run a command in .msb/ (inside the repo) and return its output. If it fails, return `default`, or stop when there is no default."""
    done = subprocess.run(cmd, capture_output=True, text=True, check=False, cwd=MSB_DIR)
    if done.returncode == 0:
        return done.stdout.strip()
    if default is None:
        die(f"`{' '.join(cmd)}` failed: {done.stderr.strip()}")
    return default


def image_id() -> str:
    image = setting("MSB_IMAGE")
    return out("docker", "image", "inspect", image, "--format", "{{.Id}}", default="") or die(
        f"the image {image} does not exist. Run: just msb image-build"
    )


def host_values() -> dict[str, str]:
    """The host values that sandbox.yaml names as ${NAME}."""
    return {
        "GITHUB_TOKEN": github_token(),
        "SANDBOX_GIT_DIR": out("git", "rev-parse", "--path-format=absolute", "--git-common-dir"),
        "SANDBOX_BRANCH": out("git", "branch", "--show-current"),
        "GIT_AUTHOR_NAME": out("git", "config", "user.name", default="agent"),
        "GIT_AUTHOR_EMAIL": out("git", "config", "user.email", default="agent@localhost"),
    }


def vault_token() -> str:
    """The access token of the Bitwarden machine account: BWS_ACCESS_TOKEN, then the token file, then a prompt that does not echo."""
    if token := os.environ.get("BWS_ACCESS_TOKEN"):
        return token
    path = Path(os.environ.get("BWS_ACCESS_TOKEN_FILE", Path.home() / ".config" / "bws" / "access-token"))
    if path.is_file():
        if path.stat().st_mode & 0o777 not in (0o400, 0o600):
            die(f"{path} must have mode 600 or 400.")
        return path.read_text().strip()
    try:
        token = getpass.getpass("Bitwarden access token (machine account): ").strip()
    except (EOFError, OSError):
        die(f"set BWS_ACCESS_TOKEN, or save the token in {path}. There is no terminal to ask on.")
    return token or die("the access token is empty.")


def vault_secrets(names: list[str]) -> dict[str, str]:
    """The values of the secrets `names` from the Bitwarden project. The values go to the environment of msb and nowhere else."""
    if not names:
        return {}  # no call to Bitwarden, and no token needed
    if not shutil.which("bws"):
        die('bws is not on the PATH. Run: mise install && eval "$(mise activate bash)"')
    env = os.environ | {"BWS_ACCESS_TOKEN": vault_token()}
    done = subprocess.run(
        ["bws", "secret", "list", "--output", "json"], capture_output=True, text=True, timeout=VAULT_TIMEOUT, env=env, check=False
    )
    if done.returncode != 0:
        die(f"bws failed: {done.stderr.strip()[:300]}")
    items = json.loads(done.stdout)
    values = {}
    for name in names:
        found = [item["value"] for item in items if item["key"] == name]
        if len(found) != 1:
            die(f"expected one Bitwarden secret named {name}, found {len(found)}.")
        values[name] = found[0]
    return values


def vault_names() -> list[str]:
    """The secrets of sandbox.yaml that come from Bitwarden. GITHUB_TOKEN comes from your gh login."""
    names = out("yq", "-r", ".secrets // {} | keys | .[]", str(CONFIG)).split()
    return [name for name in names if name != "GITHUB_TOKEN"]


def host_port_rules() -> list[str]:
    return [arg for port in HOST_PORTS for arg in ("--net-rule", f"allow@host:tcp:{port}")]


def vault_secret(key: str) -> None:
    if sys.stdout.isatty():
        die("this prints a secret. Pipe it to a command, for example: ... | docker login --password-stdin")
    print(vault_secrets([key])[key], end="")


def image_tags() -> None:
    """The commit that the image is built from, `latest` on main, and the git tag of the commit if it has one."""
    if out("git", "status", "--porcelain", "--", "dev-tools"):
        die("dev-tools/ has uncommitted changes. The tag of the image is the commit, so commit them first.")
    tags = [out("git", "rev-parse", "HEAD")]
    if out("git", "branch", "--show-current") == "main":
        tags.append("latest")
    if git_tag := out("git", "describe", "--exact-match", "--tags", "HEAD", default=""):
        tags.append(git_tag)
    print("\n".join(tags))


def github_post(data: dict[str, str]) -> dict[str, Any]:
    """A request to the token endpoint of GitHub. GitHub answers 200 with an `error` key when it refuses."""
    body = urllib.parse.urlencode({"client_id": GITHUB_APP_CLIENT_ID, **data}).encode()
    request = urllib.request.Request("https://github.com/login/oauth/access_token", data=body, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def save_github_tokens(reply: dict[str, Any]) -> dict[str, Any]:
    """Write the tokens of a reply to the token file. The file has mode 600 from the first byte, and it is replaced in one step."""
    if "refresh_token" not in reply:
        die("GitHub gave a token that does not expire. Turn on 'Expire user authorization tokens' in the settings of the app.")
    now = time.time()
    saved = {
        "access_token": reply["access_token"],
        "refresh_token": reply["refresh_token"],
        "expires_at": now + reply["expires_in"],
        "refresh_expires_at": now + reply["refresh_token_expires_in"],
    }
    GITHUB_TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp = GITHUB_TOKEN_FILE.with_suffix(".tmp")
    temp.unlink(missing_ok=True)
    with os.fdopen(os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as file:
        json.dump(saved, file)
    os.replace(temp, GITHUB_TOKEN_FILE)
    return saved


def github_login() -> None:
    """The web flow of a GitHub App: the browser goes back to a port of this host with a code, and the code becomes the tokens."""
    client_secret = vault_secrets([GITHUB_APP_SECRET])[GITHUB_APP_SECRET]
    state = secrets.token_urlsafe(16)
    redirect = f"http://127.0.0.1:{GITHUB_CALLBACK_PORT}/callback"
    got: dict[str, str] = {}

    class Callback(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if query.get("state") == [state] and "code" in query:
                got["code"] = query["code"][0]
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Approved. You can close this tab." if "code" in got else b"No approval.")

        def log_message(self, format: str, *args: object) -> None:  # no line of a log: the URL has the code
            pass

    server = http.server.HTTPServer(("127.0.0.1", GITHUB_CALLBACK_PORT), Callback)
    server.timeout = 5
    query = urllib.parse.urlencode({"client_id": GITHUB_APP_CLIENT_ID, "redirect_uri": redirect, "state": state})
    url = f"https://github.com/login/oauth/authorize?{query}"
    print(f"Approve the app in your browser. If it does not open, open this URL:\n{url}")
    webbrowser.open(url)
    deadline = time.time() + LOGIN_TIMEOUT
    while "code" not in got and time.time() < deadline:
        server.handle_request()
    server.server_close()
    if "code" not in got:
        die("there was no approval in time. Run: just msb github-login")
    reply = github_post({"client_secret": client_secret, "code": got["code"], "redirect_uri": redirect})
    if "access_token" not in reply:
        die(f"GitHub refused the code: {reply.get('error_description', reply.get('error'))}")
    save_github_tokens(reply)
    print(f"GitHub login saved in {GITHUB_TOKEN_FILE} (mode 600).")


def github_token() -> str:
    """The access token. If it expires in less than REFRESH_MARGIN seconds, refresh it first. The lock stops two refreshes at the same time:
    each refresh makes the old refresh token useless, so the second one would fail."""
    GITHUB_TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(GITHUB_TOKEN_FILE.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not GITHUB_TOKEN_FILE.is_file():
            die("there is no GitHub login. Run: just msb github-login")
        if GITHUB_TOKEN_FILE.stat().st_mode & 0o077:
            die(f"{GITHUB_TOKEN_FILE} must have mode 600.")
        saved = json.loads(GITHUB_TOKEN_FILE.read_text())
        if saved["expires_at"] - time.time() > REFRESH_MARGIN:
            return saved["access_token"]
        if saved["refresh_expires_at"] <= time.time():
            die("the GitHub login is too old to refresh. Run: just msb github-login")
        client_secret = vault_secrets([GITHUB_APP_SECRET])[GITHUB_APP_SECRET]
        reply = github_post({"client_secret": client_secret, "grant_type": "refresh_token", "refresh_token": saved["refresh_token"]})
        if "access_token" not in reply:
            die(f"GitHub refused the refresh ({reply.get('error')}). Run: just msb github-login")
        return save_github_tokens(reply)["access_token"]


def push_secret(name: str, value: str) -> None:
    """Give a running VM a new value for a secret. The placeholder in the VM stays the same, and the VM does not restart."""
    hosts = out("yq", "-r", f'.secrets.{name}.allow | join(",")', str(CONFIG))
    done = subprocess.run(
        ["msb", "modify", setting("MSB_NAME"), "--secret", f"{name}@{hosts}"],
        env=os.environ | {name: value},
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        die(f"msb could not change the secret {name}: {done.stderr.strip()[:300]}")


def refresh() -> None:
    token = github_token()  # refreshes the token file, with or without a VM
    info = out("msb", "inspect", setting("MSB_NAME"), "--format", "json", default="")
    if not info or json.loads(info)["status"].lower() != "running":
        print("There is no running VM. The token file is current.")
        return
    push_secret("GITHUB_TOKEN", token)
    for name, value in vault_secrets(vault_names()).items():
        push_secret(name, value)
    print("The running VM has the current secrets.")


def preflight() -> None:
    if not shutil.which("msb"):
        die('msb is not on the PATH. Run: mise install && eval "$(mise activate bash)"')
    if not GITHUB_TOKEN_FILE.is_file():
        die("there is no GitHub login, so git push in the VM fails. Run: just msb github-login")
    image_id()


def ensure_vm() -> None:
    name = setting("MSB_NAME")
    values = host_values()
    # The fingerprint is a hash of sandbox.yaml, the image and the host values. The token and the branch are not in it.
    parts = [
        CONFIG.read_text(),
        image_id(),
        values["SANDBOX_GIT_DIR"],
        values["GIT_AUTHOR_NAME"],
        values["GIT_AUTHOR_EMAIL"],
        str(HOST_PORTS),
    ]
    wanted = hashlib.sha256("\n".join(parts).encode()).hexdigest()[:16]

    # msb keeps the fingerprint of the VM in the label config-sha.
    info = out("msb", "inspect", name, "--format", "json", default="")
    if not info:
        # A failed boot leaves a stale folder. Then msb says "already exists" (microsandbox issue 1908). `msb inspect` does not show it.
        shutil.rmtree(Path(os.environ.get("MSB_HOME", Path.home() / ".microsandbox")) / "sandboxes" / name, ignore_errors=True)
        subprocess.run(
            ["msb", "run", "-d", "--name", name, "--conf", str(CONFIG), "--label", f"config-sha={wanted}", *host_port_rules()],
            env=os.environ | values | vault_secrets(vault_names()),  # msb reads the host values and the secrets from its environment
            check=True,
        )
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
        die("push any work in it (just msb shell). Then run: just msb rm && just msb run")
    # The VM runs and is current. Its GitHub token can be older than the file: `run` gives it the current one.
    push_secret("GITHUB_TOKEN", values["GITHUB_TOKEN"])


def wait_boot() -> None:
    name = setting("MSB_NAME")
    # sandbox-boot clones the repo, installs the hook and starts Headroom. Then it writes /run/sandbox-ready.
    # If a step fails, sandbox-boot exits with an error and the VM stops. The wait then ends, and the boot log shows the reason.
    wait = ["msb", "exec", name, "--", "sh", "-c", "until [ -f /run/sandbox-ready ]; do sleep 1; done"]
    try:
        ready = subprocess.run(wait, timeout=BOOT_TIMEOUT, check=False).returncode == 0
    except subprocess.TimeoutExpired:
        ready = False
    if not ready:
        log = out("msb", "logs", name, default="").splitlines()[-15:]
        print(f"msb: the VM did not finish its boot. This is the end of its log (msb logs {name}):\n" + "\n".join(log), file=sys.stderr)
        sys.exit(1)


def ssh_key() -> None:
    key = Path(os.environ.get("SANDBOX_SSH_PUBKEY", Path.home() / ".ssh" / "id_ed25519.pub"))
    if not key.is_file():
        die(f"there is no SSH public key at {key}. Make one with: ssh-keygen -t ed25519. Or set SANDBOX_SSH_PUBKEY.")
    print(key)


def vscode_settings() -> None:
    path = Path.home() / ".config" / "Code" / "User" / "settings.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    current = json.loads(path.read_text()) if path.is_file() else {}
    if current | VSCODE_SETTINGS != current:
        path.write_text(json.dumps(current | VSCODE_SETTINGS, indent=2) + "\n")
        print(f"VS Code settings changed in {path}. New VS Code windows use them.")


def check_host(host: str) -> None:
    if not re.fullmatch(r"(\*\.)?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?", host):
        die(f"{host} is not a host name.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    for step in ("preflight", "ensure-vm", "wait-boot", "ssh-key", "vscode-settings", "image-tags", "github-login", "refresh"):
        steps.add_parser(step)
    steps.add_parser("check-host").add_argument("host")
    steps.add_parser("vault-secret").add_argument("key")
    args = parser.parse_args()
    match args.step:
        case "preflight":
            preflight()
        case "ensure-vm":
            ensure_vm()
        case "wait-boot":
            wait_boot()
        case "ssh-key":
            ssh_key()
        case "vscode-settings":
            vscode_settings()
        case "check-host":
            check_host(args.host)
        case "vault-secret":
            vault_secret(args.key)
        case "image-tags":
            image_tags()
        case "github-login":
            github_login()
        case "refresh":
            refresh()


if __name__ == "__main__":
    main()
