#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The steps of the msb sandbox recipes: msb.py <step>

The justfile has the recipes and the order of the steps. This file has the logic of each step. Exit 1: wrong setup or a failed step.
The justfile exports MSB_NAME, MSB_IMAGE and MSB_WORKSPACE. Run msb.py through `just msb <recipe>`.

preflight        check that msb, bws, the GitHub login and the image exist
github-login     log in to GitHub with the GitHub App: you type a code in the browser. The tokens go to a file with mode 600
ensure-vm        make the VM from sandbox.yaml if none exists. If a VM exists and is current, give it the current GitHub token. Else stop.
                 The recipe runs this step under `bws run`, so the Bitwarden secrets are in its environment
wait-boot        wait until sandbox-boot is ready. If it fails, print the end of the boot log
ssh-key          print the path of your SSH public key
vscode-settings  set the VS Code settings for Remote-SSH
check-host HOST  stop if HOST is not a host name
image-tags       print the tags of the published image, one for each line. Stop if dev-tools/ differs from the commit
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, NoReturn

MSB_DIR = Path(__file__).resolve().parent
CONFIG = MSB_DIR / "sandbox.yaml"
BOOT_TIMEOUT = 90  # seconds that `wait-boot` waits for sandbox-boot
# The GitHub App of this repository. The client ID is public. You installed the app on this repository only, with the permissions contents,
# issues and pull requests. So the token cannot do more. The access token lasts 8 hours. The refresh token lasts about 6 months, and each
# refresh gives a new one. So the tokens go in a file on the host (mode 600).
GITHUB_CLIENT_ID = "Iv23liVvjK9IHk8lWmIh"
GITHUB_TOKEN_FILE = Path.home() / ".config" / "msb" / "github-app.json"
REFRESH_MARGIN = 1800  # seconds. A token that expires in less time is refreshed
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


def preflight() -> None:
    """Check what `run` needs, before it starts anything. It stops at the first problem and prints nothing if all is well.

    It checks: msb and bws are on the PATH, the GitHub token file exists, and the local image exists.
    """
    if not shutil.which("msb"):
        die('msb is not on the PATH. Run: mise install && eval "$(mise activate bash)"')
    if not shutil.which("bws"):
        die("bws is not on the PATH. Run: mise install")
    if not GITHUB_TOKEN_FILE.is_file():
        die("there is no GitHub login, so git push in the VM fails. Run: just msb github-login")
    image_id()


def image_id() -> str:
    """Return the id of the local Docker image MSB_IMAGE. Stop with a hint if the image does not exist.

    The id is part of the fingerprint of the VM, so a new image makes the VM not current.
    """
    image = setting("MSB_IMAGE")
    return out("docker", "image", "inspect", image, "--format", "{{.Id}}", default="") or die(
        f"the image {image} does not exist. Run: just msb image-build"
    )


