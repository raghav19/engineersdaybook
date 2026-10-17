# How to organize the `.sbx` just recipes

Question: 18 recipes in one flat list do not show where each runs or in what order. What can just do about it?

Source: the just manual, version 1.58.0 (the installed version). https://just.systems/man/en/

## Findings

| Claim | Manual section |
|---|---|
| `mod foo` makes `just foo <recipe>` and `just foo::<recipe>`. A module looks for `foo.just`, `foo/mod.just`, `foo/justfile`. `mod foo 'PATH'` sets the file. | Modules |
| A module cannot use the recipes, aliases or variables of another module. Each module has its own settings. | Modules |
| A recipe in a module runs in the folder of the module file, unless it has `[no-cd]`. | Modules |
| A recipe may depend on a module recipe: `baz: foo::bar`. | Dependencies |
| `import` merges the file into one namespace. Importing the same file twice is not an error. | Imports |
| `[group('name')]` works on recipes and modules. Groups sort by name. | Groups |
| `--list` sorts recipes by name. `--unsorted` keeps the order of the file. `--list-submodules` shows module recipes. | Listing Available Recipes |
| The comment line right above a recipe is its doc text in `--list`. | Documentation Comments |
| A name that starts with `_` is private and is not listed. | Private Recipes |

## Tested on just 1.58.0 in a throwaway copy

- A private recipe in a module can be a dependency of a parent recipe (`run: host::_check-proxy`).
- A file imported by the parent and by each module (`lib/common.just`) gives each one its own copy of the variables and checks. `source_directory()` inside it is the folder of `common.just`, so `sbx_dir` is its parent.
- A recipe dependency replaces a `just <recipe>` call inside a module. `&&` runs a recipe after the body, so `daemon-restart: daemon-stop && daemon-start` stops first and starts last.
- `set lazy` and the other settings are per module. Each module file repeats them.
- `--dry-run` prints a `shell(...)` variable as its source text. A real run prints the value.

## Decision

Two modules, `host` and `agent`, with `lib/common.just` for what they share (the same place and name as Part 3's `lib/workflow/common.just`, and no loose file at the top of `.sbx/`). The path (`just sandbox host daemon-start`) says what a recipe changes. A "Step N of 6" doc comment says the order. `help` uses `--unsorted`, so the list follows the file order.

Rejected: name prefixes in one namespace (`host-daemon-start`). It keeps `run` simple, but just does not know about the split, so `--list` stays one flat list.

## Kit layout (Docker kit v3)

Sources: SPEC-v3 sections 3, 4, 6, 7.4, 9 and 12, the `network-policy@2`, `credential@1` and `volume@1` pages, and the `dev-tools`, `shell` and `team` examples.
https://github.com/docker/sandbox-kit-spec

- A kit is a folder with `<kit>.yaml`, `<kit>.dockerfile` and optional `<kit>-context.md`. The folder is the build context (spec section 3.1).
- A mixin may have no recipe. It is then one descriptor layer (spec section 3.5).
- The permission gate compares the surface of each kit (spec section 7.4). Policy in its own kit shows a new host as one small widening.
- Docker's own `dev-tools` example keeps tools and egress in one kit. Both layouts are valid. The repo splits them because the allow list changed in 12 of 33 commits to the old kit file.
- The old build sent the whole repository as context. There was no `.dockerignore`. The new context is 2.61 kB.
- The build date of a kit is the time of its last commit, README excluded. A new host leaves the digest of `dev-tools` as it is.

## Kubeconfig token for the VM (tested, did not work)

Goal: the VM holds no token. An sbx custom secret (`sbx secret set-custom --host host.docker.internal --placeholder ... --command ... --refresh 6h`) would let the proxy replace a placeholder with a token that the host mints. Source: `sbx secret set-custom` and the credentials page on docs.docker.com.

Tested from inside the sandbox, after `kubeconfig-install` had registered the secret:

- `openssl s_client -proxy gateway.docker.internal:3128 -connect host.docker.internal:6444` returns the kind API server certificate (`issuer=CN=kubernetes`). The proxy passes this TLS session through.
- The same test for `api.anthropic.com:443` returns a certificate from "Docker Sandboxes Proxy CA", which the VM trusts. The proxy does open TLS for some hosts, not for this one.
- `kubectl get namespaces --insecure-skip-tls-verify` returns `Unauthorized`: the API server got the placeholder unchanged.

Result: the VM needs a real token in a kubeconfig that the host writes. The repo keeps that design: `agent kubeconfig-install` once per cluster, and `agent kubeconfig` at every `run`, with a 30-day token (`SANDBOX_KUBE_TOKEN_DURATION`). Open question for a later try: why the proxy skips this host (the port, or a host that is not a known service).
