# Headroom for Claude Code token savings in the sbx sandbox

Question: Can Headroom cut the input tokens of Claude Code in the `.sbx` sandbox, and how do we install it?

Source: `headroom-ai` 0.41.0 (PyPI). Research date: 2026-10-19.

Evidence tags: **[repo]** means the claim comes from a file in this repo or from a check in the sandbox VM. **[primary]** means the claim comes from the Headroom, Claude Code, Docker or PyPI project. **[secondary]** means a third-party report that we did not verify.

## Verdict

Headroom works in the sandbox. The short-task trial saved 1.11%, not 15%. The kit now includes it at the request of the owner, so that long sessions can be measured. Remove it if long sessions also save little.

1. Headroom is a local proxy. Claude Code reaches it through `ANTHROPIC_BASE_URL`. The sandbox needs no new egress rule.
2. The three open risks are closed. The key swap works. The sbx CA is trusted. The proxy runs without the Hugging Face model.
3. The saving is the open question. Savings claims come from the vendor. The one independent report shows 15.3%. The short-task trial shows 1.11%.

Next step:

1. Run `claude-hr` for one long interactive session (an hour or more of real work).
2. Read `/stats` at the end. Compare `total_before_compression` with `input`.
3. Keep Headroom in the kit only if the saving is at least 15%.

## Trial results (2026-10-19, in the VM)

Setup: `uv tool install --python /usr/bin/python3 "headroom-ai[sandbox]==0.41.0"`. Proxy: `headroom proxy --port 8787` with `HEADROOM_TELEMETRY=off`, `HEADROOM_BEACON=off`, `DO_NOT_TRACK=1`, `HEADROOM_UPDATE_CHECK=off`, `HF_HUB_OFFLINE=1`. Client: `ANTHROPIC_BASE_URL=http://127.0.0.1:8787 ENABLE_TOOL_SEARCH=true claude -p ...`.

| Check | Result |
|---|---|
| Install from PyPI in the VM | Passed. No policy change. |
| `GET /readyz` | Passed. Status `healthy`. |
| Key swap by the sbx proxy for a request that Headroom forwards | Passed. A prompt got an answer. No 401. |
| TLS trust of the sbx CA | Passed. No TLS error. The package `truststore` is in the dependencies. |
| Kompress model (`huggingface.co`) | Failed, as expected. Status `degraded`, marked optional. The proxy works without it. |
| Telemetry beacon | The log says `Anonymous upload beacon: DISABLED`. |
| Streaming | Passed. `claude -p` answers worked. |
| Savings, 6 requests in 3 short tasks | **1.11%** (2,111 of 190,582 tokens). The gate was 15%. |

Why the saving is small:

- The prompt cache hit was 93-99% in the log (`cache_hit_pct`). Cached reads are cheap.
- Headroom freezes the cached prefix. It compresses only new content.
- Claude Code already limits the size of a Bash result. The tool output in the test was small.
- The tasks were short, 3 to 4 turns. History compression needs a long session.

What the trial did not test: a long interactive session. The 15% gate is not met. It is also not disproved.

## Findings: this repo and the sandbox

| Claim | Source |
|---|---|
| The dev-tools kit bakes exact tool versions from `tools.toml` at build time. The build runs on the host. | [repo] [`.sbx/kits/dev-tools/dev-tools.dockerfile`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/dev-tools/dev-tools.dockerfile), [`.sbx/kits/dev-tools/tools.toml`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/dev-tools/tools.toml) |
| A kit change needs a version bump, `kit-build`, a new digest in `sbxenv.yaml` and a new sandbox. | [repo] [`.sbx/agent/agent.just`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/agent/agent.just) (`kit-build`), [`.sbx/README.md`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/README.md) |
| The VM has Python 3.14.7 and `uv` 0.12. The shell kit ships them. | [repo] VM check, [`.sbx/kits/dev-tools/tools.toml:5`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/dev-tools/tools.toml) |
| The VM sets `HTTPS_PROXY=http://gateway.docker.internal:3128`. `NO_PROXY` lists `localhost`, `127.0.0.1` and `::1`. | [repo] VM environment |
| `pypi.org`, `files.pythonhosted.org`, `github.com` and `api.anthropic.com` answer from the VM. | [repo] VM check, 2026-10-19 |
| `huggingface.co` and `cdn.pyke.io` return HTTP 403 from the VM. | [repo] VM check, 2026-10-19 |
| The egress policy is an allow list. It lists no Headroom host. | [repo] [`.sbx/kits/policy/policy.yaml`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/policy/policy.yaml) |
| The agent uses deferred MCP tools from the host gateway. Tool search must stay on. | [repo] [`.sbx/kits/policy/policy-context.md`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/policy/policy-context.md), `AGENTS.md` |
| The VM sets `SBX_CRED_ANTHROPIC_MODE=none`. The meaning is not documented. | [repo] VM environment |

