"""ext-mcp request/response rules. Pure functions, no gRPC, so each rule is unit-testable.

Each check returns None when the call passes, or a short rule id when it must be denied.
Rule ids are what the audit log and the test expectations name, never the offending value.
"""
import posixpath
import re

SENSITIVE_NAMES = (".env", ".pem", ".key", ".tfstate", "id_rsa", "id_ed25519")
SECRET_PATTERNS = {
    "aws-access-key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "github-token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"),
    "private-key": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
}


def check_path(path: str) -> str | None:
    """MCP05: traversal and sensitive files in a path-like argument."""
    norm = posixpath.normpath(path)
    if norm.startswith("..") or "/../" in f"/{norm}/" or path.startswith("/"):
        return "path-traversal"
    name = posixpath.basename(norm).lower()
    if any(name == s or name.endswith(s) for s in SENSITIVE_NAMES):
        return "sensitive-path"
    return None


def find_secret(text: str) -> str | None:
    """MCP01 / MCP10: a credential in arguments or in a result."""
    for rule_id, pat in SECRET_PATTERNS.items():
        if pat.search(text):
            return f"secret-{rule_id}"
    return None


def redact(text: str) -> tuple[str, list[str]]:
    """Mask credentials in a result. Returns the new text and the rule ids that fired."""
    fired = []
    for rule_id, pat in SECRET_PATTERNS.items():
        text, n = pat.subn("[REDACTED]", text)
        if n:
            fired.append(f"secret-{rule_id}")
    return text, fired