def github_post(path: str, **data: str) -> dict[str, Any]:
    """Send a request to https://github.com/login/<path> and return the JSON reply.

    GitHub answers an error with a JSON body and an HTTP error code, or with code 200 and an `error` key. Both come back as a dict.
    """
    body = urllib.parse.urlencode({"client_id": GITHUB_CLIENT_ID, **data}).encode()
    request = urllib.request.Request(f"https://github.com/login/{path}", data=body, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        return json.load(error)


def github_save(reply: dict[str, Any]) -> str:
    """Write the tokens of a GitHub reply to the token file, and return the access token.

    The file has mode 600 from the first byte. A new file replaces the old one in one step, so a crash never leaves a half-written file.
    Stop if the reply has no refresh token: the app does not expire its tokens, and then nothing can refresh them.
    """
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
    return saved["access_token"]


def github_login() -> None:
    """Log in to GitHub with the device flow of the GitHub App (`just msb github-login`). It writes the token file.

    1. Ask GitHub for a code. If GitHub refuses, the device flow is off in the app: stop with a hint.
    2. Print the address and the code. You type the code in the browser and approve.
    3. Ask GitHub every few seconds if you approved, until you do or the code expires.
    4. Save the access token and the refresh token with github_save.

    It needs no client secret and no local server. It runs without `bws run`.
    """
    code = github_post("device/code")
    if "device_code" not in code:
        die(
            f"GitHub refused the login: {code.get('error_description', code.get('error'))}. Turn on 'Enable Device Flow' in the app settings."
        )
    print(f"Open {code['verification_uri']} and type this code: {code['user_code']}")
    interval = code["interval"]
    deadline = time.time() + code["expires_in"]
    while time.time() < deadline:
        time.sleep(interval)
        reply = github_post(
            "oauth/access_token", device_code=code["device_code"], grant_type="urn:ietf:params:oauth:grant-type:device_code"
        )
        match reply.get("error"):
            case None:
                github_save(reply)
                print(f"GitHub login saved in {GITHUB_TOKEN_FILE} (mode 600).")
                return
            case "authorization_pending":
                pass
            case "slow_down":
                interval += 5
            case error:
                die(f"GitHub refused the login ({error}). Run: just msb github-login")
    die("the code expired. Run: just msb github-login")


def github_token() -> str:
    """Return a valid GitHub access token from the token file. `ensure-vm` calls this.

    If the access token expires in less than REFRESH_MARGIN seconds, send the refresh token to GitHub and save the two new tokens.
    Each refresh makes the old refresh token useless. Stop with a message if there is no file, if its mode is not 600,
    if the refresh token is too old (about 6 months), or if GitHub refuses the refresh. Each message says: run `just msb github-login`.
    """
    if not GITHUB_TOKEN_FILE.is_file():
        die("there is no GitHub login. Run: just msb github-login")
    if GITHUB_TOKEN_FILE.stat().st_mode & 0o077:
        die(f"{GITHUB_TOKEN_FILE} must have mode 600.")
    saved = json.loads(GITHUB_TOKEN_FILE.read_text())
    if saved["expires_at"] - time.time() > REFRESH_MARGIN:
        return saved["access_token"]
    if saved["refresh_expires_at"] <= time.time():
        die("the GitHub login is too old to refresh. Run: just msb github-login")
    # The client secret is in the environment when `bws run` started this step. GitHub may ask for it on a refresh.
    secret = {"client_secret": value} if (value := os.environ.get("GITHUB_APP_CLIENT_SECRET")) else {}
    reply = github_post("oauth/access_token", grant_type="refresh_token", refresh_token=saved["refresh_token"], **secret)
    if "access_token" not in reply:
        die(f"GitHub refused the refresh ({reply.get('error')}). Run: just msb github-login")
    return github_save(reply)


def host_values() -> dict[str, str]:
    """Return the host values that sandbox.yaml names as ${NAME}: the git directory, the branch, and the git name and email.

    They come from git on the host. The VM clones the git directory and starts on the branch, and the commits in the VM have this author.
    """
    return {
        "SANDBOX_GIT_DIR": out("git", "rev-parse", "--path-format=absolute", "--git-common-dir"),
        "SANDBOX_BRANCH": out("git", "branch", "--show-current"),
        "GIT_AUTHOR_NAME": out("git", "config", "user.name", default="agent"),
        "GIT_AUTHOR_EMAIL": out("git", "config", "user.email", default="agent@localhost"),
    }


def host_port_rules() -> list[str]:
    """Return the `--net-rule` arguments of `msb run` that let the VM reach the ports of HOST_PORTS on the host.

    sandbox.yaml cannot express a rule for a port, so msb.py adds these rules when it makes the VM.
    """
    return [arg for port in HOST_PORTS for arg in ("--net-rule", f"allow@host:tcp:{port}")]


def ensure_vm() -> None:
    """Make the VM, or check that the VM that exists is current. The recipe runs this step under `bws run`.

    The fingerprint is a hash of sandbox.yaml, the image and the host values. msb keeps it in the label `config-sha` of the VM.
    1. No VM exists: make it. msb reads the secrets of sandbox.yaml from the environment: the Bitwarden keys and GH_TOKEN.
    2. A VM exists, but it does not run or it has another fingerprint: stop. Removing it deletes its clone, so you decide.
    3. A VM exists, runs and is current: give it the current GitHub token with `msb modify --secret`. It does not restart.
    """
    name = setting("MSB_NAME")
    values = host_values()
    token = github_token()
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
        # msb reads the value of each secret of sandbox.yaml from its environment: the Bitwarden keys (from `bws run`), and GH_TOKEN.
        done = subprocess.run(
            ["msb", "run", "-d", "--name", name, "--conf", str(CONFIG), "--label", f"config-sha={wanted}", *host_port_rules()],
            env=os.environ | values | {"GH_TOKEN": token},
            check=False,
        )
        if done.returncode != 0:
            die("msb could not make the VM (its message is above). A missing secret means a missing key in the Bitwarden project.")
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
    # The VM runs and is current. Give it the current GitHub token. The placeholder in the VM stays, and the VM does not restart.
    hosts = out("yq", "-r", '.secrets.GH_TOKEN.allow | join(",")', str(CONFIG))
    done = subprocess.run(
        ["msb", "modify", name, "--secret", f"GH_TOKEN@{hosts}"],
        env=os.environ | {"GH_TOKEN": token},
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        die(f"msb could not give the VM the current GitHub token: {done.stderr.strip()[:300]}")


def wait_boot() -> None:
    """Wait until sandbox-boot writes /run/sandbox-ready, for at most BOOT_TIMEOUT seconds.

    sandbox-boot clones the repo, installs the hook and starts Headroom. If a step fails, it exits and the VM stops, so the wait ends.
    Then print the end of the boot log on stderr and exit with 1.
    """
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
    """Read the step from the command line and call its function. The steps have the same order here, in the module docstring and in this file."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    for step in ("preflight", "github-login", "ensure-vm", "wait-boot", "ssh-key", "vscode-settings"):
        steps.add_parser(step)
    steps.add_parser("check-host").add_argument("host")
    steps.add_parser("image-tags")
    args = parser.parse_args()
    match args.step:
        case "preflight":
            preflight()
        case "github-login":
            github_login()
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
        case "image-tags":
            image_tags()


if __name__ == "__main__":
    main()
