#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.13.*"
# dependencies = []
# ///
"""The GitHub login of the sandbox: github.py <step>

login  log in with the device flow of the GitHub App: you type a code in the browser. The tokens go to a file with mode 600

The module also defines github_token(), which vm.py calls. It returns the access token and refreshes it when it expires soon.
Nothing here prints a token. The VM never has a token: it has a placeholder, and the host replaces it on the network.
"""

import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from common import die

# The GitHub App of this repository. The client ID is public. You installed the app on this repository only, with the permissions contents,
# issues and pull requests. So the token cannot do more. The access token lasts 8 hours. The refresh token lasts about 6 months, and each
# refresh gives a new one. So the tokens go in a file on the host (mode 600).
GITHUB_CLIENT_ID = "Iv23liVvjK9IHk8lWmIh"
GITHUB_TOKEN_FILE = Path.home() / ".config" / "msb" / "github-app.json"
REFRESH_MARGIN = 1800  # seconds. A token that expires in less time is refreshed


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


def main() -> None:
    """Read the step from the command line and call its function."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    steps = parser.add_subparsers(dest="step", required=True)
    steps.add_parser("login")
    match parser.parse_args().step:
        case "login":
            github_login()


if __name__ == "__main__":
    main()
