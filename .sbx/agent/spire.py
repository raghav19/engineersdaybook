#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""Host side of the VM node identity: spire.py enroll

Write a one-time join token and the trust bundle to ~/.sbx/spire/. Skip when a node of the user is attested with a valid SVID.
SPIRE_ENROLL_FORCE=1 forces a token: a new VM cannot use the SVID of the old one, and nothing evicts the old node.

Needs SANDBOX_GITHUB_ID (numeric GitHub id). Exit 1: wrong setup. Exit 3: cluster unreachable.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, NoReturn

type Json = dict[str, Any]

TTL = 600  # token lifetime, seconds
OUT = Path.home() / ".sbx" / "spire"  # same path in sbxenv.yaml and dev-tools.yaml
IDENTITY = Path(__file__).resolve().parents[2] / "code/mcp-sandbox/part-3-mcp-guardrails/config/cloud/kind/identity.yaml"
SERVER = ["kubectl", "-n", "spire-system", "exec", "spire-server-0", "-c", "spire-server", "--", "/opt/spire/bin/spire-server"]


def die(message: str, code: int = 1) -> NoReturn:
    print(f"spire.py: {message}", file=sys.stderr)
    sys.exit(code)


def server(*args: str) -> str:
    """Run spire-server in the SPIRE server pod. Exit 3 on failure."""
    try:
        done = subprocess.run([*SERVER, *args], capture_output=True, text=True, check=False)
    except FileNotFoundError:
        die("kubectl is not on the PATH of the host.")
    if done.returncode:
        last_line = (done.stderr.strip().splitlines() or [""])[-1]
        die(f"cannot ask the SPIRE server: {last_line}", 3)
    return done.stdout


def server_json(*args: str) -> Json:
    return json.loads(server(*args, "-output", "json"))


def spiffe_id(parts: dict[str, str]) -> str:
    return f"spiffe://{parts['trust_domain']}{parts['path']}"


def trust_domain() -> str:
    for line in IDENTITY.read_text().splitlines():
        if line.startswith("trust_domain:"):
            return line.partition(":")[2].strip()
    die(f"cannot read trust_domain from {IDENTITY}")


def valid_until(alias: str) -> int:
    """SVID expiry (epoch seconds) of the attested node that owns the alias. 0 when there is none."""
    entries = server_json("entry", "show", "-spiffeID", alias).get("entries") or []
    node_ids = {spiffe_id(entry["parent_id"]) for entry in entries}
    nodes = server_json("agent", "list").get("agents") or []
    return max((int(node["x509svid_expires_at"]) for node in nodes if spiffe_id(node["id"]) in node_ids), default=0)


def write_secret(path: Path, text: str) -> None:
    path.unlink(missing_ok=True)
    path.touch(mode=0o600)  # the mode comes before the content: nobody else can read the token
    path.write_text(text)


def main() -> None:
    github_id = os.environ.get("SANDBOX_GITHUB_ID", "")
    if not github_id.isdigit():
        die(
            "SANDBOX_GITHUB_ID is not a number. Use the numeric id of your GitHub account: export SANDBOX_GITHUB_ID=$(gh api user --jq .id)"
        )

    # The alias is the stable name of the node. It is the parent of the workload entries of the user.
    alias = f"spiffe://{trust_domain()}/microvm/{github_id}"

    expiry = valid_until(alias)
    if expiry > time.time() and not os.environ.get("SPIRE_ENROLL_FORCE"):
        print(f"spire: a node of user {github_id} is attested until {time.strftime('%F %T', time.localtime(expiry))}, so no new join token")
        return

    OUT.mkdir(mode=0o700, parents=True, exist_ok=True)
    write_secret(OUT / "join-token", server_json("token", "generate", "-ttl", str(TTL), "-spiffeID", alias)["value"])
    (OUT / "bundle.spiffe").write_text(server("bundle", "show", "-format", "spiffe"))  # public data
    print(f"spire: join token for user {github_id} in {OUT} (valid {TTL // 60} minutes), alias {alias}")


if __name__ == "__main__":
    main()
