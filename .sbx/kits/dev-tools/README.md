# dev-tools kit

A Docker kit v3 mixin. It adds the sandbox tools to the shell and Claude kits.

| File | What it is |
|---|---|
| `dev-tools.yaml` | the descriptor: the `workspace` arg, the Terraform cache volume, the shell setup |
| `dev-tools.dockerfile` | the recipe: installs mise, the tools of `tools.toml` and their completions |
| `tools.toml` | the tools at exact versions. It is mise's system config in the VM |

- This folder is the build context. The build reads no file outside it.
- The egress rules and the agent note are the `policy` kit (`../policy/`).
- Build and publish: `just sandbox agent kit-build dev-tools`. The recipe pins the digest in `../../sbxenv.yaml`.
- The version is `version:` in `dev-tools.yaml`. Change it there and nowhere else.
