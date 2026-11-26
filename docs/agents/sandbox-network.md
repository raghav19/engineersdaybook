# Sandbox network

The agent sandbox sits on an internal Docker network. Its only way out is the proxy, which allows the hosts in `.devcontainer/policy/agent.yaml`. The builder has its own proxy and its own list in `.devcontainer/policy/builder.yaml`.

If a tool, download or API call gets a `403` inside the sandbox, the target host is likely missing from the list. Do not try to work around it. Tell the user to add the host to the right file and to run on the host:

```
just sandbox apply
```

Then retry. A `FROM` or `RUN` step of `docker build` uses the builder list. Every other call uses the agent list, including the registry login of `docker build`. Wildcards work (`*.example.com`).
