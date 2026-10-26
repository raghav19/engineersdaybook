#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The VM of the sandbox: vm.py <step>. The recipe `run` calls the steps in this order.

preflight   check that msb, bws, the GitHub login, the Claude login and the image exist
ensure-vm   make the VM from sandbox.yaml if none exists. If a VM exists and is current, give it the current tokens. Else stop.
            The recipe runs this step under `bws run`, so the Bitwarden keys are in its environment
wait-boot   wait until sandbox-boot is ready. If it fails, print the end of the boot log
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from claude import CREDENTIALS, claude_token
from common import MSB_DIR, die, out, setting
from github import GITHUB_TOKEN_FILE, github_token

CONFIG = MSB_DIR / "sandbox.yaml"
BOOT_TIMEOUT = 90  # seconds that `wait-boot` waits for sandbox-boot
# The ports of the host that the VM can reach, as host.microsandbox.internal:<port>. sandbox.yaml cannot express a rule for a port, so vm.py
# passes one `--net-rule allow@host:tcp:<port>` to msb for each. The services are in the kind cluster (the SPIRE agent and kubectl need them).
HOST_PORTS = {
    6444: "kind API server",
    18081: "SPIRE server",
    19090: "Flux Operator web UI",
}


def preflight() -> None:
    """Check what `run` needs, before it starts anything. It stops at the first problem and prints nothing if all is well.

    It checks four things. msb and bws are on the PATH. The GitHub token file and the Claude login of the host exist. The local image exists.
    """
    if not shutil.which("msb"):
        die('msb is not on the PATH. Run: mise install && eval "$(mise activate bash)"')
    if not shutil.which("bws"):
        die("bws is not on the PATH. Run: mise install")
    if not GITHUB_TOKEN_FILE.is_file():
        die("there is no GitHub login, so git push in the VM fails. Run: just msb github-login")
    if not CREDENTIALS.is_file():
        die(f"there is no Claude login on this host ({CREDENTIALS}). Run `claude` and sign in with your subscription.")
    image_id()


def image_id() -> str:
    """Return the id of the local Docker image MSB_IMAGE. Stop with a hint if the image does not exist.

    The id is part of the fingerprint of the VM, so a new image makes the VM not current.
    """
    image = setting("MSB_IMAGE")
    return out("docker", "image", "inspect", image, "--format", "{{.Id}}", default="") or die(
        f"the image {image} does not exist. Run: just msb image-build"
    )


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
    1. No VM exists: make it. msb reads the secrets of sandbox.yaml from the environment: GH_TOKEN, CLAUDE_CODE_OAUTH_TOKEN and the Bitwarden keys.
       GH_TOKEN is the GitHub App token of github.py. CLAUDE_CODE_OAUTH_TOKEN is the access token of the Claude login of this host.
    2. A VM exists, but it does not run or it has another fingerprint: stop. If you remove it, its clone goes too, so you decide.
    3. A VM exists, runs and is current: give it the current two tokens with `msb modify --secret`. It does not restart.
    """
    name = setting("MSB_NAME")
    values = host_values()
    tokens = {"GH_TOKEN": github_token(), "CLAUDE_CODE_OAUTH_TOKEN": claude_token()}
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
        # msb reads the value of each secret of sandbox.yaml from its environment: the two tokens, and the Bitwarden keys (from `bws run`).
        done = subprocess.run(
            ["msb", "run", "-d", "--name", name, "--conf", str(CONFIG), "--label", f"config-sha={wanted}", *host_port_rules()],
            env=os.environ | values | tokens,
            check=False,
        )
        if done.returncode != 0:
            die("msb could not make the VM (its message is above).")
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
    # The VM runs and is current. Give it the current tokens. The placeholders in the VM stay, and the VM does not restart.
    for secret, value in tokens.items():
        hosts = out("yq", "-r", f'.secrets.{secret}.allow | join(",")', str(CONFIG))
        done = subprocess.run(
            ["msb", "modify", name, "--secret", f"{secret}@{hosts}"],
            env=os.environ | {secret: value},
            capture_output=True,
            text=True,
            check=False,
        )
        if done.returncode != 0:
            die(f"msb could not give the VM the current value of {secret}: {done.stderr.strip()[:300]}")


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


def main() -> None:
    """Read the step from the command line and call its function."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    for step in ("preflight", "ensure-vm", "wait-boot"):
        steps.add_parser(step)
    match parser.parse_args().step:
        case "preflight":
            preflight()
        case "ensure-vm":
            ensure_vm()
        case "wait-boot":
            wait_boot()


if __name__ == "__main__":
    main()
