#!/usr/bin/env python3
"""Host side of the VM node identity: spire.py enroll|remove

enroll  Write a one-time join token and the trust bundle to ~/.sbx/spire/. Skip when an agent of the user is attested with 10+ minutes of SVID
        left. SPIRE_ENROLL_FORCE=1 forces a token.
remove  Evict the agent, delete its alias entries on the SPIRE server and the files in ~/.sbx/spire/.

Needs SANDBOX_GITHUB_ID (numeric GitHub id). Exit 1: wrong setup. Exit 3: cluster unreachable.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

TTL = 600  # token lifetime, seconds
MARGIN = 600  # minimum SVID time left, seconds

SBX = Path(__file__).resolve().parent.parent
OUT = Path.home() / ".sbx" / "spire"  # same path in sbxenv.yaml and dev-tools.yaml
IDENTITY = SBX.parent / "code/mcp-sandbox/part-3-mcp-guardrails/config/cloud/kind/identity.yaml"


def die(message, code=1):
    print(f"spire.py: {message}", file=sys.stderr)
    sys.exit(code)


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        die(f"{cmd[0]} is not on the PATH of the host.")


def host(*cmd):
    """Run a command. Return its output, or None on failure."""
    done = run(cmd)
    return done.stdout.strip() if done.returncode == 0 else None


def server(context, *args):
    """Run spire-server in the SPIRE server pod. Exit 3 on failure."""
    pod = ["kubectl", "--context", context, "-n", "spire-system", "exec", "spire-server-0", "-c", "spire-server", "--"]
    done = run([*pod, "/opt/spire/bin/spire-server", *args])
    if done.returncode:
        die(f"cannot ask the SPIRE server of {context}: {(done.stderr.strip().splitlines() or [''])[-1]}", 3)
    return done.stdout


def spiffe_id(parts):
    return f"spiffe://{parts['trust_domain']}{parts['path']}"


def attested_agents(context, alias):
    """Agents attested under the alias, as {agent id: SVID expiry}."""
    entries = json.loads(server(context, "entry", "show", "-spiffeID", alias, "-output", "json")).get("entries") or []
    parents = {spiffe_id(e["parent_id"]) for e in entries}
    agents = json.loads(server(context, "agent", "list", "-output", "json")).get("agents") or []
    return {spiffe_id(a["id"]): int(a["x509svid_expires_at"]) for a in agents if spiffe_id(a["id"]) in parents}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    github_id = os.environ.get("SANDBOX_GITHUB_ID", "")
    sbxenv = SBX / "sbxenv.yaml"

    # prechecks
    if mode not in ("enroll", "remove"):
        die("usage: spire.py enroll|remove")
    if os.environ.get("SANDBOX_NAME"):
        die("run this on the host, not in the sandbox: the token is made by the SPIRE server of the cluster.")
    if not github_id.isdigit():
        die(
            "SANDBOX_GITHUB_ID is not a number. Use the numeric id of your GitHub account: export SANDBOX_GITHUB_ID=$(gh api user --jq .id)"
        )
    trust_domain = host("yq", "-r", ".trust_domain", str(IDENTITY))
    if not trust_domain or trust_domain == "null":
        die(f"cannot read trust_domain from {IDENTITY}")
    if mode == "enroll" and str(OUT) not in (host("yq", "-r", ".additionalWorkspaces[].path", str(sbxenv)) or "").split():
        die(f"{sbxenv} does not mount {OUT}. Put this under additionalWorkspaces: - path: {OUT}, readOnly: true")
    context = host("kubectl", "config", "current-context")
    if not context:
        die("kubectl has no current context, so the SPIRE server cannot be reached. Set one: kubectl config use-context <name>", 3)

    # The alias is the parent of the workload entries of the user.
    alias = f"spiffe://{trust_domain}/microvm/{github_id}"

    if mode == "remove":
        for agent in attested_agents(context, alias):
            server(context, "agent", "evict", "-spiffeID", agent)
        for entry in json.loads(server(context, "entry", "show", "-spiffeID", alias, "-output", "json")).get("entries") or []:
            server(context, "entry", "delete", "-entryID", entry["id"])
        for name in ("join-token", "bundle.spiffe"):
            (OUT / name).unlink(missing_ok=True)
        print(f"spire: removed the agent and the alias entries of user {github_id}")
        return

    # enroll
    valid_until = max(attested_agents(context, alias).values(), default=0)
    if not os.environ.get("SPIRE_ENROLL_FORCE") and valid_until > time.time() + MARGIN:
        print(
            f"spire: an agent of user {github_id} is attested until {time.strftime('%F %T', time.localtime(valid_until))}, so no new join token"
        )
        return

    OUT.mkdir(mode=0o700, parents=True, exist_ok=True)
    OUT.chmod(0o700)
    (OUT / "join-token").unlink(missing_ok=True)  # remove the old token
    (OUT / "bundle.spiffe").write_text(server(context, "bundle", "show", "-format", "spiffe"))  # public data

    token = json.loads(server(context, "token", "generate", "-ttl", str(TTL), "-spiffeID", alias, "-output", "json"))["value"]
    fd = os.open(OUT / "join-token.tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)  # mode 600
    with os.fdopen(fd, "w") as f:
        f.write(token)
    os.replace(OUT / "join-token.tmp", OUT / "join-token")
    print(f"spire: join token for user {github_id} in {OUT} (valid {TTL // 60} minutes), alias {alias}")


if __name__ == "__main__":
    main()
