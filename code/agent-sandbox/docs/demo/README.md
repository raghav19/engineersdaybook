# Demo script

`demo.sh` runs the sandbox demo in one terminal window, about 45 seconds, in three sections, one per Anthropic principle. It simulates the flow of the main README's [demo](../../README.md#demo-the-sandbox-in-45-seconds).

```shell
./docs/demo/demo.sh     # from code/agent-sandbox
```

## Before you run it

- The sandbox is running: `sbx ls` shows `sandbox-dev` as `running` (`task sandbox:run`).
- Use one terminal window with a large font. The script prints variable names and status codes, never secret values.

## What it shows

| Section | What you see |
|---|---|
| 1. Limit what the agent is able to do | two kernels; `github.com` 200, `example.com` 403, a repo `DELETE` 403; the tools the agent sees, with merge and delete absent and `issue_write` present; `merge_pull_request` returns `unknown tool`; the proxy's log line for the refused `DELETE` |
| 2. Credentials never enter the sandbox | `ls ~/.ssh ~/.aws` fails, user `agent`; token variable names; `GH_TOKEN` gets 401 from GitHub; a direct call to the MCP host is 403; `list_branches` works through the gateway with no token in the VM |
| 3. An allowed domain is a capability grant | a dummy string is delivered to `registry.terraform.io` and to an S3 bucket nobody owns; an untracked host file is readable at `/run/sandbox/source`; the write tools are still open |

It makes no model call, so a run costs no tokens. Section 3 sends two dummy strings (`demo-canary-not-a-secret`) to third-party hosts, and creates then removes `.demo-canary-untracked.txt` in the repo directory.

## Run one part on its own

`mcp-call.sh` talks to the sbx MCP gateway (`http://mcp-gateway.docker.internal/mcp`, the VM's only MCP endpoint) with plain `curl`. `demo.sh` uses it, so keep the two together.

```shell
ssh sandbox-dev.sbx 'bash -s -- tools'                       < docs/demo/mcp-call.sh   # the tool list the agent sees
ssh sandbox-dev.sbx 'bash -s -- call merge_pull_request {}'  < docs/demo/mcp-call.sh   # error: unknown tool
ssh sandbox-dev.sbx 'bash -s -- branches'                    < docs/demo/mcp-call.sh   # list_branches, no token in the VM
```
