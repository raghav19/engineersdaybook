# Sandbox network

The agent sandbox has no network device. Its only way out is the host proxy, which allows the hosts in `.devcontainer/agent/proxy/iron-proxy.yaml`. The builder has its own proxy and its own list in `.devcontainer/builder/proxy/iron-proxy.yaml`.

If a tool, download or API call gets a `403` inside the sandbox, the target host is likely missing from the list. Do not try to work around it. Tell the user to add the host to the right file and to run on the host:

```
just sandbox run
```

Then retry. A `FROM` or `RUN` step of `docker build` uses the builder list. Every other call uses the host proxy list. Wildcards work (`*.example.com`).
