# Playwright MCP for agent browser testing

Question: Does the Playwright MCP server add value to this repo as a browser test tool for the agent?

Source: `@playwright/mcp` v0.0.83 (released 2026-09-28). Research date: 2026-10-19.

Evidence tags: **[repo]** means the claim comes from a file in this repo. **[primary]** means the claim comes from the Playwright project (README, docs source, code, or issues).

## Verdict

Do not add Playwright MCP now.

1. The repo has no web UI that it builds and serves. A browser test has nothing to test.
2. The sandbox egress policy blocks the browser download. It also blocks browsing to arbitrary sites.
3. The Playwright project says Playwright MCP is not a security boundary. The repo threat model treats web pages as untrusted input.

Revisit this verdict when the repo gets a web UI that the agent must check in a browser.

If that happens, use this order:

1. Write `@playwright/test` specs. They run without an LLM.
2. Use `playwright-cli` with skills for agent debugging. It uses fewer tokens.
3. Use Playwright MCP last, only for exploratory work.

## Findings: this repo

| Claim | Source |
|---|---|
| No project builds and serves a web UI. Part 3 has an HTTP MCP endpoint. Its tests use `curl` and shell scripts. | [repo] `code/mcp-sandbox/part-3-mcp-guardrails/tests/justfile:13-17` |
| The dashboards in `devk8s-kind-wsl2` are third-party charts and operators. | [repo] `code/devk8s-kind-wsl2/README.md:21-23,84-115` |
| The Jekyll site is archived. `prek` excludes it. | [repo] `prek.toml:4` |
| The repo has no CI and no browser or e2e test. The checks are `prek` hooks. | [repo] `prek.toml:6-45` (`.github/` does not exist) |
| The sandbox VM has Node and `npx`. It has no Chromium and no Playwright. | [repo] [`.sbx/kits/dev-tools/tools.toml:5,16-35`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/dev-tools/tools.toml) |
| The egress policy is an allow list. It lists no Playwright download host. | [repo] [`.sbx/kits/policy/policy.yaml:17-71`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/policy/policy.yaml) |
| MCP servers register on the host gateway. The repo has no `.mcp.json`. | [repo] [`.sbx/agent/agent.just:87-102`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/agent/agent.just) |
| A web page is an untrusted-content channel. The sandbox has no control for it. | [repo] `code/agent-sandbox/README.md:43,313-321` |
| An allowed domain is a capability grant. | [repo] `code/agent-sandbox/README.md:25,344-346` |
| The sbx baseline allows shared-hosting wildcards such as `**.amazonaws.com`. | [repo] `code/agent-sandbox/README.md:296` |
| The gateway does not log rejected tool calls or their arguments. | [repo] `code/agent-sandbox/README.md:360-363` |
| The agent can read the repo directory at `/run/sandbox/source`, including untracked files. | [repo] `code/agent-sandbox/README.md:303` |
| Sandboxing the MCP server process does not stop the lethal trifecta. | [repo] `code/mcp-sandbox/part-1-lethal-trifecta/README.md:11` |

## Findings: Playwright MCP