## Findings: Headroom

| Claim | Source |
|---|---|
| Headroom compresses tool output, logs, files and history before they reach the model. License: Apache 2.0. | https://github.com/headroomlabs-ai/headroom (README) |
| Install: `uv tool install --python 3.13 "headroom-ai[all]"`. Python 3.10 or newer. | https://github.com/headroomlabs-ai/headroom (README) |
| Release 0.41.0 has a `manylinux_2_28_x86_64` wheel (`cp310-abi3`). | https://pypi.org/pypi/headroom-ai/json |
| The extra `sandbox` has no torch. It holds proxy, code, relevance, reports, otel, html, mcp and spreadsheet. The extra `all` adds torch, voice and more. | https://github.com/headroomlabs-ai/headroom/blob/main/pyproject.toml |
| The proxy binds to `127.0.0.1:8787` by default. Flags: `--host`, `--port`. | https://github.com/headroomlabs-ai/headroom/blob/main/wiki/proxy.md |
| Health: `GET /readyz`. Stats: `GET /stats`. Dashboard: `/dashboard`. | https://github.com/headroomlabs-ai/headroom/blob/main/wiki/proxy.md |
| Claude Code setup: `ANTHROPIC_BASE_URL=http://localhost:8787 claude`. | https://github.com/headroomlabs-ai/headroom/blob/main/wiki/proxy.md |
| `headroom wrap claude` starts the proxy, installs Serena and starts Claude Code. `--code-memory none` skips Serena. | https://github.com/headroomlabs-ai/headroom (README) |
| `headroom wrap claude` sets `ENABLE_TOOL_SEARCH`. A custom base URL otherwise makes Claude Code materialize every tool schema (issue 746). | https://github.com/headroomlabs-ai/headroom/blob/main/headroom/providers/claude/install.py |
| The prompt cache stays valid. Headroom compresses only new content. The prefix stays byte-identical. | https://github.com/headroomlabs-ai/headroom (README) |
| Headroom keeps originals in a local cache (CCR). The model can retrieve them. State is under `~/.headroom`. | https://github.com/headroomlabs-ai/headroom/blob/main/SECURITY.md |
| `proxy.log` is always written. `--log-file` and `--log-messages` also record request content. | https://github.com/headroomlabs-ai/headroom/blob/main/SECURITY.md |
| Control routes need a loopback client. The security policy says any process on the same host is trusted. | https://github.com/headroomlabs-ai/headroom/blob/main/SECURITY.md |
| Only the latest PyPI release gets security fixes. | https://github.com/headroomlabs-ai/headroom/blob/main/SECURITY.md |
| Telemetry off switches: `HEADROOM_TELEMETRY=off`, `HEADROOM_BEACON=off`, `DO_NOT_TRACK=1`, `HEADROOM_OFFLINE=1`. Update check off: `HEADROOM_UPDATE_CHECK=off`. | https://github.com/headroomlabs-ai/headroom (README) |
| Network calls: the model provider, PyPI (update check), `huggingface.co` (Kompress model) and `cdn.pyke.io` (ONNX Runtime). | https://github.com/headroomlabs-ai/headroom (README) |

## Findings: Claude Code and sbx

| Claim | Source |
|---|---|
| `ANTHROPIC_BASE_URL` overrides the API endpoint. Set it in the shell or in the `env` key of `settings.json`. | https://code.claude.com/docs/en/env-vars (read through a search result) |
| For a non-first-party base URL, MCP tool search is off by default. Set `ENABLE_TOOL_SEARCH=true` if the proxy forwards `tool_reference` blocks. | https://code.claude.com/docs/en/env-vars (read through a search result) |
| The sbx proxy swaps the key on requests to `api.anthropic.com`, `console.anthropic.com`, `claude.ai` and `mcp-proxy.anthropic.com`. The agent sees a sentinel such as `proxy-managed`. | https://docs.docker.com/ai/sandboxes/security/credentials/ |
| The key binding command is `sbx secret set anthropic`. | https://docs.docker.com/ai/sandboxes/security/credentials/ |
| Docker says: do not set API keys inside the sandbox. | https://docs.docker.com/ai/sandboxes/security/credentials/ |

