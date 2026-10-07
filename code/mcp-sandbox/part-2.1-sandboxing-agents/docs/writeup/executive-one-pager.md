# Sandboxing Agents

## The Problem

A coding agent runs **as you**. Anyone who can put text in front of it (an issue, a web page, a tool result) can try to steer it, and it cannot reliably tell their text from yours. At risk: **host credentials**, **data exfiltration**, **over-powered tokens**, and **files that later run on your host**.

## The Solution

Claude Code runs inside an **`sbx` microVM** on a **private clone** of the repo, holding **no real credential**. A **host proxy** applies an **egress allow and deny list** and injects a short-lived GitHub App token **only** on the MCP host.

## Anthropic's Principles

- Supervise what the agent is **able** to do, not what it does.
- If **credentials never enter** the sandbox, they can't be exfiltrated.
- Every function reachable through an **allowed domain** is an attack surface.

## How It Runs

1. Run `task sandbox:run` and approve the plan.
2. A **microVM** starts with a **private clone** of the repo.
3. Claude works inside; every request goes through the **host proxy**.
4. Fetch its commits, **review**, then merge.

## Summary

| Threat | Solution | Gap |
|---|---|---|
| Compromised MCP server | ✅ Stopped | none |
| Credential theft or misuse | ✅ Stopped | none |
| Tampered images | ✅ Stopped | kits unsigned |
| Data leaving | ⚠️ Partly | broad baseline domains |
| Files run on host | ⚠️ Partly | review before merging |
| Over-powered MCP tools | ⚠️ Partly | proxy can't tell read from delete; needs gateway |
| Injected instructions | ❌ Not stopped | needs detection |
| Poisoned tool results | ❌ Not stopped | results not inspected |
