# Sandbox network

The msb sandbox VM blocks all egress except hosts listed in `network.allow` in `.msb/sandbox.yaml`. If a tool, download, or API call fails with a DNS or connection error inside the sandbox, the target host is likely missing from that allowlist. Do not try to work around it. Tell the user to run on the host:

```
just msb allow-host <host>
just msb rm && just msb run
```

Then retry. Wildcards work (`*.example.com`), but the bare domain must be added separately if needed.