## Savings claims

| Claim | Source |
|---|---|
| 20% fewer tokens for coding agents. 60-95% fewer for JSON. | [primary] https://github.com/headroomlabs-ai/headroom (description) |
| Code search 21%, codebase exploration 42%, SRE incident 57%, GitHub issue triage 30%. | [primary] README. The script is `benchmarks/index_proof_table.py --seed 20260902`. |
| 15.3% of input tokens over 15 days (115M of 750.6M). | [secondary] user report in search results. Not verified. |

Use 15% as the realistic low end.

## Gaps and conflicts

- **Telemetry default.** The README says the anonymous beacon is on by default. `wiki/proxy.md` says it is off by default. Neither names the beacon host. The plan turns it off in every way.
- **Model download.** The README names a Kompress model on `huggingface.co`. The VM blocks that host. No source says whether Headroom works without the model.
- **TLS trust.** No source says if Headroom (Python `httpx`) trusts the sbx CA. `HEADROOM_CA_BUNDLE`, `HEADROOM_TLS_STRICT` and `HEADROOM_CERT_STORE` exist. We did not read their docs.
- **Key swap.** The sbx page does not cover a custom `ANTHROPIC_BASE_URL`. It does not confirm the swap for a second process in the VM.
- **Subscription login.** Not studied. This note covers the API key path only.
- **Docs sites.** `docs.headroomlabs.ai` and `code.claude.com` returned HTTP 403. The facts come from `wiki/` in the repo and from search results.
- **Project owner.** Search results show `chopratejas/headroom` and `headroomlabs-ai/headroom`. We did not confirm the PyPI publisher.
- **Install size.** No source states it.
- **Streaming.** The proxy docs do not describe streaming. The trial must show that streamed answers work.

## What the kit does (version 0.2.0)

- `tools.toml` pins `headroom-ai` 0.41.0 with the extra `sandbox` (`pypi:` backend). Read the changelog before each bump.
- `tools.toml` also pins `uv` 0.12. The mise `pypi:` backend needs `uv` or `pipx`, and the build image (`dhi.io/debian-base:trixie-dev`) has neither, nor Python. It fails without them ("pipx" not found). `uv` replaces the shell kit's `uv` on PATH.
- `tools.toml` `[env]` sets `UV_PYTHON_INSTALL_DIR=/opt/mise/uv-python`. mise applies it during the install, so the Dockerfile has no Headroom line. Without it, `uv` downloads Python to `/root/.local/share/uv/python`, which the image does not copy, and the venv breaks. A test in the build image confirmed that with the variable the venv `home` is `/opt/mise/uv-python/...` and `headroom --version` runs after `uv`'s default directory is deleted. The shell kit's `python` is not replaced.
- The install is about 855 MB in the image. The extras `proxy,code` give 774 MB. The base extra `proxy` (onnxruntime, transformers) is most of the size.
- `tools.toml` `[env]` sets `HEADROOM_TELEMETRY=off`, `HEADROOM_BEACON=off`, `HEADROOM_UPDATE_CHECK=off`, `DO_NOT_TRACK=1` and `HF_HUB_OFFLINE=1`.
- `dev-tools.yaml` adds `claude-hr() { headroom wrap claude --code-memory none -- "$@"; }`. Plain `claude` stays the direct path.
- `headroom wrap claude` starts the proxy in the background. The proxy keeps running after Claude Code exits. The command also adds a `headroom` MCP server (`headroom mcp serve`) to `~/.claude.json`.
- `headroom wrap claude` keeps tool search on, and it prints "Remote Control (/rc) is disabled while routed through Headroom".
- The dashboard (`/dashboard`) and `/stats` answer for any `Host` header. The proxy listens on `127.0.0.1` only. Reach the dashboard from the host at `http://127.0.0.1:8787/dashboard`: `sandbox.yaml` publishes the port on the host loopback (`.msb/README.md`).
- The policy kit has no change. The trial needed no new egress host.
- Keep `--log-messages` off.
- If a later version needs the Hugging Face model, bake it into the image at build time. Do not allow `huggingface.co` in the policy kit.