| Claim | Source |
|---|---|
| The latest release is v0.0.83 (2026-09-28). The version is pre-1.0. | https://github.com/microsoft/playwright-mcp/releases |
| The server code now lives in the Playwright monorepo. | https://github.com/microsoft/playwright-mcp/blob/main/src/README.md |
| The server works from accessibility snapshots. It needs no vision model. | https://github.com/microsoft/playwright/blob/main/docs/src/getting-started-mcp.md |
| Install for Claude Code: `claude mcp add playwright npx @playwright/mcp@latest`. | https://github.com/microsoft/playwright-mcp/blob/main/README.md |
| The default mode is headed. Use `--headless` when no display exists. | https://github.com/microsoft/playwright-mcp/blob/main/README.md |
| "Playwright MCP is **not** a security boundary." | https://github.com/microsoft/playwright-mcp/blob/main/README.md (Security) |
| `--allowed-origins` and `--blocked-origins` are not a security boundary. They do not affect redirects. | https://github.com/microsoft/playwright-mcp/blob/main/README.md |
| By default, `file://` navigation and file access outside the workspace are blocked. The project calls this a convenience, not a secure boundary. | https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/tools/mcp/config.d.ts (`--allow-unrestricted-file-access`) |
| `browser_run_code_unsafe` is "RCE-equivalent." It is in the default tool set. | https://github.com/microsoft/playwright/blob/main/docs/src/getting-started-mcp.md |
| The project closed a prompt-injection report and pointed to the README security note. | https://github.com/microsoft/playwright-mcp/issues/1479 |
| The project recommends a sandbox with controlled network access for sensitive use. | https://github.com/microsoft/playwright-mcp/issues/1626 |
| The Docker image `mcr.microsoft.com/playwright/mcp` is headless Chromium only. It runs with `--no-sandbox`. | https://github.com/microsoft/playwright-mcp/blob/main/Dockerfile |
| On Linux, a downloaded Chromium build defaults to no sandbox. | https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/tools/mcp/config.ts |
| The root user disables the Chromium sandbox. For untrusted sites, use a separate user and the seccomp profile. | https://github.com/microsoft/playwright/blob/main/docs/src/docker.md |
| Browsers are not bundled. The server prints an install command when one is missing. | https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/tools/mcp/browserFactory.ts |
| Browser download hosts: `cdn.playwright.dev` and `playwright.download.prss.microsoft.com`. | https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/server/registry/index.ts |
| `install-deps` needs root or sudo on Debian and Ubuntu. | https://github.com/microsoft/playwright/blob/main/docs/src/browsers.md |
| `playwright-cli` suits coding agents. It avoids large tool schemas and verbose accessibility trees. | https://github.com/microsoft/playwright/blob/main/docs/src/getting-started-cli.md |
| MCP suits "specialized agentic loops" such as exploratory automation. | https://github.com/microsoft/playwright/blob/main/docs/src/getting-started-cli.md |
| Playwright ships Test Agents (planner, generator, healer). Set up with `npx playwright init-agents --loop=claude`. | https://github.com/microsoft/playwright/blob/main/docs/src/test-agents-js.md |
| One browser instance can use a persistent profile at a time. Use `--isolated` for parallel clients. | https://github.com/microsoft/playwright-mcp/blob/main/README.md |
| Tools for storage, network, devtools, pdf, vision, and testing need `--caps`. | https://github.com/microsoft/playwright-mcp/blob/main/README.md |

## Gaps and conflicts

- `playwright.dev` returned HTTP 403 in the research environment. The docs above come from `microsoft/playwright/docs/src/*.md` on GitHub. The live site wording may differ.
- No primary source gave the browser download size.
- No primary source compares MCP with `@playwright/test` on token cost, determinism, or CI. The determinism claim for specs is an inference.
- No primary source gave a hard limit on tool-output size.
- No primary source covers root in a microVM. Only the Docker doc covers root.
- The Node requirement conflicts. The README says 18 or newer. The getting-started docs say 20 or newer. The system-requirements section says 22, 24, or 26. Target 22 or newer.
- The `modelcontextprotocol.io` security page was not read. The README links to it.

## If the team adopts it later

- Add Chromium and `install-deps` to the dev-tools image ([`.sbx/kits/dev-tools/`](https://github.com/raghav19/engineersdaybook/tree/docker-sbx/.sbx/kits/dev-tools/)).
- Add the two Playwright download hosts to [`.sbx/kits/policy/policy.yaml`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/policy/policy.yaml) for the build step only.
- Pin the `@playwright/mcp` version. Do not use `@latest`.
- Run it with `--headless --isolated`. Enforce the browsing allow list at the network level, not with `--allowed-origins`.
- Register it on the gateway only after a threat review against `code/agent-sandbox/README.md`.
