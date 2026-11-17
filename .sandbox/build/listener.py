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
2. Check each field. A field that does not match its pattern ends the build.
3. Export the context from the registry by its digest. It is a tar. Stop at 64 MB.
4. Run the builder in gVisor. The builder unpacks the tar in its own container and builds.
   The output of the builder goes straight to the agent, as the builder prints it.
   The last line is "sandbox-build: exit N". The agent ends with the same exit code.

The host never reads the tar. A bad path or link in it can only harm the builder, which is gone after the build.
Stop the listener with Ctrl-C.
"""

import json
import os
import re
import secrets
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "")
SOCKET = Path(os.environ.get("SANDBOX_BUILD_SOCKET", f"{RUNTIME}/sandbox/build.sock"))
# The registry and the account that hold the contexts. The agent pushes the context to REGISTRY/build-context.
REGISTRY = os.environ.get("SANDBOX_BUILD_REGISTRY", "ghcr.io/raghav19/engineersdaybook")
BUILDER_IMAGE = os.environ.get("SANDBOX_BUILDER_IMAGE", "localhost/sandbox-dev:latest")
# Each build keeps its tar here. The folder is private to your user.
WORK = Path(RUNTIME) / "sandbox-build"

MAX_BYTES = 64 * 1024 * 1024
READ_SECONDS = 10
BUILD_SECONDS = 1800

# The agent chooses these three values. Each pattern accepts only what the build needs.
IMAGE_PATTERN = re.compile(r"[a-z0-9][a-z0-9._-]{0,62}:[A-Za-z0-9._-]{1,64}")
FILE_PATTERN = re.compile(r"(?!.*\.\.)[A-Za-z0-9._][A-Za-z0-9._/-]{0,127}")
CONTEXT_PATTERN = re.compile(rf"{re.escape(REGISTRY)}/build-context@sha256:[0-9a-f]{{64}}")

# This runs in the builder as the user agent. The script gets the file and the image as $1 and $2, never inside the text.
BUILDER_SCRIPT = (
    "mkdir /tmp/work && tar -x -C /tmp/work -f /context.tar && "
    'exec podman build --isolation=chroot --storage-driver=vfs -f "/tmp/work/$1" -t "$2" /tmp/work'
)


def reply(conn: socket.socket, text: str) -> None:
    """Send text to the agent. Do nothing if the agent is gone."""
    try:
        conn.sendall(text.encode())
    except OSError:
        pass


if not RUNTIME:
    sys.exit("XDG_RUNTIME_DIR is empty. Run the listener in your user session.")
WORK.mkdir(mode=0o700, exist_ok=True)
SOCKET.unlink(missing_ok=True)

try:
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(SOCKET))
        # The folder of the socket is below the 0700 folder of your session. Only your user and the sandbox reach it.
        SOCKET.chmod(0o666)
        server.listen()
        print(f"the listener waits on {SOCKET}", flush=True)

        while True:
            conn, _ = server.accept()
            with conn, tempfile.TemporaryDirectory(dir=WORK, prefix="build-") as folder:
                # Step 1: read the spec. It is the first line, and it ends with a newline.
                conn.settimeout(READ_SECONDS)
                try:
                    line = conn.makefile("rb").readline(4097)
                except TimeoutError:
                    line = b""
                conn.settimeout(None)
                try:
                    spec = json.loads(line) if line.endswith(b"\n") else None
                except ValueError:
                    spec = None

                # Step 2: check the spec. The first problem ends the build with exit code 2.
                problem = None
                if not isinstance(spec, dict) or set(spec) != {"image", "file", "context"}:
                    problem = "the first line must be JSON with the fields image, file and context. It has at most 4096 bytes and arrives in 10 seconds"
                elif not all(isinstance(value, str) for value in spec.values()):
                    problem = "each field of the spec must be a string"
                elif not IMAGE_PATTERN.fullmatch(spec["image"]):
                    problem = "the image must look like name:tag, with lowercase letters, digits, dot, dash or underscore"
                elif not FILE_PATTERN.fullmatch(spec["file"]):
                    problem = "the file must be a relative path in the context, with no '..'"
                elif not CONTEXT_PATTERN.fullmatch(spec["context"]):
                    problem = f"the context must be {REGISTRY}/build-context@sha256:<64 hex characters>"
                if problem or spec is None:
                    reply(conn, f"sandbox-build: rejected: {problem}\nsandbox-build: exit 2\n")
                    print(f"rejected: {problem}", flush=True)
                    continue

                # Step 3: export the context from the registry into a tar file. Stop at 64 MB.
                archive = Path(folder) / "context.tar"
                size = 0
                with (
                    subprocess.Popen(["crane", "export", spec["context"], "-"], stdout=subprocess.PIPE) as export,
                    archive.open("wb") as out,
                ):
                    while export.stdout and (chunk := export.stdout.read(1 << 20)):
                        size += len(chunk)
                        if size > MAX_BYTES:
                            export.kill()
                            break
                        out.write(chunk)
                if size > MAX_BYTES or export.returncode != 0:
                    problem = "the context is larger than 64 MB" if size > MAX_BYTES else "crane could not export the context"
                    reply(conn, f"sandbox-build: rejected: {problem}\nsandbox-build: exit 2\n")
                    print(f"rejected: {problem}", flush=True)
                    continue

                # Step 4: run the builder. podman writes to the socket itself. If the agent disconnects, the next write ends podman.
                name = f"sandbox-build-{secrets.token_hex(4)}"
                # runsc ignores the memory limit of podman. --timeout stops the container after BUILD_SECONDS.
                command = [
                    "podman", "run", "--rm", "--name", name, f"--timeout={BUILD_SECONDS}",
                    "--runtime=runsc", "--network=none", "--user=1000", "--env", "PODMAN_IGNORE_CGROUPSV1_WARNING=1",
                    "--cap-drop=ALL", "--cap-add=SETUID", "--cap-add=SETGID", "--cap-add=SYS_CHROOT",
                    "--volume", f"{archive}:/context.tar:ro",
                    "--entrypoint", "sh", BUILDER_IMAGE, "-c", BUILDER_SCRIPT, "sh", spec["file"], spec["image"],
                ]  # fmt: skip
                # The warning about cgroups v1 comes from podman on the host and from podman in the builder. The agent does not need it.
                environment = {**os.environ, "PODMAN_IGNORE_CGROUPSV1_WARNING": "1"}
                code = subprocess.run(command, env=environment, stdout=conn.fileno(), stderr=subprocess.STDOUT, check=False).returncode
                # Remove the container if podman ended and left it. This does nothing if the container is gone.
                subprocess.run(["podman", "rm", "-f", name], check=False, capture_output=True)
                reply(conn, f"sandbox-build: exit {code}\n")
                print(f"{spec['image']} from {spec['context']}: exit {code}", flush=True)
except KeyboardInterrupt:
    print("the listener stops")
finally:
    SOCKET.unlink(missing_ok=True)
