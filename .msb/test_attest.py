#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = ["ruamel.yaml==0.19.1"]
# ///
"""Self-check of the pure parts of `msb.py attest`: the name checks of the CSR and the certificate, and the CertificateRequest.

Run it with `uv run .msb/test_attest.py`. It makes real CSRs and certificates with openssl in a temporary folder. It needs no VM and no cluster.
"""

import base64
import importlib.util
import subprocess
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("msb", Path(__file__).resolve().parent / "msb.py")
assert spec and spec.loader
msb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(msb)

NAME = "sandbox-dev"
URI = "x509pop://mcp.local/github-id/raghav19"


def make(folder: Path, cn: str, san: str | None, cert: bool = False) -> str:
    """Make a CSR (or a self-signed certificate) with openssl and return its PEM."""
    key = folder / "key.pem"
    if not key.exists():
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", str(key)],
            check=True,
            capture_output=True,
        )
    out = folder / ("out.crt" if cert else "out.csr")
    command = ["openssl", "req", "-key", str(key), "-subj", f"/CN={cn}", "-out", str(out)]
    command += ["-x509", "-days", "1"] if cert else ["-new"]
    if san:
        command += ["-addext", f"subjectAltName={san}"]
    subprocess.run(command, check=True, capture_output=True)
    return out.read_text()


def stops(kind: str, pem: str) -> bool:
    """True when the check stops the step."""
    try:
        msb._check_names(kind, pem, NAME, URI)
    except SystemExit:
        return True
    return False


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        assert not stops("req", make(folder, NAME, f"URI:{URI}")), "a good CSR passes"
        assert not stops("x509", make(folder, NAME, f"URI:{URI}", cert=True)), "a good certificate passes"
        assert stops("req", make(folder, "other-vm", f"URI:{URI}")), "another CN stops"
        assert stops("req", make(folder, NAME, "URI:x509pop://mcp.local/github-id/someone-else")), "another login stops"
        assert stops("req", make(folder, NAME, f"URI:{URI},DNS:evil.example")), "an extra SAN stops"
        assert stops("req", make(folder, NAME, None)), "no SAN stops"
        assert stops("x509", make(folder, "other-vm", f"URI:{URI}", cert=True)), "a certificate with another CN stops"
        assert stops("req", "not a pem"), "a text that is no CSR stops"
        good = make(folder, NAME, f"URI:{URI}")
        der = bytearray(base64.b64decode("".join(good.splitlines()[1:-1])))
        der[-1] ^= 0xFF  # the last byte is in the signature
        body = base64.b64encode(bytes(der)).decode()
        lines = [body[i : i + 64] for i in range(0, len(body), 64)]
        tampered = "\n".join(["-----BEGIN CERTIFICATE REQUEST-----", *lines, "-----END CERTIFICATE REQUEST-----"]) + "\n"
        assert stops("req", tampered), "a CSR with a broken signature stops"

    csr = "-----BEGIN CERTIFICATE REQUEST-----\nAAAA\n-----END CERTIFICATE REQUEST-----\n"
    request = msb._certificate_request(NAME, csr)
    assert request["spec"]["usages"] == ["digital signature"], "the key usage the x509pop plugin needs"
    assert request["spec"]["issuerRef"]["name"] == "node-ca"
    assert base64.b64decode(request["spec"]["request"]).decode() == csr, "the CSR travels as base64 of the PEM"
    print("all checks pass")


if __name__ == "__main__":
    main()
