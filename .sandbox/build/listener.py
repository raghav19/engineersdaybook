#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The build listener: listener.py

`just sandbox build-listen` runs it on the host. It takes one build at a time from the socket build.sock.
The agent in the sandbox connects with the command sandbox-build. The builds wait in the listen queue of the socket.

The steps of one build:
1. Read one line of JSON. It has three fields: image, file and context.
2. Check each field. A field that does not match the pattern ends the build.
3. Export the context from the registry by its digest. It is a tar. Stop at 64 MB.
4. Unpack the tar into a private folder. The data filter of tarfile refuses paths and links that leave the folder.
5. Run the builder in gVisor. Send each line of its output to the agent as the builder prints it.
6. Send the last line: "sandbox-build: exit N". The agent ends with the same exit code.

Stop it with Ctrl-C.
"""

import json
import os
import re
import secrets
import socket
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import NamedTuple

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "")
SOCKET = Path(os.environ.get("SANDBOX_BUILD_SOCKET", f"{RUNTIME}/sandbox/build.sock"))
# The registry and the account that hold the contexts. The agent pushes the context to REGISTRY/build-context.
REGISTRY = os.environ.get("SANDBOX_BUILD_REGISTRY", "ghcr.io/raghav19/engineersdaybook")
BUILDER_IMAGE = os.environ.get("SANDBOX_BUILDER_IMAGE", "localhost/sandbox-dev:latest")
# Each build unpacks here. The folder is private to your user.
WORK = Path(RUNTIME) / "sandbox-build"

MAX_BYTES = 64 * 1024 * 1024
READ_SECONDS = 10
BUILD_SECONDS = 1800

# The agent chooses these values. Each pattern accepts only what the build needs.
CONTEXT_PATTERN = re.compile(rf"{re.escape(REGISTRY)}/build-context@sha256:[0-9a-f]{{64}}")
IMAGE_PATTERN = re.compile(r"[a-z0-9][a-z0-9._-]{0,62}:[A-Za-z0-9._-]{1,64}")
FILE_PATTERN = re.compile(r"[A-Za-z0-9._][A-Za-z0-9._/-]{0,127}")


class Rejected(Exception):
    """The listener refuses a build. The message goes to the agent."""


class Spec(NamedTuple):
    image: str
    file: str
    context: str


def check(line: bytes) -> Spec:
    """Turn the first line of the connection into a spec. Raise Rejected if a field is not allowed."""
    try:
        raw = json.loads(line)
    except ValueError:
        raise Rejected("the spec is not JSON") from None
    if not isinstance(raw, dict) or set(raw) != {"image", "file", "context"}:
        raise Rejected("the spec needs the fields image, file and context")
    if not all(isinstance(value, str) for value in raw.values()):
        raise Rejected("each field of the spec must be a string")
    spec = Spec(raw["image"], raw["file"], raw["context"])
    if not IMAGE_PATTERN.fullmatch(spec.image):
        raise Rejected("the image must look like name:tag, with lowercase letters, digits, dot, dash or underscore")
    if not FILE_PATTERN.fullmatch(spec.file) or ".." in Path(spec.file).parts:
        raise Rejected("the file must be a relative path in the context, with no '..'")
    if not CONTEXT_PATTERN.fullmatch(spec.context):
        raise Rejected(f"the context must be {REGISTRY}/build-context@sha256:<64 hex characters>")
    return spec


def fetch(context: str, folder: Path) -> Path:
    """Export the context from the registry and unpack it. Return the folder with the files."""
    archive = folder / "context.tar"
    files = folder / "ctx"
    files.mkdir(mode=0o755)
    with subprocess.Popen(["crane", "export", context, "-"], stdout=subprocess.PIPE) as export, archive.open("wb") as out:
        if export.stdout is None:
            raise RuntimeError("crane has no output")
        size = 0
        while chunk := export.stdout.read(1 << 20):
            size += len(chunk)
            if size > MAX_BYTES:
                export.kill()
                raise Rejected("the context is larger than 64 MB")
            out.write(chunk)
    if export.returncode != 0:
        raise Rejected("crane could not export the context from the registry")
    try:
        with tarfile.open(archive) as tar:
            tar.extractall(files, filter="data")
    except tarfile.TarError as error:
        raise Rejected(f"the context has a path or a link that is not allowed ({error})") from None
    # The builder runs as another user than you. It needs the read bit for all users.
    subprocess.run(["chmod", "-R", "a+rX", files], check=True)
    return files


def build(spec: Spec, files: Path, conn: socket.socket) -> int:
    """Run the builder and send its output to the agent line by line. Return the exit code of the build."""
    name = f"sandbox-build-{secrets.token_hex(4)}"
    # runsc ignores the memory limit of podman. --timeout stops the container after BUILD_SECONDS.
    command = [
        "podman", "run", "--rm", "--name", name, f"--timeout={BUILD_SECONDS}",
        "--runtime=runsc", "--network=none", "--user=1000",
        "--cap-drop=ALL", "--cap-add=SETUID", "--cap-add=SETGID", "--cap-add=SYS_CHROOT",
        "--volume", f"{files}:/ctx:ro",
        "--entrypoint", "podman", BUILDER_IMAGE,
        "build", "--isolation=chroot", "--storage-driver=vfs", "-f", f"/ctx/{spec.file}", "-t", spec.image, "/ctx",
    ]  # fmt: skip
    # The warning about cgroups v1 comes from the host. It is not part of the build, so the agent does not need it.
    environment = {**os.environ, "PODMAN_IGNORE_CGROUPSV1_WARNING": "1"}
    with subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
        if process.stdout is None:
            raise RuntimeError("podman has no output")
        for line in process.stdout:
            try:
                conn.sendall(line)
            except OSError:
                # The agent is gone. Stop the build.
                subprocess.run(["podman", "rm", "-f", name], check=False, capture_output=True)
                break
        return process.wait()


def send(conn: socket.socket, text: str) -> None:
    """Send text to the agent. Do nothing if the agent is gone."""
    try:
        conn.sendall(text.encode())
    except OSError:
        pass


def handle(conn: socket.socket) -> None:
    """Do one build for one connection."""
    code = 1
    summary = "no spec"
    try:
        conn.settimeout(READ_SECONDS)
        line = conn.makefile("rb").readline(4097)
        conn.settimeout(None)
        if not line.endswith(b"\n"):
            raise Rejected("the first line must be the spec. It ends with a newline and has at most 4096 bytes")
        spec = check(line)
        summary = f"{spec.image} from {spec.context}"
        with tempfile.TemporaryDirectory(dir=WORK, prefix="build-") as folder:
            files = fetch(spec.context, Path(folder))
            code = build(spec, files, conn)
    except Rejected as error:
        send(conn, f"sandbox-build: rejected: {error}\n")
        code = 2
    except TimeoutError:
        code = 2
        send(conn, "sandbox-build: rejected: the spec did not arrive in 10 seconds\n")
    send(conn, f"sandbox-build: exit {code}\n")
    print(f"{summary}: exit {code}", flush=True)


def main() -> None:
    if not RUNTIME:
        sys.exit("XDG_RUNTIME_DIR is empty. Run the listener in your user session.")
    WORK.mkdir(mode=0o700, exist_ok=True)
    SOCKET.unlink(missing_ok=True)
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(SOCKET))
        # The folder of the socket is below the 0700 folder of your session. Only your user and the sandbox reach it.
        SOCKET.chmod(0o666)
        server.listen()
        print(f"the listener waits on {SOCKET}", flush=True)
        while True:
            conn, _ = server.accept()
            with conn:
                handle(conn)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("the listener stops")
    finally:
        SOCKET.unlink(missing_ok=True)
