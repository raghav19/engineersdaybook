# policy kit

A Docker kit v3 mixin with no recipe: one descriptor layer.

| File | What it is |
|---|---|
| `policy.yaml` | the egress allow list and the deny rule (`network-policy@2`, runtime phase) |
| `policy-context.md` | the note for the agent: GitHub access goes through the host MCP gateway |

- A new host is one line in `policy.yaml`. The digest of the `dev-tools` kit does not change.
- Build and publish: `just sandbox agent kit-build policy`. Then create a new sandbox.
- To allow the hosts in the host sbx policy now, without a new sandbox: `just sandbox agent allow-hosts`.
