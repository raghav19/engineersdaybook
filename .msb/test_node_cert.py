#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = ["ruamel.yaml==0.19.1"]
# ///
"""Self-check of the parts of `msb.py provision` that decide: when the node certificate stays, and how a file is replaced.

Run it with `uv run .msb/test_node_cert.py`. It makes real keys and certificates with openssl in a temporary folder. It needs no VM and no cluster.
"""

import importlib.util
import subprocess
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("msb", Path(__file__).resolve().parent / "msb.py")
assert spec and spec.loader
msb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(msb)


def make_key(path: Path) -> Path:
    subprocess.run(
        ["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", str(path)],
        check=True,
        capture_output=True,
    )
    return path


def make_cert(key: Path, days: int, out: Path) -> Path:
    subprocess.run(
        ["openssl", "req", "-x509", "-key", str(key), "-subj", "/CN=sandbox-dev", "-days", str(days), "-out", str(out)],
        check=True,
        capture_output=True,
    )
    return out


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        key = make_key(folder / "key.pem")
        other = make_key(folder / "other.pem")
        assert not msb._cert_ok(key, folder / "none.crt"), "no certificate: make one"
        assert msb._cert_ok(key, make_cert(key, 90, folder / "d90.crt")), "a 90-day certificate stays"
        assert msb._cert_ok(key, make_cert(key, msb.NODE_RENEW_DAYS + 2, folder / "d32.crt")), "a certificate with 32 days left stays"
        assert not msb._cert_ok(key, make_cert(key, msb.NODE_RENEW_DAYS - 2, folder / "d28.crt")), (
            "a certificate with 28 days left is renewed"
        )
        assert not msb._cert_ok(key, make_cert(other, 90, folder / "other.crt")), "a certificate of another key is replaced"

        target = folder / "file.txt"
        target.write_text("old")
        msb._write(target, "new", 0o600)
        assert target.read_text() == "new" and oct(target.stat().st_mode & 0o777) == "0o600", "the file is replaced, with the mode"
        assert not (folder / "file.txt.new").exists(), "no half-written file stays"
    print("all checks pass")


if __name__ == "__main__":
    main()
